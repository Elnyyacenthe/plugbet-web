// ============================================================
// PILE OU FACE — Service Supabase
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/coinflip_models.dart';
import '../../../services/game_audit_service.dart';

class CoinflipService {
  CoinflipService._();
  static final CoinflipService instance = CoinflipService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<void> cleanupStaleRooms() async {
    try {
      await _client.from('coinflip_rooms').delete().eq('status', 'waiting')
          .lt('created_at', DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> createRoom({int betAmount = 100}) async {
    try {
      final r = await _client.rpc('cf_create_room', params: {'p_bet_amount': betAmount});
      if (r is Map) {
        final map = Map<String, dynamic>.from(r);
        final roomId = map['room_id']?.toString();
        if (roomId != null) {
          unawaited(GameAuditService.instance.logGameStart(
            gameId: roomId, gameType: 'coinflip',
            payload: {'bet': betAmount, 'action': 'create_room'},
          ));
          unawaited(GameAuditService.instance.logBetPlaced(
            gameId: roomId, gameType: 'coinflip', amount: betAmount,
          ));
        }
        return map;
      }
      return null;
    } catch (e) { debugPrint('[CF] createRoom: $e'); rethrow; }
  }

  Future<String?> joinRoom(String code) async {
    try {
      final r = await _client.rpc('cf_join_room', params: {'p_code': code.toUpperCase()});
      String? roomId;
      if (r is Map) {
        roomId = r['room_id']?.toString();
      } else {
        roomId = r?.toString();
      }
      if (roomId != null) {
        unawaited(GameAuditService.instance.logEvent(
          gameId: roomId, gameType: 'coinflip',
          eventType: 'player_joined',
          payload: {'code': code.toUpperCase()},
        ));
      }
      return roomId;
    } catch (e) { debugPrint('[CF] joinRoom: $e'); rethrow; }
  }

  Future<void> chooseSide(String gameId, String choice) async {
    try {
      await _client.rpc('cf_choose_side', params: {'p_game_id': gameId, 'p_choice': choice});
      unawaited(GameAuditService.instance.logMove(
        gameId: gameId, gameType: 'coinflip',
        moveData: {'choice': choice},
      ));
    } catch (e) { debugPrint('[CF] chooseSide: $e'); rethrow; }
  }

  Future<String> autoContinue(String gameId) async {
    try {
      final r = await _client.rpc('cf_auto_continue', params: {'p_game_id': gameId});
      return r?.toString() ?? 'ended';
    } catch (e) { debugPrint('[CF] autoContinue: $e'); return 'ended'; }
  }

  Future<CFGame?> getGame(String gameId) async {
    try {
      final d = await _client.from('coinflip_games').select().eq('id', gameId).maybeSingle();
      return d != null ? CFGame.fromJson(d) : null;
    } catch (e) { debugPrint('[CF] getGame: $e'); return null; }
  }

  Future<CFRoom?> getRoom(String roomId) async {
    try {
      final d = await _client.from('coinflip_rooms').select().eq('id', roomId).maybeSingle();
      return d != null ? CFRoom.fromJson(d) : null;
    } catch (_) { return null; }
  }

  /// Recupere une room par son code (pour pre-check du solde avant join)
  Future<CFRoom?> getRoomByCode(String code) async {
    try {
      final d = await _client.from('coinflip_rooms')
          .select().eq('code', code.toUpperCase())
          .eq('status', 'waiting').maybeSingle();
      return d != null ? CFRoom.fromJson(d) : null;
    } catch (_) { return null; }
  }

  Future<List<Map<String, dynamic>>> getPlayers(String roomId) async {
    try {
      return List<Map<String, dynamic>>.from(
        await _client.from('coinflip_room_players').select().eq('room_id', roomId));
    } catch (_) { return []; }
  }

  RealtimeChannel subscribeRoom(String roomId, void Function(CFRoom) onUpdate) {
    return _client.channel('cf-room-$roomId').onPostgresChanges(
      event: PostgresChangeEvent.update, schema: 'public', table: 'coinflip_rooms',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: roomId),
      callback: (p) { try { onUpdate(CFRoom.fromJson(p.newRecord)); } catch (_) {} },
    ).subscribe();
  }

  RealtimeChannel subscribeGame(String gameId, void Function(CFGame) onUpdate) {
    return _client.channel('cf-game-$gameId').onPostgresChanges(
      event: PostgresChangeEvent.update, schema: 'public', table: 'coinflip_games',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
      callback: (p) { try { onUpdate(CFGame.fromJson(p.newRecord)); } catch (_) {} },
    ).subscribe();
  }

  RealtimeChannel subscribePlayers(String roomId, void Function() onChange) {
    return _client.channel('cf-players-$roomId').onPostgresChanges(
      event: PostgresChangeEvent.all, schema: 'public', table: 'coinflip_room_players',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: roomId),
      callback: (_) => onChange(),
    ).subscribe();
  }

  void unsubscribe(RealtimeChannel c) => _client.removeChannel(c);
}

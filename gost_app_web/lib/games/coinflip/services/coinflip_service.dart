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

  /// Passe par la RPC serveur qui refund les rooms zombies au lieu de
  /// DELETE direct (l'ancien code supprimait sans rembourser !).
  Future<void> cleanupStaleRooms() async {
    try {
      await _client.rpc('coinflip_cleanup_stale_rooms');
    } catch (_) {}
  }

  /// Annule une room en `waiting` et refund le host.
  /// Idempotent cote serveur. Retourne true sur succes ou idempotent.
  Future<bool> cancelWaitingRoom(String roomId) async {
    try {
      final r = await _client.rpc('cf_cancel_waiting_room', params: {
        'p_room_id': roomId,
      });
      return r is Map && r['success'] == true;
    } catch (e) {
      debugPrint('[CF] cancelWaitingRoom error: $e');
      return false;
    }
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

  /// [requestId] : id stable genere par l'appelant, reutilise sur chaque
  /// retry pour l'idempotence (wrapper cf_choose_side_idem).
  Future<void> chooseSide(String gameId, String choice, {String? requestId}) async {
    final reqId = requestId
        ?? '${currentUserId ?? "anon"}_${gameId}_cf_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _client.rpc('cf_choose_side_idem', params: {
        'p_game_id': gameId,
        'p_choice': choice,
        'p_request_id': reqId,
      });
      unawaited(GameAuditService.instance.logMove(
        gameId: gameId, gameType: 'coinflip',
        moveData: {'choice': choice, 'request_id': reqId},
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

  /// [onConnectionLost] : callback declenche si le channel ferme/error.
  /// Le caller peut alors demarrer un polling fallback.
  RealtimeChannel subscribeRoom(
    String roomId,
    void Function(CFRoom) onUpdate, {
    void Function()? onConnectionLost,
  }) {
    return _client.channel('cf-room-$roomId').onPostgresChanges(
      event: PostgresChangeEvent.update, schema: 'public', table: 'coinflip_rooms',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: roomId),
      callback: (p) { try { onUpdate(CFRoom.fromJson(p.newRecord)); } catch (_) {} },
    ).subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError
          || status == RealtimeSubscribeStatus.closed
          || status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[CF] room channel issue: $status ${error ?? ""}');
        onConnectionLost?.call();
      }
    });
  }

  RealtimeChannel subscribeGame(
    String gameId,
    void Function(CFGame) onUpdate, {
    void Function()? onConnectionLost,
  }) {
    return _client.channel('cf-game-$gameId').onPostgresChanges(
      event: PostgresChangeEvent.update, schema: 'public', table: 'coinflip_games',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
      callback: (p) { try { onUpdate(CFGame.fromJson(p.newRecord)); } catch (_) {} },
    ).subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError
          || status == RealtimeSubscribeStatus.closed
          || status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[CF] game channel issue: $status ${error ?? ""}');
        onConnectionLost?.call();
      }
    });
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

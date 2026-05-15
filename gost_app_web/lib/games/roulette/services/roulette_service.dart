// ============================================================
// ROULETTE — Service Supabase
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/roulette_models.dart';
import '../../../services/game_audit_service.dart';

class RouletteService {
  RouletteService._();
  static final RouletteService instance = RouletteService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get currentUserId => _client.auth.currentUser?.id;

  Future<void> cleanupStaleRooms() async {
    try {
      await _client.from('roulette_rooms').delete().eq('status', 'waiting')
          .lt('created_at', DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> createRoom({int maxPlayers = 6, int minBet = 50}) async {
    try {
      final result = await _client.rpc('rlt_create_room', params: {
        'p_max_players': maxPlayers, 'p_min_bet': minBet,
      });
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) { debugPrint('[RLT] createRoom: $e'); rethrow; }
  }

  Future<String?> joinRoom(String code) async {
    try {
      final result = await _client.rpc('rlt_join_room', params: {'p_code': code.toUpperCase()});
      if (result is Map) return result['room_id']?.toString();
      return result?.toString();
    } catch (e) { debugPrint('[RLT] joinRoom: $e'); rethrow; }
  }

  /// Pre-check : recupere une room par son code pour valider le solde avant join.
  Future<RouletteRoom?> getRoomByCode(String code) async {
    try {
      final d = await _client.from('roulette_rooms')
          .select().eq('code', code.toUpperCase())
          .eq('status', 'waiting').maybeSingle();
      return d != null ? RouletteRoom.fromJson(d) : null;
    } catch (_) { return null; }
  }

  Future<String?> startGame(String roomId) async {
    try {
      final result = await _client.rpc('rlt_start_game', params: {'p_room_id': roomId});
      final gameId = result?.toString();
      if (gameId != null) {
        unawaited(GameAuditService.instance.logGameStart(
          gameId: gameId, gameType: 'roulette',
          payload: {'room_id': roomId},
        ));
      }
      return gameId;
    } catch (e) { debugPrint('[RLT] startGame: $e'); return null; }
  }

  Future<void> placeBet(String gameId, String type, int amount, {int? number}) async {
    try {
      await _client.rpc('rlt_place_bet', params: {
        'p_game_id': gameId, 'p_type': type, 'p_amount': amount, 'p_number': number,
      });
      unawaited(GameAuditService.instance.logBetPlaced(
        gameId: gameId, gameType: 'roulette', amount: amount,
        extra: {'type': type, if (number != null) 'number': number},
      ));
    } catch (e) { debugPrint('[RLT] placeBet: $e'); rethrow; }
  }

  Future<void> spin(String gameId) async {
    try {
      await _client.rpc('rlt_spin', params: {'p_game_id': gameId});
      unawaited(GameAuditService.instance.logEvent(
        gameId: gameId, gameType: 'roulette', eventType: 'spin',
      ));
    } catch (e) { debugPrint('[RLT] spin: $e'); rethrow; }
  }

  Future<String> autoContinue(String gameId) async {
    try {
      final r = await _client.rpc('rlt_auto_continue', params: {'p_game_id': gameId});
      return r?.toString() ?? 'ended';
    } catch (e) { debugPrint('[RLT] autoContinue: $e'); return 'ended'; }
  }

  Future<void> markReady(String roomId, bool ready) async {
    // S18 : passe par RPC (RLS bloque les UPDATE directs)
    try {
      await _client.rpc('rlt_set_ready', params: {
        'p_room_id': roomId,
        'p_is_ready': ready,
      });
    } catch (e) { debugPrint('[RLT] markReady: $e'); }
  }

  Future<RouletteRoom?> getRoom(String roomId) async {
    try {
      final d = await _client.from('roulette_rooms').select().eq('id', roomId).maybeSingle();
      return d != null ? RouletteRoom.fromJson(d) : null;
    } catch (_) { return null; }
  }

  Future<List<Map<String, dynamic>>> getPlayers(String roomId) async {
    try {
      return List<Map<String, dynamic>>.from(
        await _client.from('roulette_room_players').select().eq('room_id', roomId));
    } catch (_) { return []; }
  }

  Future<RouletteGame?> getGame(String gameId) async {
    try {
      final d = await _client.from('roulette_games').select().eq('id', gameId).maybeSingle();
      return d != null ? RouletteGame.fromJson(d) : null;
    } catch (e) { debugPrint('[RLT] getGame: $e'); return null; }
  }

  RealtimeChannel subscribeRoom(
    String roomId,
    void Function(RouletteRoom) onUpdate, {
    void Function()? onConnectionLost,
  }) {
    return _client.channel('rlt-room-$roomId').onPostgresChanges(
      event: PostgresChangeEvent.update, schema: 'public', table: 'roulette_rooms',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: roomId),
      callback: (p) { try { onUpdate(RouletteRoom.fromJson(p.newRecord)); } catch (_) {} },
    ).subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError
          || status == RealtimeSubscribeStatus.closed
          || status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[RLT] room channel issue: $status ${error ?? ""}');
        onConnectionLost?.call();
      }
    });
  }

  RealtimeChannel subscribeGame(
    String gameId,
    void Function(RouletteGame) onUpdate, {
    void Function()? onConnectionLost,
  }) {
    return _client.channel('rlt-game-$gameId').onPostgresChanges(
      event: PostgresChangeEvent.update, schema: 'public', table: 'roulette_games',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
      callback: (p) { try { onUpdate(RouletteGame.fromJson(p.newRecord)); } catch (_) {} },
    ).subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.channelError
          || status == RealtimeSubscribeStatus.closed
          || status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('[RLT] game channel issue: $status ${error ?? ""}');
        onConnectionLost?.call();
      }
    });
  }

  RealtimeChannel subscribePlayers(String roomId, void Function() onChange) {
    return _client.channel('rlt-players-$roomId').onPostgresChanges(
      event: PostgresChangeEvent.all, schema: 'public', table: 'roulette_room_players',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: roomId),
      callback: (_) => onChange(),
    ).subscribe();
  }

  void unsubscribe(RealtimeChannel c) => _client.removeChannel(c);
}

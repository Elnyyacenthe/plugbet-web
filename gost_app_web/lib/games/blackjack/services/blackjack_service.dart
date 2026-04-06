// ============================================================
// BLACKJACK — Service Supabase (RPC + Realtime)
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/blackjack_models.dart';

class BlackjackService {
  BlackjackService._();
  static final BlackjackService instance = BlackjackService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get currentUserId => _client.auth.currentUser?.id;

  // ── Cleanup ────────────────────────────────────────────
  Future<void> cleanupStaleRooms() async {
    try {
      await _client.from('blackjack_rooms').delete().eq('status', 'waiting')
          .lt('created_at', DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());
    } catch (_) {}
  }

  // ── Rooms ──────────────────────────────────────────────
  Future<Map<String, dynamic>?> createRoom({
    int playerCount = 2,
    int betAmount = 100,
  }) async {
    try {
      final result = await _client.rpc('bj_create_room', params: {
        'p_player_count': playerCount,
        'p_bet_amount': betAmount,
      });
      debugPrint('[BJ] createRoom: $result');
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('[BJ] Erreur createRoom: $e');
      rethrow;
    }
  }

  Future<String?> joinRoom(String code) async {
    try {
      final result = await _client.rpc('bj_join_room', params: {
        'p_code': code.toUpperCase(),
      });
      debugPrint('[BJ] joinRoom: $result');
      if (result is Map) return result['room_id']?.toString();
      return result?.toString();
    } catch (e) {
      debugPrint('[BJ] Erreur joinRoom: $e');
      rethrow;
    }
  }

  Future<String?> startGame(String roomId) async {
    try {
      final result = await _client.rpc('bj_start_game', params: {
        'p_room_id': roomId,
      });
      debugPrint('[BJ] startGame: $result');
      return result?.toString();
    } catch (e) {
      debugPrint('[BJ] Erreur startGame: $e');
      return null;
    }
  }

  Future<void> markReady(String roomId, bool isReady) async {
    try {
      final uid = currentUserId;
      if (uid == null) return;
      await _client.from('blackjack_room_players').update({
        'is_ready': isReady,
      }).eq('room_id', roomId).eq('user_id', uid);
    } catch (e) {
      debugPrint('[BJ] Erreur markReady: $e');
    }
  }

  // ── Game actions ───────────────────────────────────────
  Future<BJGame?> getGame(String gameId) async {
    try {
      final data = await _client.from('blackjack_games')
          .select().eq('id', gameId).maybeSingle();
      if (data == null) return null;
      return BJGame.fromJson(data);
    } catch (e) {
      debugPrint('[BJ] Erreur getGame: $e');
      return null;
    }
  }

  Future<void> hit(String gameId) async {
    try {
      await _client.rpc('bj_hit', params: {'p_game_id': gameId});
      debugPrint('[BJ] hit OK');
    } catch (e) {
      debugPrint('[BJ] Erreur hit: $e');
      rethrow;
    }
  }

  Future<void> stand(String gameId) async {
    try {
      await _client.rpc('bj_stand', params: {'p_game_id': gameId});
      debugPrint('[BJ] stand OK');
    } catch (e) {
      debugPrint('[BJ] Erreur stand: $e');
      rethrow;
    }
  }

  Future<String> autoContinue(String gameId) async {
    try {
      final result = await _client.rpc('bj_auto_continue', params: {
        'p_game_id': gameId,
      });
      return result?.toString() ?? 'ended';
    } catch (e) {
      debugPrint('[BJ] Erreur autoContinue: $e');
      return 'ended';
    }
  }

  // ── Room info ──────────────────────────────────────────
  Future<BJRoom?> getRoom(String roomId) async {
    try {
      final data = await _client.from('blackjack_rooms')
          .select().eq('id', roomId).maybeSingle();
      if (data == null) return null;
      return BJRoom.fromJson(data);
    } catch (e) {
      debugPrint('[BJ] Erreur getRoom: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getPlayers(String roomId) async {
    try {
      final data = await _client.from('blackjack_room_players')
          .select().eq('room_id', roomId);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('[BJ] Erreur getPlayers: $e');
      return [];
    }
  }

  // ── Realtime ───────────────────────────────────────────
  RealtimeChannel subscribeRoom(String roomId, void Function(BJRoom) onUpdate) {
    return _client.channel('bj-room-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'blackjack_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'id', value: roomId,
          ),
          callback: (payload) {
            try {
              onUpdate(BJRoom.fromJson(payload.newRecord));
            } catch (e) {
              debugPrint('[BJ-RT] room parse error: $e');
            }
          },
        )
        .subscribe();
  }

  RealtimeChannel subscribeGame(String gameId, void Function(BJGame) onUpdate) {
    return _client.channel('bj-game-$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'blackjack_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'id', value: gameId,
          ),
          callback: (payload) {
            try {
              onUpdate(BJGame.fromJson(payload.newRecord));
            } catch (e) {
              debugPrint('[BJ-RT] game parse error: $e');
            }
          },
        )
        .subscribe();
  }

  RealtimeChannel subscribePlayers(String roomId, void Function() onChange) {
    return _client.channel('bj-players-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blackjack_room_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'room_id', value: roomId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}

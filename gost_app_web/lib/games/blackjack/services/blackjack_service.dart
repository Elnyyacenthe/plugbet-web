// ============================================================
// BLACKJACK — Service Supabase (RPC + Realtime)
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/blackjack_models.dart';
import '../../../services/game_audit_service.dart';

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

  /// Annule une room en `waiting` sans autres joueurs et refund le host.
  /// Idempotent cote serveur. Retourne true si refund effectue ou idempotent.
  Future<bool> cancelWaitingRoom(String roomId) async {
    try {
      final r = await _client.rpc('bj_cancel_waiting_room', params: {
        'p_room_id': roomId,
      });
      return r is Map && r['success'] == true;
    } catch (e) {
      debugPrint('[BJ] cancelWaitingRoom error: $e');
      return false;
    }
  }

  /// Pre-check : recupere une room par son code pour valider le solde avant join.
  Future<BJRoom?> getRoomByCode(String code) async {
    try {
      final d = await _client.from('blackjack_rooms')
          .select().eq('code', code.toUpperCase())
          .eq('status', 'waiting').maybeSingle();
      return d != null ? BJRoom.fromJson(d) : null;
    } catch (_) { return null; }
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
      final gameId = result?.toString();
      if (gameId != null) {
        unawaited(GameAuditService.instance.logGameStart(
          gameId: gameId, gameType: 'blackjack',
          payload: {'room_id': roomId},
        ));
      }
      return gameId;
    } catch (e) {
      debugPrint('[BJ] Erreur startGame: $e');
      return null;
    }
  }

  Future<void> markReady(String roomId, bool isReady) async {
    // S18 : passe par RPC (RLS bloque les UPDATE directs)
    try {
      final uid = currentUserId;
      if (uid == null) return;
      await _client.rpc('bj_set_ready', params: {
        'p_room_id': roomId,
        'p_is_ready': isReady,
      });
    } catch (e) {
      debugPrint('[BJ] Erreur markReady: $e');
    }
  }

  /// Reprise de session : retourne la partie/room Blackjack active
  /// de l'user, ou null. Tolere toute erreur silencieusement.
  Future<Map<String, dynamic>?> getActiveSession() async {
    try {
      final r = await _client.rpc('bj_get_active');
      return r is Map ? Map<String, dynamic>.from(r) : null;
    } catch (e) {
      debugPrint('[BJ] getActiveSession: $e');
      return null;
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

  Future<void> hit(String gameId, {String? requestId}) async {
    final reqId = requestId
        ?? '${currentUserId ?? "anon"}_${gameId}_hit_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _client.rpc('bj_hit_idem', params: {
        'p_game_id': gameId, 'p_request_id': reqId,
      });
      debugPrint('[BJ] hit OK');
      unawaited(GameAuditService.instance.logMove(
        gameId: gameId, gameType: 'blackjack',
        moveData: {'action': 'hit', 'request_id': reqId},
      ));
    } catch (e) {
      debugPrint('[BJ] Erreur hit: $e');
      rethrow;
    }
  }

  Future<void> stand(String gameId, {String? requestId}) async {
    final reqId = requestId
        ?? '${currentUserId ?? "anon"}_${gameId}_stand_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _client.rpc('bj_stand_idem', params: {
        'p_game_id': gameId, 'p_request_id': reqId,
      });
      debugPrint('[BJ] stand OK');
      unawaited(GameAuditService.instance.logMove(
        gameId: gameId, gameType: 'blackjack',
        moveData: {'action': 'stand', 'request_id': reqId},
      ));
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
  RealtimeChannel subscribeRoom(
    String roomId,
    void Function(BJRoom) onUpdate, {
    void Function()? onConnectionLost,
  }) {
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
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError
              || status == RealtimeSubscribeStatus.closed
              || status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('[BJ] room channel issue: $status ${error ?? ""}');
            onConnectionLost?.call();
          }
        });
  }

  RealtimeChannel subscribeGame(
    String gameId,
    void Function(BJGame) onUpdate, {
    void Function()? onConnectionLost,
  }) {
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
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError
              || status == RealtimeSubscribeStatus.closed
              || status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('[BJ] game channel issue: $status ${error ?? ""}');
            onConnectionLost?.call();
          }
        });
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

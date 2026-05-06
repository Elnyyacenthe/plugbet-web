// ============================================================
// LUDO V2 — Supabase Service (RPC + Realtime) - PRODUCTION
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/ludo_models.dart';

class LudoV2Service {
  static final LudoV2Service instance = LudoV2Service._();
  LudoV2Service._();

  final _uuid = const Uuid();
  SupabaseClient get _client => Supabase.instance.client;
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Genere un request_id unique pour idempotence
  String _newRequestId() => _uuid.v4();

  // ── CLEANUP ─────────────────────────────────────────────

  /// Cleanup serveur (idempotent, peut etre appele au demarrage de l'app).
  /// Necessite une RPC dediee si appelle non-admin sinon les rooms d'autres
  /// utilisateurs ne sont pas affectees.
  Future<void> cleanupStaleRooms() async {
    try {
      await _client.rpc('ludo_v2_cleanup_stale');
    } catch (e) {
      debugPrint('[LUDO-V2] cleanup error: $e');
    }
  }

  // ── ROOMS ──────────────────────────────────────────────

  Future<Map<String, dynamic>> createRoom({
    int playerCount = 2,
    int bet = 0,
    bool isPrivate = false,
  }) async {
    final result = await _client.rpc('ludo_v2_create_room', params: {
      'p_player_count': playerCount,
      'p_bet': bet,
      'p_private': isPrivate,
    });
    debugPrint('[LUDO-V2] createRoom: $result');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<LudoV2Room?> getRoomByCode(String code) async {
    try {
      final d = await _client.from('ludo_v2_rooms')
          .select().eq('code', code.toUpperCase())
          .eq('status', 'waiting').maybeSingle();
      return d != null ? LudoV2Room.fromJson(d) : null;
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>> joinRoom(String code) async {
    final result = await _client.rpc('ludo_v2_join_room', params: {
      'p_code': code.toUpperCase(),
    });
    debugPrint('[LUDO-V2] joinRoom: $result');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<LudoV2Room>> getPublicRooms() async {
    final data = await _client
        .from('ludo_v2_rooms')
        .select('*, ludo_v2_room_players(*)')
        .eq('status', 'waiting')
        .eq('is_private', false)
        .order('created_at', ascending: false)
        .limit(20);
    return (data as List).map((j) => LudoV2Room.fromJson(j)).toList();
  }

  Future<LudoV2Room?> getRoom(String roomId) async {
    final data = await _client
        .from('ludo_v2_rooms')
        .select('*, ludo_v2_room_players(*)')
        .eq('id', roomId)
        .maybeSingle();
    if (data == null) return null;
    return LudoV2Room.fromJson(data);
  }

  Future<void> deleteRoom(String roomId) async {
    await _client.from('ludo_v2_rooms').delete().eq('id', roomId);
  }

  // ── GAME ───────────────────────────────────────────────

  Future<LudoV2Game?> getGame(String gameId) async {
    final data = await _client
        .from('ludo_v2_games')
        .select()
        .eq('id', gameId)
        .maybeSingle();
    if (data == null) return null;
    return LudoV2Game.fromJson(data);
  }

  /// Lance le dé. request_id pour idempotence sur retry.
  Future<int> rollDice(String gameId, {String? requestId}) async {
    final result = await _client.rpc('ludo_v2_roll_dice', params: {
      'p_game_id': gameId,
      'p_request_id': requestId ?? _newRequestId(),
    });
    debugPrint('[LUDO-V2] rollDice: $result');
    return (result as num).toInt();
  }

  /// Joue un mouvement (idempotent via request_id).
  Future<LudoV2MoveResult> playMove(String gameId, int pawnIndex, {String? requestId}) async {
    final result = await _client.rpc('ludo_v2_play_move', params: {
      'p_game_id': gameId,
      'p_pawn_index': pawnIndex,
      'p_request_id': requestId ?? _newRequestId(),
    });
    debugPrint('[LUDO-V2] playMove: $result');
    return LudoV2MoveResult.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<void> skipTurn(String gameId, {String? requestId}) async {
    await _client.rpc('ludo_v2_skip_turn', params: {
      'p_game_id': gameId,
      'p_request_id': requestId ?? _newRequestId(),
    });
  }

  Future<void> forfeit(String gameId, {String? requestId}) async {
    await _client.rpc('ludo_v2_forfeit', params: {
      'p_game_id': gameId,
      'p_request_id': requestId ?? _newRequestId(),
    });
  }

  /// Compte un timeout cote serveur. Retourne {forfeited, timeouts, max}.
  Future<Map<String, dynamic>> registerTimeout(String gameId) async {
    final r = await _client.rpc('ludo_v2_register_timeout', params: {
      'p_game_id': gameId,
    });
    return Map<String, dynamic>.from(r as Map);
  }

  /// Reclame une victoire si l'adversaire est idle > 90s.
  Future<Map<String, dynamic>> claimIdleWin(String gameId) async {
    final r = await _client.rpc('ludo_v2_claim_idle_win', params: {
      'p_game_id': gameId,
    });
    return Map<String, dynamic>.from(r as Map);
  }

  // ── REALTIME ───────────────────────────────────────────

  RealtimeChannel subscribeGame(
    String gameId,
    void Function(LudoV2Game game) onUpdate,
  ) {
    return _client
        .channel('ludo-v2-game-$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ludo_v2_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            try {
              final game = LudoV2Game.fromJson(payload.newRecord);
              debugPrint('[LUDO-V2-RT] Update: turn=${game.currentTurn} dice=${game.diceValue} status=${game.status}');
              onUpdate(game);
            } catch (e) {
              debugPrint('[LUDO-V2-RT] Parse error: $e');
            }
          },
        )
        .subscribe();
  }

  RealtimeChannel subscribeRoom(
    String roomId,
    void Function(LudoV2Room room) onUpdate,
  ) {
    return _client
        .channel('ludo-v2-room-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ludo_v2_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (_) async {
            try {
              final room = await getRoom(roomId);
              if (room != null) onUpdate(room);
            } catch (e) {
              debugPrint('[LUDO-V2-RT] Room parse error: $e');
            }
          },
        )
        .subscribe();
  }

  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}

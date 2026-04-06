// ============================================================
// LUDO V2 — Supabase Service (RPC + Realtime)
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ludo_models.dart';

class LudoV2Service {
  static final LudoV2Service instance = LudoV2Service._();
  LudoV2Service._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get currentUserId => _client.auth.currentUser?.id;

  // ── CLEANUP ─────────────────────────────────────────────

  /// Supprime les salles en attente depuis plus d'1 heure
  Future<void> cleanupStaleRooms() async {
    try {
      await _client.from('ludo_v2_rooms')
          .delete()
          .eq('status', 'waiting')
          .lt('created_at', DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());
    } catch (e) {
      debugPrint('[LUDO-V2] cleanup error: $e');
    }
  }

  // ── ROOMS ──────────────────────────────────────────────

  /// Crée une room et retourne {room_id, code}
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

  /// Rejoint une room, retourne {room_id, game_id, started}
  Future<Map<String, dynamic>> joinRoom(String code) async {
    final result = await _client.rpc('ludo_v2_join_room', params: {
      'p_code': code.toUpperCase(),
    });
    debugPrint('[LUDO-V2] joinRoom: $result');
    return Map<String, dynamic>.from(result as Map);
  }

  /// Liste les rooms publiques en attente
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

  /// Détail d'une room avec ses joueurs
  Future<LudoV2Room?> getRoom(String roomId) async {
    final data = await _client
        .from('ludo_v2_rooms')
        .select('*, ludo_v2_room_players(*)')
        .eq('id', roomId)
        .maybeSingle();
    if (data == null) return null;
    return LudoV2Room.fromJson(data);
  }

  /// Supprime une room (host only)
  Future<void> deleteRoom(String roomId) async {
    await _client.from('ludo_v2_rooms').delete().eq('id', roomId);
  }

  // ── GAME ───────────────────────────────────────────────

  /// Charge une partie
  Future<LudoV2Game?> getGame(String gameId) async {
    final data = await _client
        .from('ludo_v2_games')
        .select()
        .eq('id', gameId)
        .maybeSingle();
    if (data == null) return null;
    return LudoV2Game.fromJson(data);
  }

  /// Lance le dé (côté serveur uniquement)
  Future<int> rollDice(String gameId) async {
    final result = await _client.rpc('ludo_v2_roll_dice', params: {
      'p_game_id': gameId,
    });
    debugPrint('[LUDO-V2] rollDice: $result');
    return (result as num).toInt();
  }

  /// Joue un mouvement
  Future<LudoV2MoveResult> playMove(String gameId, int pawnIndex) async {
    final result = await _client.rpc('ludo_v2_play_move', params: {
      'p_game_id': gameId,
      'p_pawn_index': pawnIndex,
    });
    debugPrint('[LUDO-V2] playMove: $result');
    return LudoV2MoveResult.fromJson(Map<String, dynamic>.from(result as Map));
  }

  /// Passe le tour (aucun coup possible)
  Future<void> skipTurn(String gameId) async {
    await _client.rpc('ludo_v2_skip_turn', params: {
      'p_game_id': gameId,
    });
    debugPrint('[LUDO-V2] skipTurn');
  }

  Future<void> forfeit(String gameId) async {
    await _client.rpc('ludo_v2_forfeit', params: {
      'p_game_id': gameId,
    });
    debugPrint('[LUDO-V2] forfeit');
  }

  // ── REALTIME ───────────────────────────────────────────

  /// S'abonne aux changements d'une partie
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
              debugPrint('[LUDO-V2-RT] Game update: turn=${game.currentTurn}, dice=${game.diceValue}, status=${game.status}');
              onUpdate(game);
            } catch (e) {
              debugPrint('[LUDO-V2-RT] Parse error: $e');
            }
          },
        )
        .subscribe();
  }

  /// S'abonne aux changements d'une room (joueurs qui rejoignent)
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
          callback: (payload) async {
            try {
              // Refetch full room with players
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

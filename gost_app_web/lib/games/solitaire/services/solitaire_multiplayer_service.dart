// ============================================================
// Solitaire – Service multijoueur (Supabase)
// Table : solitaire_rooms
// ============================================================
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/wallet_service.dart';
import '../models/solitaire_models.dart';
import '../models/solitaire_room_models.dart';

class SolitaireMultiplayerService {
  final SupabaseClient _client = Supabase.instance.client;
  final WalletService _wallet = WalletService();

  RealtimeChannel? _channel;

  String? get currentUserId => _client.auth.currentUser?.id;

  // ============================================================
  // PROFIL / COINS (caisse générale)
  // ============================================================

  Future<int> getCoins() => _wallet.getCoins();

  Future<String> _getUsername() => _wallet.getUsername();

  // ============================================================
  // CRÉER UNE SALLE
  // ============================================================

  Future<SolitaireRoom?> createRoom({
    required int betAmount,
    required int maxPlayers,
    required bool isPrivate,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;

    final ok = await _wallet.deductCoins(betAmount);
    if (!ok) return null;

    final username = await _getUsername();
    final code = isPrivate ? _generateCode() : null;

    // État initial du jeu avec les joueurs
    final initialState = SolitaireState.initial();
    final gameState = {
      ...initialState.toJson(),
      'players': [
        SolitaireRoomPlayer(id: uid, username: username).toJson(),
      ],
      'currentTurnIndex': 0,
    };

    try {
      final row = await _client.from('solitaire_rooms').insert({
        'host_id': uid,
        'host_username': username,
        'max_players': maxPlayers,
        'current_players': 1,
        'bet_amount': betAmount,
        'pot': betAmount,
        'is_private': isPrivate,
        'private_code': code,
        'status': 'waiting',
        'game_state': gameState,
      }).select().single();

      return SolitaireRoom.fromJson(row);
    } catch (e) {
      debugPrint('[SOL-MULTI] createRoom: $e');
      // Rembourser si échec
      await _wallet.addCoins(betAmount);
      return null;
    }
  }

  // ============================================================
  // REJOINDRE UNE SALLE
  // ============================================================

  Future<SolitaireRoom?> joinRoom(String roomId) async {
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      final row = await _client
          .from('solitaire_rooms')
          .select()
          .eq('id', roomId)
          .eq('status', 'waiting')
          .single();
      final room = SolitaireRoom.fromJson(row);

      if (room.currentPlayers >= room.maxPlayers) return null;

      final ok = await _wallet.deductCoins(room.betAmount);
      if (!ok) return null;

      final username = await _getUsername();
      final newPlayers = [
        ...room.players.map((p) => p.toJson()),
        SolitaireRoomPlayer(id: uid, username: username).toJson(),
      ];
      final newCount = room.currentPlayers + 1;
      final newPot = room.pot + room.betAmount;
      final isNowFull = newCount >= room.maxPlayers;

      Map<String, dynamic> gameState;
      if (isNowFull) {
        // Initialiser un plateau frais quand la salle est pleine
        final freshState = SolitaireState.initial();
        gameState = {
          ...freshState.toJson(),
          'players': newPlayers,
          'currentTurnIndex': 0,
        };
      } else {
        gameState = {
          ...(room.gameStateJson ?? {}),
          'players': newPlayers,
          'currentTurnIndex': 0,
        };
      }

      final updated = await _client
          .from('solitaire_rooms')
          .update({
            'current_players': newCount,
            'pot': newPot,
            'status': isNowFull ? 'playing' : 'waiting',
            'game_state': gameState,
          })
          .eq('id', roomId)
          .select()
          .single();

      return SolitaireRoom.fromJson(updated);
    } catch (e) {
      debugPrint('[SOL-MULTI] joinRoom: $e');
      return null;
    }
  }

  Future<SolitaireRoom?> joinByCode(String code) async {
    try {
      final row = await _client
          .from('solitaire_rooms')
          .select()
          .eq('private_code', code.toUpperCase().trim())
          .eq('status', 'waiting')
          .maybeSingle();
      if (row == null) return null;
      return joinRoom(row['id'] as String);
    } catch (e) {
      debugPrint('[SOL-MULTI] joinByCode: $e');
      return null;
    }
  }

  // ============================================================
  // SALLES PUBLIQUES
  // ============================================================

  Future<List<SolitaireRoom>> getPublicRooms() async {
    try {
      final rows = await _client
          .from('solitaire_rooms')
          .select()
          .eq('status', 'waiting')
          .eq('is_private', false)
          .order('created_at', ascending: false)
          .limit(20);
      return (rows as List)
          .map((r) => SolitaireRoom.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SOL-MULTI] getPublicRooms: $e');
      return [];
    }
  }

  // ============================================================
  // SYNCHRONISER L'ÉTAT DU JEU
  // ============================================================

  Future<void> pushGameState(
    String roomId,
    SolitaireState state,
    List<SolitaireRoomPlayer> players,
    int currentTurnIndex,
  ) async {
    final gameState = {
      ...state.toJson(),
      'players': players.map((p) => p.toJson()).toList(),
      'currentTurnIndex': currentTurnIndex,
    };
    try {
      await _client
          .from('solitaire_rooms')
          .update({'game_state': gameState})
          .eq('id', roomId);
    } catch (e) {
      debugPrint('[SOL-MULTI] pushGameState: $e');
    }
  }

  // ============================================================
  // FIN DE PARTIE ET GAINS
  // ============================================================

  Future<void> distributeWinnings(
    String roomId,
    List<SolitaireRoomPlayer> players,
  ) async {
    if (players.isEmpty) return;
    try {
      // Trouver le(s) gagnant(s) – le plus haut score
      final maxScore = players.map((p) => p.score).reduce(max);
      final winners = players.where((p) => p.score == maxScore).toList();

      final row = await _client
          .from('solitaire_rooms')
          .select('pot')
          .eq('id', roomId)
          .single();
      final pot = row['pot'] as int? ?? 0;

      if (pot > 0 && winners.isNotEmpty) {
        final share = pot ~/ winners.length;
        for (final w in winners) {
          await _wallet.addCoinsToUser(w.id, share);
        }
      }

      await _client.from('solitaire_rooms').update({
        'status': 'finished',
        'winner_id': winners.length == 1 ? winners.first.id : null,
      }).eq('id', roomId);
    } catch (e) {
      debugPrint('[SOL-MULTI] distributeWinnings: $e');
    }
  }

  // ============================================================
  // ANNULER (HOST QUITTE EN LOBBY)
  // ============================================================

  Future<void> cancelRoom(String roomId) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      final row = await _client
          .from('solitaire_rooms')
          .select('bet_amount, pot, status, host_id, game_state')
          .eq('id', roomId)
          .single();

      // Rembourser tous les joueurs si waiting
      if (row['status'] == 'waiting') {
        final gameState = row['game_state'] as Map<String, dynamic>?;
        final playersJson = (gameState?['players'] as List?) ?? [];
        final betAmount = row['bet_amount'] as int? ?? 0;
        for (final p in playersJson) {
          final playerId = (p as Map<String, dynamic>)['id'] as String?;
          if (playerId != null) {
            await _wallet.addCoinsToUser(playerId, betAmount);
          }
        }
      }

      await _client.from('solitaire_rooms').delete().eq('id', roomId);
    } catch (e) {
      debugPrint('[SOL-MULTI] cancelRoom: $e');
    }
  }

  // ============================================================
  // REALTIME
  // ============================================================

  void subscribeToRoom(String roomId, void Function(SolitaireRoom) onUpdate) {
    _channel = _client
        .channel('sol-room-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'solitaire_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final room = SolitaireRoom.fromJson(
                  payload.newRecord.cast<String, dynamic>());
              onUpdate(room);
            } catch (e) {
              debugPrint('[SOL-MULTI] realtime parse: $e');
            }
          },
        )
        .subscribe();
  }

  void unsubscribe() {
    if (_channel != null) {
      _client.removeChannel(_channel!);
      _channel = null;
    }
  }

  // ============================================================
  // UTILITAIRES
  // ============================================================

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

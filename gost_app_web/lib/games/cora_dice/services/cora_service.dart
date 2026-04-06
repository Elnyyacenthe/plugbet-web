// ============================================================
// CORA DICE - Service Supabase
// Gère rooms, parties, logique de jeu et realtime
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cora_models.dart';

class CoraService {
  late final SupabaseClient _client;

  CoraService() {
    _client = Supabase.instance.client;
  }

  String? get currentUserId => _client.auth.currentUser?.id;

  // ============================================================
  // ROOMS
  // ============================================================

  /// Créer une room
  Future<Map<String, dynamic>?> createRoom({
    required int playerCount,
    required bool isPrivate,
    int betAmount = 200,
  }) async {
    try {
      final result = await _client.rpc('create_cora_room', params: {
        'p_player_count': playerCount,
        'p_bet_amount': betAmount,
        'p_is_private': isPrivate,
      });
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('Erreur createRoom: $e');
      rethrow;
    }
  }

  /// Rejoindre une room par code
  Future<String?> joinRoom(String code) async {
    try {
      final result = await _client.rpc('join_cora_room', params: {
        'p_code': code.toUpperCase(),
      });
      debugPrint('[CORA] joinRoom raw: $result (${result.runtimeType})');
      if (result is Map) return result['room_id']?.toString();
      if (result is String) return result;
      return result?.toString();
    } catch (e) {
      debugPrint('Erreur joinRoom: $e');
      rethrow;
    }
  }

  /// Supprimer les salles en attente > 1h
  Future<void> cleanupStaleRooms() async {
    try {
      await _client.from('cora_rooms')
          .delete()
          .eq('status', 'waiting')
          .lt('created_at', DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());
    } catch (_) {}
  }

  /// Lister les rooms publiques
  Future<List<CoraRoom>> getPublicRooms() async {
    try {
      final data = await _client
          .from('cora_rooms')
          .select()
          .eq('status', 'waiting')
          .eq('is_private', false)
          .order('created_at', ascending: false)
          .limit(20);
      return (data as List).map((r) => CoraRoom.fromJson(r)).toList();
    } catch (e) {
      debugPrint('Erreur getPublicRooms: $e');
      return [];
    }
  }

  /// Récupérer une room par ID
  Future<CoraRoom?> getRoom(String roomId) async {
    try {
      final data = await _client
          .from('cora_rooms')
          .select()
          .eq('id', roomId)
          .maybeSingle();
      if (data == null) return null;
      return CoraRoom.fromJson(data);
    } catch (e) {
      debugPrint('Erreur getRoom: $e');
      return null;
    }
  }

  /// Marquer joueur comme prêt (update direct sans RPC problématique)
  Future<void> markReady(String roomId, bool isReady) async {
    try {
      final uid = currentUserId;
      if (uid == null) return;
      await _client.from('cora_room_players').update({
        'is_ready': isReady,
      }).eq('room_id', roomId).eq('user_id', uid);
    } catch (e) {
      debugPrint('Erreur markReady: $e');
    }
  }

  /// Quitter/supprimer une room
  Future<void> deleteRoom(String roomId) async {
    try {
      await _client.from('cora_rooms').delete().eq('id', roomId);
    } catch (e) {
      debugPrint('Erreur deleteRoom: $e');
    }
  }

  /// Écouter les mises à jour d'une room
  RealtimeChannel subscribeRoom(String roomId, void Function(CoraRoom) onUpdate) {
    return _client
        .channel('cora-room-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'cora_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final room = CoraRoom.fromJson(payload.newRecord);
              onUpdate(room);
            } catch (e) {
              debugPrint('Erreur parsing room update: $e');
            }
          },
        )
        .subscribe();
  }

  /// Démarrer la partie quand tous les joueurs sont prêts
  Future<String?> startGame(String roomId) async {
    try {
      final result = await _client.rpc('start_cora_game', params: {
        'p_room_id': roomId,
      });
      debugPrint('[CORA] startGame raw: $result (${result.runtimeType})');
      final gameId = result?.toString();
      debugPrint('[CORA] startGame: $gameId');
      return gameId;
    } catch (e) {
      debugPrint('[CORA] Erreur startGame: $e');
      return null;
    }
  }

  /// Auto-continue : vérifie les soldes et reset la manche
  Future<String> autoContinue(String gameId) async {
    try {
      final result = await _client.rpc('cora_auto_continue', params: {
        'p_game_id': gameId,
      });
      debugPrint('[CORA] autoContinue: $result');
      return result?.toString() ?? 'ended';
    } catch (e) {
      debugPrint('[CORA] Erreur autoContinue: $e');
      return 'ended';
    }
  }

  // ============================================================
  // GAME
  // ============================================================

  /// Récupérer une partie
  Future<CoraGame?> getGame(String gameId) async {
    try {
      final data = await _client
          .from('cora_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (data == null) return null;
      return CoraGame.fromJson(data);
    } catch (e) {
      debugPrint('Erreur getGame: $e');
      return null;
    }
  }

  /// Lancer les dés
  Future<DiceRoll> rollDice() async {
    final random = Random();
    final dice1 = random.nextInt(6) + 1;
    final dice2 = random.nextInt(6) + 1;

    return DiceRoll(
      dice1: dice1,
      dice2: dice2,
      timestamp: DateTime.now(),
    );
  }

  /// Soumettre un lancer
  Future<void> submitRoll({
    required String gameId,
    required DiceRoll roll,
  }) async {
    try {
      await _client.rpc('submit_cora_roll', params: {
        'p_game_id': gameId,
        'p_dice1': roll.dice1,
        'p_dice2': roll.dice2,
      });
    } catch (e) {
      debugPrint('Erreur submitRoll: $e');
      rethrow;
    }
  }

  /// Calculer le résultat final (appelé côté serveur normalement)
  Map<String, dynamic> calculateResult(CoraGameState state) {
    final players = state.players.values.toList();

    // 1. Vérifier Cora multiple → annulation
    final coraPlayers = players.where((p) => p.hasCora).toList();
    if (coraPlayers.length > 1) {
      return {
        'status': 'cancelled',
        'result': 'Plusieurs Cora ! Partie annulée, remboursement total.',
        'winners': <String>[],
        'payouts': {for (final p in players) p.userId: 0}, // Remboursement géré ailleurs
      };
    }

    // 2. Vérifier Cora unique → double pot
    if (coraPlayers.length == 1) {
      final winner = coraPlayers.first;
      return {
        'status': 'finished',
        'result': '${winner.username} a fait CORA ! Double pot !',
        'winners': [winner.userId],
        'is_cora_win': true,
      };
    }

    // 3. Calculer scores (7 = -1 effectif)
    final scores = <String, int>{};
    for (final player in players) {
      if (player.hasSeven) {
        scores[player.userId] = -1; // 7 perd auto
      } else {
        scores[player.userId] = player.roll?.total ?? 0;
      }
    }

    // 4. Trouver le max score
    final maxScore = scores.values.reduce((a, b) => a > b ? a : b);
    if (maxScore <= 0) {
      // Tous ont 7 → annulation
      return {
        'status': 'cancelled',
        'result': 'Tous les joueurs ont fait 7 ! Partie annulée.',
        'winners': <String>[],
      };
    }

    // 5. Trouver les gagnants
    final winners =
        scores.entries.where((e) => e.value == maxScore).map((e) => e.key).toList();

    // 6. Égalité → annulation
    if (winners.length > 1) {
      return {
        'status': 'cancelled',
        'result': 'Égalité parfaite ! Partie annulée, remboursement.',
        'winners': <String>[],
      };
    }

    // 7. Un seul gagnant → pot normal
    final winnerId = winners.first;
    final winnerPlayer = players.firstWhere((p) => p.userId == winnerId);
    return {
      'status': 'finished',
      'result': '${winnerPlayer.username} gagne avec $maxScore !',
      'winners': [winnerId],
      'is_cora_win': false,
    };
  }

  /// Écouter les mises à jour d'une partie
  RealtimeChannel subscribeGame(
    String gameId,
    void Function(CoraGame) onUpdate,
  ) {
    return _client
        .channel('cora-game-$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'cora_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            try {
              final game = CoraGame.fromJson(payload.newRecord);
              onUpdate(game);
            } catch (e) {
              debugPrint('Erreur parsing game update: $e');
            }
          },
        )
        .subscribe();
  }

  // ============================================================
  // CHAT
  // ============================================================

  /// Envoyer un message
  Future<void> sendMessage(String roomId, String message) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      // Récupérer le username du joueur
      String username = 'Joueur';
      try {
        final profile = await _client
            .from('user_profiles')
            .select('username')
            .eq('id', userId)
            .maybeSingle();
        if (profile != null && (profile['username'] as String?)?.isNotEmpty == true) {
          username = profile['username'] as String;
        }
      } catch (_) {}

      await _client.from('cora_messages').insert({
        'room_id': roomId,
        'user_id': userId,
        'username': username,
        'message': message,
      });
    } catch (e) {
      debugPrint('Erreur sendMessage: $e');
    }
  }

  /// Charger les messages
  Future<List<CoraMessage>> getMessages(String roomId) async {
    try {
      final data = await _client
          .from('cora_messages')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: true)
          .limit(50);
      return (data as List).map((r) => CoraMessage.fromJson(r)).toList();
    } catch (e) {
      debugPrint('Erreur getMessages: $e');
      return [];
    }
  }

  /// Écouter les nouveaux messages
  RealtimeChannel subscribeMessages(
    String roomId,
    void Function(CoraMessage) onMessage,
  ) {
    return _client
        .channel('cora-messages-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'cora_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final msg = CoraMessage.fromJson(payload.newRecord);
              onMessage(msg);
            } catch (e) {
              debugPrint('Erreur parsing message: $e');
            }
          },
        )
        .subscribe();
  }

  /// Se désabonner d'un channel
  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}

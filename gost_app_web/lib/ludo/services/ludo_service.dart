// ============================================================
// LUDO MODULE - Service Supabase
// Gère : profil, coins, lobby, challenges, games, realtime
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ludo_models.dart';

class LudoService {
  late final SupabaseClient _client;

  LudoService() {
    _client = Supabase.instance.client;
  }

  String? get currentUserId => _client.auth.currentUser?.id;

  // ============================================================
  // PROFIL & COINS
  // ============================================================

  /// Récupérer ou créer le profil de l'utilisateur courant
  Future<UserProfile?> getMyProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final data = await _client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data != null) {
        return UserProfile.fromJson(data);
      }

      // Créer le profil s'il n'existe pas
      final newProfile = {
        'id': userId,
        'username': 'Player_${userId.substring(0, 6)}',
        'coins': 500,
      };
      await _client.from('user_profiles').upsert(newProfile);
      return UserProfile.fromJson(newProfile);
    } catch (e) {
      debugPrint('Erreur getMyProfile: $e');
      return null;
    }
  }

  /// Mettre à jour le pseudo
  Future<void> updateUsername(String username) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _client
        .from('user_profiles')
        .update({'username': username, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', userId);
  }

  /// Récupérer le solde coins
  Future<int> getCoins() async {
    final profile = await getMyProfile();
    return profile?.coins ?? 0;
  }

  // ============================================================
  // LOBBY - Présence en ligne
  // ============================================================

  /// Signaler sa présence dans le lobby
  Future<void> joinLobby() async {
    final userId = currentUserId;
    if (userId == null) return;

    final profile = await getMyProfile();
    if (profile == null) return;

    try {
      await _client.from('ludo_online').upsert({
        'user_id': userId,
        'username': profile.username,
        'coins': profile.coins,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Erreur joinLobby: $e');
    }
  }

  /// Mettre à jour le heartbeat (toutes les 30s)
  Future<void> updatePresence() async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await _client
          .from('ludo_online')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Erreur updatePresence: $e');
    }
  }

  /// Quitter le lobby
  Future<void> leaveLobby() async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await _client.from('ludo_online').delete().eq('user_id', userId);
    } catch (e) {
      debugPrint('Erreur leaveLobby: $e');
    }
  }

  /// Récupérer les joueurs en ligne (vus dans les 2 dernières minutes)
  Future<List<OnlinePlayer>> getOnlinePlayers() async {
    final userId = currentUserId;
    try {
      final cutoff =
          DateTime.now().subtract(const Duration(minutes: 2)).toUtc().toIso8601String();
      final data = await _client
          .from('ludo_online')
          .select()
          .gte('last_seen', cutoff)
          .order('last_seen', ascending: false);

      return (data as List)
          .map((row) => OnlinePlayer.fromJson(row))
          .where((p) => p.userId != userId)
          .toList();
    } catch (e) {
      debugPrint('Erreur getOnlinePlayers: $e');
      return [];
    }
  }

  /// Écouter les changements du lobby en temps réel
  RealtimeChannel subscribeLobby(void Function() onUpdate) {
    return _client
        .channel('ludo-lobby')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ludo_online',
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  // ============================================================
  // CHALLENGES (Défis)
  // ============================================================

  /// Envoyer un défi à un joueur
  Future<LudoChallenge?> sendChallenge(String toUserId, int betAmount) async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final data = await _client
          .from('ludo_challenges')
          .insert({
            'from_user': userId,
            'to_user': toUserId,
            'bet_amount': betAmount,
            'status': 'pending',
          })
          .select()
          .single();

      return LudoChallenge.fromJson(data);
    } catch (e) {
      debugPrint('Erreur sendChallenge: $e');
      return null;
    }
  }

  /// Accepter un défi (appelle la fonction sécurisée Supabase)
  Future<String?> acceptChallenge(String challengeId) async {
    try {
      final result = await _client.rpc('accept_challenge', params: {
        'p_challenge_id': challengeId,
      });

      // Le résultat est l'ID de la partie créée
      if (result is String) return result;
      if (result != null) return result.toString();
      return null;
    } catch (e) {
      debugPrint('Erreur acceptChallenge: $e');
      rethrow;
    }
  }

  /// Refuser un défi
  Future<void> declineChallenge(String challengeId) async {
    try {
      await _client
          .from('ludo_challenges')
          .update({
            'status': 'declined',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', challengeId);
    } catch (e) {
      debugPrint('Erreur declineChallenge: $e');
    }
  }

  /// Récupérer les défis en attente reçus
  Future<List<LudoChallenge>> getPendingChallenges() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
      final data = await _client
          .from('ludo_challenges')
          .select()
          .eq('to_user', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return (data as List).map((row) => LudoChallenge.fromJson(row)).toList();
    } catch (e) {
      debugPrint('Erreur getPendingChallenges: $e');
      return [];
    }
  }

  /// Écouter les nouveaux défis en temps réel
  RealtimeChannel subscribeChallenges(void Function(LudoChallenge) onChallenge) {
    final userId = currentUserId;

    return _client
        .channel('ludo-challenges-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ludo_challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_user',
            value: userId!,
          ),
          callback: (payload) {
            final challenge = LudoChallenge.fromJson(payload.newRecord);
            onChallenge(challenge);
          },
        )
        .subscribe();
  }

  /// Écouter les mises à jour de mes défis envoyés (accepted/declined)
  RealtimeChannel subscribeMyChallengeUpdates(
      void Function(LudoChallenge) onUpdate) {
    final userId = currentUserId;

    return _client
        .channel('ludo-my-challenges-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ludo_challenges',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'from_user',
            value: userId!,
          ),
          callback: (payload) {
            final challenge = LudoChallenge.fromJson(payload.newRecord);
            onUpdate(challenge);
          },
        )
        .subscribe();
  }

  // ============================================================
  // GAME (Partie)
  // ============================================================

  /// Récupérer une partie par ID
  Future<LudoGame?> getGame(String gameId) async {
    try {
      final data = await _client
          .from('ludo_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();

      if (data == null) return null;
      return LudoGame.fromJson(data);
    } catch (e) {
      debugPrint('Erreur getGame: $e');
      return null;
    }
  }

  /// Mettre à jour l'état du jeu (après un mouvement)
  Future<void> updateGameState({
    required String gameId,
    required LudoGameState newState,
    required String nextTurn,
    String? winnerId,
  }) async {
    try {
      final update = <String, dynamic>{
        'game_state': newState.toJson(),
        'current_turn': nextTurn,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (winnerId != null) {
        update['status'] = 'finished';
        update['winner_id'] = winnerId;
      }

      await _client.from('ludo_games').update(update).eq('id', gameId);

      // Si victoire, appeler la fonction de fin de partie
      if (winnerId != null) {
        await _client.rpc('finish_ludo_game', params: {
          'p_game_id': gameId,
          'p_winner_id': winnerId,
        });
      }
    } catch (e) {
      debugPrint('Erreur updateGameState: $e');
      rethrow;
    }
  }

  /// Abandonner la partie
  Future<void> abandonGame(String gameId) async {
    try {
      await _client.rpc('abandon_ludo_game', params: {
        'p_game_id': gameId,
      });
    } catch (e) {
      debugPrint('Erreur abandonGame: $e');
      rethrow;
    }
  }

  /// Annuler la partie (bug systeme) - rembourse les deux joueurs
  Future<void> cancelGame(String gameId) async {
    try {
      await _client.rpc('cancel_ludo_game', params: {
        'p_game_id': gameId,
      });
    } catch (e) {
      debugPrint('Erreur cancelGame: $e');
      rethrow;
    }
  }

  /// Écouter les changements d'une partie en temps réel
  RealtimeChannel subscribeGame(
    String gameId,
    void Function(LudoGame) onUpdate,
  ) {
    return _client
        .channel('ludo-game-$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ludo_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            try {
              final game = LudoGame.fromJson(payload.newRecord);
              onUpdate(game);
            } catch (e) {
              debugPrint('Erreur parsing game update: $e');
            }
          },
        )
        .subscribe();
  }

  /// Se désabonner d'un channel
  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }

  /// Récupérer le profil d'un joueur par ID
  Future<UserProfile?> getPlayerProfile(String userId) async {
    try {
      final data = await _client
          .from('user_profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data == null) return null;
      return UserProfile.fromJson(data);
    } catch (e) {
      debugPrint('Erreur getPlayerProfile: $e');
      return null;
    }
  }

  // ============================================================
  // ROOMS (Salles)
  // ============================================================

  /// Creer une salle
  Future<Map<String, dynamic>?> createRoom(
    int betAmount,
    bool isPrivate, {
    int playerCount = 2,
  }) async {
    try {
      final result = await _client.rpc('create_ludo_room', params: {
        'p_bet_amount': betAmount,
        'p_is_private': isPrivate,
        'p_player_count': playerCount,
      });
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('Erreur createRoom: $e');
      rethrow;
    }
  }

  /// Rejoindre une salle par code
  Future<String?> joinRoom(String code) async {
    try {
      final result = await _client.rpc('join_ludo_room', params: {
        'p_code': code.toUpperCase(),
      });
      debugPrint('[LUDO] joinRoom RPC result: $result (type: ${result.runtimeType})');
      if (result is String && result.isNotEmpty) return result;
      if (result != null && result.toString().isNotEmpty && result.toString() != 'null') {
        return result.toString();
      }
      // Le RPC a retourné null → la salle n'est pas encore pleine (4 joueurs)
      // Chercher le room_id via le code pour écouter les updates
      debugPrint('[LUDO] joinRoom: gameId null, chercher room par code...');
      final rooms = await _client
          .from('ludo_rooms')
          .select('id, game_id, status')
          .eq('code', code.toUpperCase())
          .limit(1);
      if (rooms.isNotEmpty) {
        final room = rooms.first;
        debugPrint('[LUDO] Room trouvée: ${room['id']}, status=${room['status']}, game_id=${room['game_id']}');
        if (room['game_id'] != null) return room['game_id'] as String;
      }
      return null;
    } catch (e) {
      debugPrint('[LUDO] Erreur joinRoom: $e');
      rethrow;
    }
  }

  /// Lister les salles publiques en attente
  Future<List<LudoRoom>> getPublicRooms({int? playerCount}) async {
    try {
      var query = _client
          .from('ludo_rooms')
          .select()
          .eq('status', 'waiting')
          .eq('is_private', false);

      if (playerCount != null) {
        query = query.eq('player_count', playerCount);
      }

      final data = await query
          .order('created_at', ascending: false)
          .limit(20);

      return (data as List).map((r) => LudoRoom.fromJson(r)).toList();
    } catch (e) {
      debugPrint('Erreur getPublicRooms: $e');
      return [];
    }
  }

  /// Ecouter les mises a jour d'une salle
  RealtimeChannel subscribeRoom(String roomId, void Function(LudoRoom) onUpdate) {
    return _client
        .channel('ludo-room-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ludo_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              debugPrint('[LUDO-RT] Room update reçu: status=${payload.newRecord['status']}, game_id=${payload.newRecord['game_id']}, guest_id=${payload.newRecord['guest_id']}');
              final room = LudoRoom.fromJson(payload.newRecord);
              debugPrint('[LUDO-RT] Room parsed: status=${room.status}, gameId=${room.gameId}, isFull=${room.isFull}');
              onUpdate(room);
            } catch (e) {
              debugPrint('[LUDO-RT] Erreur parsing room update: $e');
              debugPrint('[LUDO-RT] Raw payload: ${payload.newRecord}');
            }
          },
        )
        .subscribe();
  }

  /// Supprimer une salle en attente
  Future<void> deleteRoom(String roomId) async {
    try {
      await _client.from('ludo_rooms').delete().eq('id', roomId);
    } catch (e) {
      debugPrint('Erreur deleteRoom: $e');
    }
  }

  // ============================================================
  // CHAT
  // ============================================================

  /// Envoyer un message
  Future<void> sendChatMessage(String gameId, String message) async {
    final userId = currentUserId;
    if (userId == null) return;

    try {
      await _client.from('ludo_chat').insert({
        'game_id': gameId,
        'user_id': userId,
        'message': message,
      });
    } catch (e) {
      debugPrint('Erreur sendChatMessage: $e');
    }
  }

  /// Charger les messages d'une partie
  Future<List<ChatMessage>> getChatMessages(String gameId) async {
    try {
      final data = await _client
          .from('ludo_chat')
          .select()
          .eq('game_id', gameId)
          .order('created_at', ascending: true)
          .limit(100);
      return (data as List).map((r) => ChatMessage.fromJson(r)).toList();
    } catch (e) {
      debugPrint('Erreur getChatMessages: $e');
      return [];
    }
  }

  /// Ecouter les nouveaux messages en temps reel
  RealtimeChannel subscribeChatMessages(
    String gameId,
    void Function(ChatMessage) onMessage,
  ) {
    return _client
        .channel('ludo-chat-$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ludo_chat',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: gameId,
          ),
          callback: (payload) {
            try {
              final msg = ChatMessage.fromJson(payload.newRecord);
              onMessage(msg);
            } catch (e) {
              debugPrint('Erreur parsing chat message: $e');
            }
          },
        )
        .subscribe();
  }
}

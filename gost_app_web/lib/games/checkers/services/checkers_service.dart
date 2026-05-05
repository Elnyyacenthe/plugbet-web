// ============================================================
// Checkers – Service Supabase (rooms, état de jeu, FCFA)
// ============================================================

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/wallet_service.dart';
import '../models/checkers_models.dart';

class CheckersService {
  final SupabaseClient _client = Supabase.instance.client;
  final WalletService _wallet = WalletService();

  String? get currentUserId => _client.auth.currentUser?.id;

  // Délégation à la caisse générale
  Future<Map<String, dynamic>?> getProfile() => _wallet.getProfile();
  Future<int> getCoins() => _wallet.getCoins();
  Future<String> getUsername() => _wallet.getUsername();
  Future<bool> deductCoins(int amount) => _wallet.deductCoins(amount);
  Future<void> addCoins(int amount) => _wallet.addCoins(amount);

  // ============================================================
  // ROOMS
  // ============================================================

  /// Crée une room et débite la mise via le treasury unifie.
  Future<CheckersRoom?> createRoom({
    required int betAmount,
    required bool isPrivate,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      final color = Random().nextBool() ? 'red' : 'black';
      final result = await _client.rpc('checkers_create_room', params: {
        'p_bet_amount': betAmount,
        'p_is_private': isPrivate,
        'p_host_color': color,
      });
      if (result is Map) {
        return CheckersRoom.fromJson(Map<String, dynamic>.from(result));
      }
      return null;
    } catch (e) {
      debugPrint('[CHECKERS] createRoom error: $e');
      return null;
    }
  }

  /// Rejoindre une room par ID via le treasury unifie.
  Future<CheckersRoom?> joinRoom(String roomId) async {
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      final initialState = CheckersGameState.initial();
      final result = await _client.rpc('checkers_join_room', params: {
        'p_room_id': roomId,
        'p_initial_state': initialState.toJson(),
      });
      if (result is Map) {
        return CheckersRoom.fromJson(Map<String, dynamic>.from(result));
      }
      return null;
    } catch (e) {
      debugPrint('[CHECKERS] joinRoom error: $e');
      return null;
    }
  }

  /// Rejoindre par code privé
  Future<CheckersRoom?> joinByCode(String code) async {
    try {
      final data = await _client
          .from('checkers_rooms')
          .select()
          .eq('private_code', code.toUpperCase())
          .eq('status', 'waiting')
          .maybeSingle();
      if (data == null) return null;
      return joinRoom(data['id'] as String);
    } catch (e) {
      debugPrint('[CHECKERS] joinByCode error: $e');
      return null;
    }
  }

  /// Supprimer les salles en attente > 1h
  Future<void> cleanupStaleRooms() async {
    try {
      await _client.from('checkers_rooms')
          .delete()
          .eq('status', 'waiting')
          .lt('created_at', DateTime.now().subtract(const Duration(hours: 1)).toIso8601String());
    } catch (_) {}
  }

  /// Recuperer une room par son ID (utilise par le polling de secours)
  Future<CheckersRoom?> getRoom(String roomId) async {
    try {
      final data = await _client
          .from('checkers_rooms')
          .select()
          .eq('id', roomId)
          .maybeSingle();
      if (data == null) return null;
      return CheckersRoom.fromJson(data);
    } catch (e) {
      debugPrint('[CHECKERS] getRoom error: $e');
      return null;
    }
  }

  /// Rooms publiques en attente
  Future<List<CheckersRoom>> getPublicRooms() async {
    try {
      final data = await _client
          .from('checkers_rooms')
          .select()
          .eq('status', 'waiting')
          .eq('is_private', false)
          .order('created_at', ascending: false)
          .limit(20);
      return (data as List).map((j) => CheckersRoom.fromJson(j)).toList();
    } catch (e) {
      debugPrint('[CHECKERS] getPublicRooms error: $e');
      return [];
    }
  }

  // ============================================================
  // ÉTAT DE JEU
  // ============================================================

  /// Met à jour l'état du jeu via la RPC dédiée (anti-cheat).
  /// Le UPDATE direct est bloqué par RLS depuis checkers_anti_cheat_v1.sql.
  /// Pour terminer la partie, utiliser distributeWinnings (->finish_game RPC),
  /// pas updateGameState (qui rejette les states avec isGameOver=true).
  Future<void> updateGameState(String roomId, CheckersGameState state) async {
    try {
      // On ne pousse PAS l'etat de fin via cette route — la RPC le rejette.
      // La fin sera transmise par distributeWinnings (checkers_finish_game).
      if (state.isGameOver) return;
      await _client.rpc('checkers_update_state', params: {
        'p_room_id': roomId,
        'p_game_state': state.toJson(),
      });
    } catch (e) {
      debugPrint('[CHECKERS] updateGameState error: $e');
    }
  }

  /// Distribue les FCFA à la fin de la partie via le treasury unifie.
  /// - Vainqueur connu : checkers_finish_game (90% au winner, 10% caisse)
  /// - Match nul        : checkers_draw_game (refund 100% sans commission)
  /// Throw si le RPC echoue : le caller doit gerer pour informer l'utilisateur.
  Future<void> distributeWinnings({
    required String roomId,
    required String? winnerId,
    required String hostId,
    required String? guestId,
    required int pot,
    CheckersGameState? finalState,
  }) async {
    if (winnerId != null) {
      await _client.rpc('checkers_finish_game', params: {
        'p_room_id': roomId,
        'p_winner_id': winnerId,
        if (finalState != null) 'p_final_state': finalState.toJson(),
      });
    } else {
      await _client.rpc('checkers_draw_game', params: {
        'p_room_id': roomId,
        if (finalState != null) 'p_final_state': finalState.toJson(),
      });
    }
  }

  Future<void> addCoinsToUser(String userId, int amount) =>
      _wallet.addCoinsToUser(userId, amount);

  // ============================================================
  // REALTIME
  // ============================================================

  RealtimeChannel? _roomChannel;

  void subscribeToRoom(String roomId, void Function(CheckersRoom) onUpdate) {
    _roomChannel?.unsubscribe();
    _roomChannel = _client
        .channel('checkers_room_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'checkers_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final room = CheckersRoom.fromJson(payload.newRecord);
              onUpdate(room);
            } catch (e) {
              debugPrint('[CHECKERS] realtime parse error: $e');
            }
          },
        )
        .subscribe();
  }

  void unsubscribe() {
    _roomChannel?.unsubscribe();
    _roomChannel = null;
  }

  // ============================================================
  // CHAT
  // ============================================================

  Future<void> sendMessage(String roomId, String text) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      String username = 'Joueur';
      try {
        final p = await _client.from('user_profiles').select('username')
            .eq('id', uid).maybeSingle();
        if (p != null && (p['username'] as String?)?.isNotEmpty == true) {
          username = p['username'] as String;
        }
      } catch (_) {}
      await _client.from('checkers_messages').insert({
        'room_id': roomId,
        'user_id': uid,
        'username': username,
        'message': text,
      });
    } catch (e) {
      debugPrint('[CHECKERS] sendMessage error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(String roomId) async {
    try {
      final data = await _client.from('checkers_messages')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: true)
          .limit(50);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  RealtimeChannel subscribeMessages(
    String roomId,
    void Function(Map<String, dynamic>) onMessage,
  ) {
    return _client
        .channel('checkers-msg-$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'checkers_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) => onMessage(payload.newRecord),
        )
        .subscribe();
  }

}

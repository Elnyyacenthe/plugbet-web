// ============================================================
// Checkers – Service Supabase (rooms, état de jeu, coins)
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

  /// Crée une room et débite la mise
  Future<CheckersRoom?> createRoom({
    required int betAmount,
    required bool isPrivate,
  }) async {
    final uid = currentUserId;
    if (uid == null) return null;

    final ok = await deductCoins(betAmount);
    if (!ok) return null;

    try {
      final username = await getUsername();
      final code = isPrivate ? _generateCode() : null;
      final color = Random().nextBool() ? 'red' : 'black';

      final data = await _client.from('checkers_rooms').insert({
        'host_id': uid,
        'host_username': username,
        'bet_amount': betAmount,
        'is_private': isPrivate,
        'private_code': code,
        'status': 'waiting',
        'host_color': color,
        'pot': betAmount,
      }).select().single();

      return CheckersRoom.fromJson(data);
    } catch (e) {
      // Rembourser si création échoue
      await addCoins(betAmount);
      debugPrint('[CHECKERS] createRoom error: $e');
      return null;
    }
  }

  /// Rejoindre une room par ID
  Future<CheckersRoom?> joinRoom(String roomId) async {
    final uid = currentUserId;
    if (uid == null) return null;

    try {
      final roomData = await _client
          .from('checkers_rooms')
          .select()
          .eq('id', roomId)
          .single();
      final room = CheckersRoom.fromJson(roomData);

      if (room.isFull || room.status != CheckersRoomStatus.waiting) return null;

      final ok = await deductCoins(room.betAmount);
      if (!ok) return null;

      final username = await getUsername();
      final guestColor = room.hostColor == 'red' ? 'black' : 'red';

      // Initialise l’état du jeu
      final initialState = CheckersGameState.initial();

      final updated = await _client.from('checkers_rooms').update({
        'guest_id': uid,
        'guest_username': username,
        'guest_color': guestColor,
        'status': 'playing',
        'pot': room.betAmount * 2,
        'game_state': initialState.toJson(),
      }).eq('id', roomId).select().single();

      return CheckersRoom.fromJson(updated);
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

  /// Met à jour l’état du jeu sur Supabase
  Future<void> updateGameState(String roomId, CheckersGameState state) async {
    try {
      await _client
          .from('checkers_rooms')
          .update({'game_state': state.toJson()}).eq('id', roomId);
    } catch (e) {
      debugPrint('[CHECKERS] updateGameState error: $e');
    }
  }

  /// Distribue les FCFA à la fin de la partie
  Future<void> distributeWinnings({
    required String roomId,
    required String? winnerId,
    required String hostId,
    required String? guestId,
    required int pot,
    CheckersGameState? finalState,
  }) async {
    try {
      if (winnerId != null) {
        await addCoinsToUser(winnerId, pot);
      } else {
        final half = pot ~/ 2;
        await addCoinsToUser(hostId, half);
        if (guestId != null) await addCoinsToUser(guestId, half);
      }

      // Mettre à jour room ET game_state pour que l'adversaire voit le résultat
      final updateData = <String, dynamic>{
        'status': 'finished',
        'winner_id': winnerId,
      };
      if (finalState != null) {
        updateData['game_state'] = finalState.toJson();
      }
      await _client.from('checkers_rooms').update(updateData).eq('id', roomId);
    } catch (e) {
      debugPrint('[CHECKERS] distributeWinnings error: $e');
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

  // ============================================================
  // UTILS
  // ============================================================

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

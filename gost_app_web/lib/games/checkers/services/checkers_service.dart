// ============================================================
// Checkers – Service Supabase (rooms, état de jeu, FCFA)
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../services/wallet_service.dart';
import '../../../services/game_audit_service.dart';
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
        final room = CheckersRoom.fromJson(Map<String, dynamic>.from(result));
        unawaited(GameAuditService.instance.logGameStart(
          gameId: room.id, gameType: 'checkers',
          payload: {'bet': betAmount, 'is_private': isPrivate, 'host_color': color},
        ));
        unawaited(GameAuditService.instance.logBetPlaced(
          gameId: room.id, gameType: 'checkers', amount: betAmount,
        ));
        return room;
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
        final room = CheckersRoom.fromJson(Map<String, dynamic>.from(result));
        unawaited(GameAuditService.instance.logEvent(
          gameId: room.id, gameType: 'checkers',
          eventType: 'player_joined',
        ));
        return room;
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

  /// DEPRECATED depuis checkers_v2_production.sql.
  /// Le client n'applique JAMAIS le move localement : tout passe par
  /// checkers_play_move() qui valide serveur. Cette methode reste pour
  /// compatibilite (no-op).
  Future<void> updateGameState(String roomId, CheckersGameState state) async {
    debugPrint('[CHECKERS] updateGameState called (deprecated, use playMove)');
  }

  /// Joue un move via la RPC serveur. Le serveur valide TOUT et renvoie le
  /// nouvel etat via Realtime. Le client se contente d'envoyer (from, to).
  ///
  /// Retour : Map avec :
  ///   - success: bool
  ///   - captured: bool
  ///   - promoted: bool
  ///   - must_continue: bool  (multi-capture obligatoire depuis dst)
  ///   - game_over: bool
  ///   - winner_color: 'red' | 'black' | null
  ///
  /// Idempotent : meme requestId = no-op.
  Future<Map<String, dynamic>> playMove({
    required String roomId,
    required int fromRow,
    required int fromCol,
    required int toRow,
    required int toCol,
    String? requestId,
  }) async {
    final reqId = requestId ?? Uuid().v4();
    final r = await _client.rpc('checkers_play_move', params: {
      'p_room_id': roomId,
      'p_from_r': fromRow,
      'p_from_c': fromCol,
      'p_to_r': toRow,
      'p_to_c': toCol,
      'p_request_id': reqId,
    });
    final result = Map<String, dynamic>.from(r as Map);
    unawaited(GameAuditService.instance.logMove(
      gameId: roomId, gameType: 'checkers',
      moveData: {
        'from': [fromRow, fromCol],
        'to': [toRow, toCol],
        'request_id': reqId,
        'result': result,
      },
    ));
    return result;
  }

  /// Compte un timeout serveur. Si 3 timeouts → forfait auto.
  Future<Map<String, dynamic>> registerTimeout(String roomId) async {
    final r = await _client.rpc('checkers_register_timeout', params: {
      'p_room_id': roomId,
    });
    return Map<String, dynamic>.from(r as Map);
  }

  /// Reclame une victoire si l'adversaire est idle > 90s.
  Future<Map<String, dynamic>> claimIdleWin(String roomId) async {
    final r = await _client.rpc('checkers_claim_idle_win', params: {
      'p_room_id': roomId,
    });
    return Map<String, dynamic>.from(r as Map);
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
      // S3 : p_final_state retire (le serveur ne fait plus confiance au state
      // client). Cette RPC n'accepte que le forfait (caller != winner).
      await _client.rpc('checkers_finish_game', params: {
        'p_room_id': roomId,
        'p_winner_id': winnerId,
      });
      unawaited(GameAuditService.instance.logGameEnd(
        gameId: roomId, gameType: 'checkers', won: true,
        extra: {'winner_id': winnerId, 'pot': pot},
      ));
    } else {
      await _client.rpc('checkers_draw_game', params: {
        'p_room_id': roomId,
        if (finalState != null) 'p_final_state': finalState.toJson(),
      });
      unawaited(GameAuditService.instance.logEvent(
        gameId: roomId, gameType: 'checkers', eventType: 'game_draw',
        payload: {'pot': pot, 'reason': 'draw_refund'},
      ));
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

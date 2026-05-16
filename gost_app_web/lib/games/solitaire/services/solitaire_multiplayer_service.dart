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

    final username = await _getUsername();
    final code = isPrivate ? _generateCode() : null;

    final initialState = SolitaireState.initial();
    final gameState = {
      ...initialState.toJson(),
      'players': [
        SolitaireRoomPlayer(id: uid, username: username).toJson(),
      ],
      'currentTurnIndex': 0,
    };

    try {
      // 1. Crée la row room avec un id généré côté DB
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

      final room = SolitaireRoom.fromJson(row);

      // 2. Débit via la RPC V2 (passe par _ledger_post, dual-source wallet_balance)
      try {
        await _client.rpc('solitaire_multi_place_bet', params: {
          'p_room_id': room.id,
          'p_amount': betAmount,
        });
        return room;
      } catch (e) {
        debugPrint('[SOL-MULTI] place_bet failed, rolling back room: $e');
        // Rollback : supprime la room créée si le débit échoue
        try {
          await _client.from('solitaire_rooms').delete().eq('id', room.id);
        } catch (_) {}
        return null;
      }
    } catch (e) {
      debugPrint('[SOL-MULTI] createRoom: $e');
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

      // Débit via la nouvelle RPC V2 (passe par _ledger_post + wallet_balance dual-source)
      try {
        await _client.rpc('solitaire_multi_place_bet', params: {
          'p_room_id': room.id,
          'p_amount': room.betAmount,
        });
      } catch (e) {
        debugPrint('[SOL-MULTI] joinRoom place_bet failed: $e');
        return null;
      }

      final username = await _getUsername();
      // [C2 P2] Mutation room atomique côté serveur (RPC SECURITY
      // DEFINER) au lieu d'un UPDATE direct : le serveur ajoute le
      // joueur, incrémente pot/current_players, passe en 'playing' si
      // plein, et supprime la race join (FOR UPDATE). Le plateau frais
      // n'est utilisé par le serveur QUE si la salle devient pleine
      // (scores tous à 0 -> aucun enjeu financier à ce stade).
      await _client.rpc('solitaire_multi_join', params: {
        'p_room_id': roomId,
        'p_username': username,
        'p_fresh_state': SolitaireState.initial().toJson(),
      });
      final refreshed = await _client
          .from('solitaire_rooms')
          .select()
          .eq('id', roomId)
          .single();

      return SolitaireRoom.fromJson(refreshed);
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
      // [C2 P2] Écriture du game_state via RPC SECURITY DEFINER au lieu
      // d'un UPDATE direct : le serveur fige les scores des autres
      // joueurs et clampe le score du caller (monotone, delta borné,
      // 0..1500). Stoppe la forge de score via PostgREST direct.
      await _client.rpc('solitaire_multi_push_state', params: {
        'p_room_id': roomId,
        'p_state': gameState,
      });
    } catch (e) {
      debugPrint('[SOL-MULTI] pushGameState: $e');
    }
  }

  // ============================================================
  // FIN DE PARTIE ET GAINS
  // ============================================================

  /// Finalise la partie via la RPC V2.
  /// Le serveur calcule pot - 10% commission + split si égalité.
  /// Retourne les détails du payout.
  Future<Map<String, dynamic>?> distributeWinnings(
    String roomId,
    List<SolitaireRoomPlayer> players,
  ) async {
    if (players.isEmpty) return null;
    try {
      // Trouver les gagnants côté CLIENT (highest score)
      final eligible = players.where((p) => !p.forfeited).toList();
      if (eligible.isEmpty) {
        // Tous forfeited → cancel sans winner
        final res = await _client.rpc('solitaire_multi_finalize', params: {
          'p_room_id': roomId,
          'p_winner_ids': <String>[],
        });
        return res is Map ? Map<String, dynamic>.from(res) : null;
      }
      final maxScore = eligible.map((p) => p.score).reduce(max);
      final winnerIds =
          eligible.where((p) => p.score == maxScore).map((p) => p.id).toList();

      // Le serveur calcule pot, commission, split
      final res = await _client.rpc('solitaire_multi_finalize', params: {
        'p_room_id': roomId,
        'p_winner_ids': winnerIds,
      });
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (e) {
      debugPrint('[SOL-MULTI] distributeWinnings: $e');
      return null;
    }
  }

  /// Forfait : un joueur quitte la partie.
  /// Pendant 'waiting' → refund + retire du players. Pendant 'playing' →
  /// FORFAIT (mise perdue, game continue). Si 1 seul restant → il gagne pot.
  Future<Map<String, dynamic>?> forfeit(String roomId) async {
    try {
      final res = await _client.rpc('solitaire_multi_forfeit', params: {
        'p_room_id': roomId,
      });
      return res is Map ? Map<String, dynamic>.from(res) : null;
    } catch (e) {
      debugPrint('[SOL-MULTI] forfeit: $e');
      return null;
    }
  }

  // ============================================================
  // ANNULER (HOST QUITTE EN LOBBY)
  // ============================================================

  /// Annule la room (host uniquement, status=waiting uniquement).
  /// Refund TOUS les players via la RPC V2 atomique.
  /// Returns true si annulé, false sinon (not-host, status mauvais, etc.)
  Future<bool> cancelRoom(String roomId) async {
    try {
      final res = await _client.rpc('solitaire_multi_cancel_room', params: {
        'p_room_id': roomId,
      });
      return res is Map && res['cancelled'] == true;
    } catch (e) {
      debugPrint('[SOL-MULTI] cancelRoom: $e');
      return false;
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

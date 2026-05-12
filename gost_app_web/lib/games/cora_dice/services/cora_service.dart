// ============================================================
// CORA DICE V3 — Service Supabase
// RPCs unifiées : cora_create_room, cora_join_room, cora_toggle_ready,
// cora_submit_roll, cora_forfeit, cora_leave_room, cora_get_active.
// + Idempotence anti double-tap (déduplication par clé d'action).
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cora_models.dart';
import '../../../services/game_audit_service.dart';

class CoraService {
  late final SupabaseClient _client;

  CoraService() {
    _client = Supabase.instance.client;
  }

  String? get currentUserId => _client.auth.currentUser?.id;

  // ============================================================
  // IDEMPOTENCE : déduplication des actions concurrentes
  // ============================================================
  // Si l'utilisateur tape 2× un bouton ou si un retry réseau déclenche
  // 2 appels simultanés sur la même action, on retourne le même Future
  // au lieu d'envoyer 2 RPCs.
  final Map<String, Future<dynamic>> _inFlight = {};

  Future<T> _dedup<T>(String key, Future<T> Function() fn) async {
    if (_inFlight.containsKey(key)) {
      return await _inFlight[key]! as T;
    }
    final fut = fn();
    _inFlight[key] = fut;
    try {
      return await fut;
    } finally {
      _inFlight.remove(key);
    }
  }

  // ============================================================
  // ROOMS
  // ============================================================

  /// Créer une room. Débite la mise du créateur via le ledger.
  Future<Map<String, dynamic>?> createRoom({
    required int playerCount,
    required bool isPrivate,
    int betAmount = 200,
  }) {
    final uid = currentUserId ?? 'anon';
    return _dedup('create:$uid:$betAmount:$playerCount', () async {
      try {
        final result = await _client.rpc('cora_create_room', params: {
          'p_player_count': playerCount,
          'p_bet_amount': betAmount,
          'p_is_private': isPrivate,
        });
        if (result is Map) {
          final map = Map<String, dynamic>.from(result);
          final roomId = map['room_id']?.toString();
          if (roomId != null) {
            unawaited(GameAuditService.instance.logGameStart(
              gameId: roomId, gameType: 'cora_dice',
              payload: {'bet': betAmount, 'player_count': playerCount, 'is_private': isPrivate},
            ));
            unawaited(GameAuditService.instance.logBetPlaced(
              gameId: roomId, gameType: 'cora_dice', amount: betAmount,
            ));
          }
          return map;
        }
        return null;
      } catch (e) {
        debugPrint('[CORA] createRoom: $e');
        rethrow;
      }
    });
  }

  /// Rejoindre une room par code. Débite la mise du joueur.
  Future<Map<String, dynamic>?> joinRoom(String code) {
    return _dedup('join:${code.toUpperCase()}', () async {
      try {
        final result = await _client.rpc('cora_join_room', params: {
          'p_code': code.toUpperCase(),
        });
        if (result is Map) {
          final map = Map<String, dynamic>.from(result);
          final roomId = map['room_id']?.toString();
          if (roomId != null) {
            unawaited(GameAuditService.instance.logEvent(
              gameId: roomId, gameType: 'cora_dice',
              eventType: 'player_joined',
              payload: {'code': code.toUpperCase()},
            ));
          }
          return map;
        }
        return null;
      } catch (e) {
        debugPrint('[CORA] joinRoom: $e');
        rethrow;
      }
    });
  }

  /// Quitter une room avant le démarrage. Refund automatique.
  Future<Map<String, dynamic>?> leaveRoom(String roomId) {
    return _dedup('leave:$roomId', () async {
      try {
        final result = await _client.rpc('cora_leave_room', params: {
          'p_room_id': roomId,
        });
        if (result is Map) return Map<String, dynamic>.from(result);
        return null;
      } catch (e) {
        debugPrint('[CORA] leaveRoom: $e');
        return null;
      }
    });
  }

  /// Lister les rooms publiques en attente.
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
      debugPrint('[CORA] getPublicRooms: $e');
      return [];
    }
  }

  /// Lire une room (pré-check côté client, ex. solde).
  /// Lance les exceptions au lieu de les avaler : le caller (lobby) doit
  /// pouvoir distinguer "row absente" (return null) de "erreur réseau/RLS"
  /// (throws).
  Future<CoraRoom?> getRoom(String roomId) async {
    final data = await _client
        .from('cora_rooms')
        .select()
        .eq('id', roomId)
        .maybeSingle();
    if (data == null) return null;
    return CoraRoom.fromJson(data);
  }

  /// Pre-check par code pour valider le solde avant join.
  Future<CoraRoom?> getRoomByCode(String code) async {
    try {
      final d = await _client
          .from('cora_rooms')
          .select()
          .eq('code', code.toUpperCase())
          .eq('status', 'waiting')
          .maybeSingle();
      return d != null ? CoraRoom.fromJson(d) : null;
    } catch (_) {
      return null;
    }
  }

  /// Marquer prêt / annuler. Le serveur démarre la partie auto si tous prêts.
  Future<Map<String, dynamic>?> toggleReady(String roomId, bool ready) {
    return _dedup('ready:$roomId:$ready', () async {
      try {
        final result = await _client.rpc('cora_toggle_ready', params: {
          'p_room_id': roomId,
          'p_ready': ready,
        });
        if (result is Map) return Map<String, dynamic>.from(result);
        return null;
      } catch (e) {
        debugPrint('[CORA] toggleReady: $e');
        rethrow;
      }
    });
  }

  /// Compat : ancienne API. Délègue vers toggleReady.
  Future<void> markReady(String roomId, bool isReady) async {
    await toggleReady(roomId, isReady);
  }

  /// Écouter les mises à jour d'une room.
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
              debugPrint('[CORA] parse room update: $e');
            }
          },
        )
        .subscribe();
  }

  // ============================================================
  // SESSION RESUME
  // ============================================================

  /// Récupère la session active (room en attente ou game en cours).
  /// Retourne null si rien d'actif.
  Future<Map<String, dynamic>?> getActiveSession() async {
    try {
      final result = await _client.rpc('cora_get_active');
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('[CORA] getActiveSession: $e');
      return null;
    }
  }

  /// Kill switch : abandonne TOUTES les rooms/games actives de l'utilisateur.
  /// Refund pour les rooms `waiting`, forfait pour les games `playing`.
  /// Utilisé pour débloquer TOO_MANY_ACTIVE_GAMES.
  Future<Map<String, dynamic>?> abandonAll() async {
    try {
      final result = await _client.rpc('cora_abandon_my_rooms');
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('[CORA] abandonAll: $e');
      return null;
    }
  }

  // ============================================================
  // GAME
  // ============================================================

  /// Récupérer une partie. Laisse remonter les exceptions pour que l'UI
  /// puisse distinguer "row absente" (return null) de "erreur réseau/RLS"
  /// (throws) — sinon le GameScreen reste sur spinner indéfiniment.
  Future<CoraGame?> getGame(String gameId) async {
    final data = await _client
        .from('cora_games')
        .select()
        .eq('id', gameId)
        .maybeSingle();
    if (data == null) return null;
    return CoraGame.fromJson(data);
  }

  /// Lancer les dés. Le SERVEUR génère les valeurs (anti-cheat).
  /// Retourne le DiceRoll réel calculé côté serveur.
  Future<DiceRoll?> submitRoll(String gameId) {
    return _dedup('roll:$gameId:${currentUserId ?? ""}', () async {
      try {
        final res = await _client.rpc('cora_submit_roll', params: {
          'p_game_id': gameId,
        });
        if (res is Map) {
          final d1 = (res['dice1'] as num).toInt();
          final d2 = (res['dice2'] as num).toInt();
          unawaited(GameAuditService.instance.logEvent(
            gameId: gameId, gameType: 'cora_dice',
            eventType: 'dice_roll',
            payload: {'dice1': d1, 'dice2': d2, 'sum': d1 + d2},
          ));
          return DiceRoll(
            dice1: d1, dice2: d2,
            timestamp: DateTime.now(),
          );
        }
        return null;
      } catch (e) {
        debugPrint('[CORA] submitRoll: $e');
        rethrow;
      }
    });
  }

  /// Compat : ancienne signature. Le `roll` côté client est ignoré.
  Future<DiceRoll?> submitRollAndGetServerDice({required String gameId}) {
    return submitRoll(gameId);
  }

  /// Compat : ancienne API legacy.
  @Deprecated('Use submitRoll(gameId) instead')
  Future<void> submitRollLegacy({
    required String gameId,
    required DiceRoll roll,
  }) async {
    await submitRoll(gameId);
  }

  /// Demande de revanche après une partie finie.
  /// Le 1er appel initialise un vote (30s timeout). Les autres participants
  /// votent en appelant cette même fonction. Quand tous acceptent, une
  /// nouvelle room/game est créée atomiquement et l'id est retourné.
  ///
  /// Retour : { status, new_game_id?, new_room_id?, accepted_count, total_needed,
  ///            proposer_id, expires_at, ... }
  Future<Map<String, dynamic>?> requestRematch(String gameId,
      {bool accept = true}) async {
    try {
      final result = await _client.rpc('cora_request_rematch', params: {
        'p_game_id': gameId,
        'p_accept': accept,
      });
      if (result is Map) return Map<String, dynamic>.from(result);
      return null;
    } catch (e) {
      debugPrint('[CORA] requestRematch: $e');
      rethrow;
    }
  }

  /// Forfait propre : marque le joueur comme abandonnant côté serveur.
  /// Sa mise est perdue. La partie continue ou se termine selon les autres.
  Future<Map<String, dynamic>?> forfeit(String gameId) {
    return _dedup('forfeit:$gameId', () async {
      try {
        final result = await _client.rpc('cora_forfeit', params: {
          'p_game_id': gameId,
        });
        if (result is Map) {
          unawaited(GameAuditService.instance.logGameEnd(
            gameId: gameId, gameType: 'cora_dice', won: false,
            extra: {'reason': 'forfeit'},
          ));
          return Map<String, dynamic>.from(result);
        }
        return null;
      } catch (e) {
        debugPrint('[CORA] forfeit: $e');
        return null;
      }
    });
  }

  /// Écouter les mises à jour d'une partie.
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
              debugPrint('[CORA] parse game update: $e');
            }
          },
        )
        .subscribe();
  }

  // ============================================================
  // CHAT
  // ============================================================

  /// Envoyer un message via la RPC sécurisée (rate-limited).
  Future<void> sendMessage(String roomId, String message) async {
    final text = message.trim();
    if (text.isEmpty) return;
    final uid = currentUserId ?? 'anon';
    return _dedup('msg:$roomId:$uid:${DateTime.now().millisecondsSinceEpoch ~/ 500}', () async {
      try {
        await _client.rpc('cora_send_message', params: {
          'p_room_id': roomId,
          'p_message': text,
        });
      } catch (e) {
        debugPrint('[CORA] sendMessage: $e');
      }
    });
  }

  /// Charger les messages.
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
      debugPrint('[CORA] getMessages: $e');
      return [];
    }
  }

  /// Écouter les nouveaux messages.
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
              debugPrint('[CORA] parse message: $e');
            }
          },
        )
        .subscribe();
  }

  /// Se désabonner d'un channel.
  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }

  // ============================================================
  // DEPRECATED — anciennes APIs supprimées
  // ============================================================

  @Deprecated('Use leaveRoom() — le serveur gère le refund.')
  Future<void> deleteRoom(String roomId) async {
    await leaveRoom(roomId);
  }

  @Deprecated('Géré côté serveur via cron pg_cron.')
  Future<void> cleanupStaleRooms() async {
    // No-op : le cron cora-cleanup-rooms s'en charge.
  }

  @Deprecated('Renommée en createRoom.')
  Future<String?> startGame(String roomId) async {
    debugPrint('[CORA] startGame déprécié : la partie démarre auto via cora_toggle_ready');
    return null;
  }

  @Deprecated('Géré côté serveur.')
  Future<String> autoContinue(String gameId) async {
    return 'ended';
  }

  @Deprecated('Le résultat est calculé côté serveur dans game_state.')
  Map<String, dynamic> calculateResult(CoraGameState state) {
    return {'status': 'finished', 'winners': <String>[]};
  }

  @Deprecated('Anciennement utilisé pour l\'animation locale (placeholder).')
  Future<DiceRoll> rollDice() async {
    return DiceRoll(dice1: 1, dice2: 1, timestamp: DateTime.now());
  }
}

// ============================================================
// GameAuditService — Logging d'events jeu pour traçabilité serveur
// ============================================================
// Wrap autour de la RPC log_game_event (definie dans
// supabase_audit_corrections.sql cote dashboard).
//
// Tout est best-effort : si Supabase n'est pas atteignable ou si
// la RPC n'existe pas encore, on log seulement en console et on
// ne casse JAMAIS la logique du jeu.
//
// Usage typique dans un service de jeu :
//
//   await GameAuditService.instance.logGameStart(
//     gameId: gameId, gameType: 'mines', payload: {'bet': 100, 'mines': 3});
//
//   await GameAuditService.instance.logBetPlaced(
//     gameId: gameId, gameType: 'mines', amount: 100);
//
//   await GameAuditService.instance.logGameEnd(
//     gameId: gameId, gameType: 'mines',
//     payload: {'won': true, 'multiplier': 1.5, 'payout': 150});
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class GameAuditService {
  GameAuditService._();
  static final GameAuditService instance = GameAuditService._();

  static const _uuid = Uuid();

  SupabaseClient get _client => Supabase.instance.client;

  /// Cœur : appelle la RPC `log_game_event`.
  /// Retourne true en cas de succes, false sinon (jamais throw).
  Future<bool> logEvent({
    required String gameId,
    required String gameType,
    required String eventType,
    Map<String, dynamic>? payload,
    Map<String, dynamic>? stateBefore,
    Map<String, dynamic>? stateAfter,
    String? requestId,
  }) async {
    try {
      // Si pas authentifie, skip silencieusement (jeux solo offline ok)
      if (_client.auth.currentUser == null) return false;

      await _client.rpc('log_game_event', params: {
        'p_game_id': gameId,
        'p_game_type': gameType,
        'p_event_type': eventType,
        'p_payload': payload ?? {},
        'p_state_before': stateBefore,
        'p_state_after': stateAfter,
        'p_request_id': requestId,
        'p_client_ts': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    } catch (e) {
      // Best-effort : on ne casse jamais le jeu
      if (kDebugMode) {
        debugPrint('[GameAudit] logEvent failed ($eventType): $e');
      }
      return false;
    }
  }

  /// Genere un UUID idempotency-key (a stocker cote game si retry possible)
  String generateRequestId() => _uuid.v4();

  // ─── Helpers semantiques ───────────────────────────────────────────

  Future<void> logGameStart({
    required String gameId,
    required String gameType,
    Map<String, dynamic>? payload,
  }) =>
      logEvent(
        gameId: gameId,
        gameType: gameType,
        eventType: 'game_start',
        payload: payload,
      );

  Future<void> logBetPlaced({
    required String gameId,
    required String gameType,
    required int amount,
    Map<String, dynamic>? extra,
  }) =>
      logEvent(
        gameId: gameId,
        gameType: gameType,
        eventType: 'bet_placed',
        payload: {'amount': amount, ...?extra},
      );

  Future<void> logDiceRoll({
    required String gameId,
    required String gameType,
    required int value,
    Map<String, dynamic>? extra,
  }) =>
      logEvent(
        gameId: gameId,
        gameType: gameType,
        eventType: 'dice_roll',
        payload: {'value': value, ...?extra},
      );

  Future<void> logMove({
    required String gameId,
    required String gameType,
    required Map<String, dynamic> moveData,
    Map<String, dynamic>? stateBefore,
    Map<String, dynamic>? stateAfter,
  }) =>
      logEvent(
        gameId: gameId,
        gameType: gameType,
        eventType: 'move',
        payload: moveData,
        stateBefore: stateBefore,
        stateAfter: stateAfter,
      );

  Future<void> logTurnChange({
    required String gameId,
    required String gameType,
    required String? nextUserId,
    Map<String, dynamic>? extra,
  }) =>
      logEvent(
        gameId: gameId,
        gameType: gameType,
        eventType: 'turn_change',
        payload: {'next_user': nextUserId, ...?extra},
      );

  Future<void> logGameEnd({
    required String gameId,
    required String gameType,
    required bool won,
    int? payout,
    Map<String, dynamic>? extra,
  }) =>
      logEvent(
        gameId: gameId,
        gameType: gameType,
        eventType: 'game_end',
        payload: {
          'won': won,
          if (payout != null) 'payout': payout,
          ...?extra,
        },
      );

  Future<void> logCrash({
    required String gameId,
    required String gameType,
    String? reason,
    Map<String, dynamic>? extra,
  }) =>
      logEvent(
        gameId: gameId,
        gameType: gameType,
        eventType: 'crash_detected',
        payload: {'reason': reason ?? 'unknown', ...?extra},
      );

  /// Wrapper idempotent autour des paiements de gain.
  /// Si requestId deja traite cote serveur, retourne le resultat memorise
  /// au lieu de re-payer (anti double-paiement sur retry reseau).
  Future<Map<String, dynamic>?> safeApplyPayout({
    required String requestId,
    required String userId,
    required int amount,
    required String gameType,
    required String gameId,
    String description = 'Gain',
  }) async {
    try {
      final result = await _client.rpc('safe_apply_payout', params: {
        'p_request_id': requestId,
        'p_user_id': userId,
        'p_amount': amount,
        'p_game_type': gameType,
        'p_game_id': gameId,
        'p_description': description,
      });
      return result as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[GameAudit] safeApplyPayout failed: $e');
      }
      return null;
    }
  }
}

// ============================================================
// PenaltyService — wrappers RPC Supabase (server-authoritative)
// ============================================================
// 3 RPCs : penalty_start_round, penalty_take_shot, penalty_abandon_round.
// Idempotence : penalty_start_round par p_request_id stable côté caller.
//               penalty_take_shot par UNIQUE(round_id, shot_index) serveur.
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/penalty_models.dart';
import '../../../services/game_audit_service.dart';

class PenaltyService {
  PenaltyService._();
  static final PenaltyService instance = PenaltyService._();

  final SupabaseClient _client = Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Démarre un round. Débit ledger + insert. Idempotent via requestId stable.
  /// Rethrows les erreurs métier (INSUFFICIENT_FUNDS, INVALID_BET_RANGE, etc.)
  /// pour que la UI les affiche proprement.
  Future<PenaltyRound> startRound({
    required int betAmount,
    int totalShots = 5,
    String? requestId,
  }) async {
    final reqId = requestId ??
        'penalty_round:${currentUserId ?? "anon"}:${DateTime.now().microsecondsSinceEpoch}';
    final res = await _client.rpc('penalty_start_round', params: {
      'p_bet_amount': betAmount,
      'p_total_shots': totalShots,
      'p_request_id': reqId,
    });
    if (res is! Map) {
      throw StateError('penalty_start_round: reponse inattendue ($res)');
    }
    final map = Map<String, dynamic>.from(res);
    final round = PenaltyRound.fromJson(map);
    unawaited(GameAuditService.instance.logGameStart(
      gameId: round.id,
      gameType: 'penalty',
      payload: {
        'bet': betAmount,
        'total_shots': totalShots,
        'request_id': reqId,
      },
    ));
    unawaited(GameAuditService.instance.logBetPlaced(
      gameId: round.id,
      gameType: 'penalty',
      amount: betAmount,
    ));
    return round;
  }

  /// Tire un coup. Le serveur génère la direction du gardien et décide.
  /// Si c'est le dernier tir et goals>misses, le payout est crédité dans la
  /// même transaction (atomique).
  Future<PenaltyShotResult> takeShot({
    required String roundId,
    required int shotIndex,
    required PenaltyDirection playerDirection,
  }) async {
    final res = await _client.rpc('penalty_take_shot', params: {
      'p_round_id': roundId,
      'p_shot_index': shotIndex,
      'p_player_direction': playerDirection.toJson(),
    });
    if (res is! Map) {
      throw StateError('penalty_take_shot: reponse inattendue ($res)');
    }
    final r = PenaltyShotResult.fromJson(Map<String, dynamic>.from(res));
    unawaited(GameAuditService.instance.logEvent(
      gameId: roundId,
      gameType: 'penalty',
      eventType: 'shot_taken',
      payload: {
        'shot_index': shotIndex,
        'player_dir': playerDirection.toJson(),
        'server_dir': r.serverDirection.toJson(),
        'outcome': r.outcome,
      },
    ));
    if (r.roundFinished) {
      unawaited(GameAuditService.instance.logGameEnd(
        gameId: roundId,
        gameType: 'penalty',
        won: r.roundStatus == PenaltyRoundStatus.won,
        extra: {
          'goals': r.goalsSoFar,
          'misses': r.missesSoFar,
          'payout': r.payout,
          'status': r.roundStatus.name,
        },
      ));
    }
    return r;
  }

  /// Abandonne un round actif (sortie volontaire). Mise déjà perdue.
  Future<void> abandonRound(String roundId) async {
    try {
      await _client.rpc('penalty_abandon_round', params: {
        'p_round_id': roundId,
      });
      unawaited(GameAuditService.instance.logGameEnd(
        gameId: roundId,
        gameType: 'penalty',
        won: false,
        extra: {'reason': 'abandoned'},
      ));
    } catch (e) {
      debugPrint('[PENALTY] abandonRound: $e');
    }
  }
}

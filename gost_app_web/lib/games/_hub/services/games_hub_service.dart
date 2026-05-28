// ============================================================
// GamesHubService — débit pay-to-play + audit
// ============================================================
// Réutilise WalletService.deductCoins (my_wallet_apply_delta + idempotence
// par referenceId). AUCUNE migration nouvelle.
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/game_model.dart';
import '../../../services/wallet_service.dart';
import '../../../services/game_audit_service.dart';

class GamesHubService {
  GamesHubService._();
  static final GamesHubService instance = GamesHubService._();

  // WalletService est un factory singleton -> on récupère l'instance.
  final WalletService _wallet = WalletService();

  Future<bool> startSession({
    required GameModel game,
    required String sessionId,
  }) async {
    if (game.entryPriceCoins == 0) {
      unawaited(_logStart(game, sessionId, paid: 0));
      return true;
    }

    final ok = await _wallet.deductCoins(
      game.entryPriceCoins,
      source: 'games_hub_session',
      referenceId: sessionId,
      note: '${game.slug} ${game.sessionDurationMinutes}min',
    );

    if (ok) {
      unawaited(_logStart(game, sessionId, paid: game.entryPriceCoins));
    } else {
      debugPrint('[GAMES_HUB] startSession: deductCoins refused for ${game.id}');
    }
    return ok;
  }

  Future<void> endSession({
    required GameModel game,
    required String sessionId,
    required String reason, // 'expired' | 'user_exit' | 'error'
  }) async {
    try {
      await GameAuditService.instance.logGameEnd(
        gameId: sessionId,
        gameType: 'games_hub',
        won: false,
        extra: {'game_id': game.id, 'reason': reason},
      );
    } catch (_) { /* best-effort */ }
  }

  Future<void> _logStart(GameModel g, String sessionId, {required int paid}) async {
    try {
      await GameAuditService.instance.logGameStart(
        gameId: sessionId,
        gameType: 'games_hub',
        payload: {
          'game_id': g.id,
          'slug': g.slug,
          'paid': paid,
          'duration_min': g.sessionDurationMinutes,
        },
      );
      if (paid > 0) {
        await GameAuditService.instance.logBetPlaced(
          gameId: sessionId,
          gameType: 'games_hub',
          amount: paid,
        );
      }
    } catch (_) { /* best-effort */ }
  }
}

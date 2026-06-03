// ============================================================
// SlotsService — Logique de spin (Phase 1 Demo, Phase 2 Real)
// ============================================================
// Phase 1 : tout en local, Random.secure(), pas de Supabase. Le
// solde demo est un compteur en memoire (recharge gratuite illimitee).
//
// Phase 2 : remplacer spin() par un appel RPC :
//   final r = await _client.rpc('slots_spin', params: {
//     'p_bet': bet,
//     'p_request_id': reqId, // stable a travers les retries
//   });
//   -> r contient reels, multiplier, payout, new_balance
// La paytable serveur (SQL) doit etre IDENTIQUE a slot_models.dart.
// ============================================================

import 'dart:math';
import '../models/slot_models.dart';
import '../../../utils/logger.dart';

class SlotsService {
  SlotsService._();
  static final SlotsService instance = SlotsService._();

  static const _log = Logger('SLOTS');

  final Random _rng = Random.secure();

  // Phase 1 Demo : solde en memoire. Recharge libre (bouton refill).
  int _demoBalance = 10000;
  int get demoBalance => _demoBalance;

  /// Historique des derniers spins (capped a 50 pour la RAM).
  final List<SpinResult> _history = [];
  List<SpinResult> get history => List.unmodifiable(_history);

  /// Refill du solde demo (debug / replay).
  void refillDemo([int amount = 10000]) {
    _demoBalance = amount;
  }

  /// Execute un spin. Throws si bet invalide ou solde insuffisant.
  /// Phase 2 : remplacer le corps par un appel RPC `slots_spin`.
  Future<SpinResult> spin({required int bet}) async {
    if (!kBetLevels.contains(bet)) {
      throw ArgumentError('BET_NOT_ALLOWED');
    }
    if (_demoBalance < bet) {
      throw StateError('INSUFFICIENT_BALANCE');
    }

    // Debit immediat.
    _demoBalance -= bet;

    // RNG : 3 tirages independants (1 par rouleau).
    final reels = <SlotSymbol>[
      pickSymbol(_rng),
      pickSymbol(_rng),
      pickSymbol(_rng),
    ];

    final multiplier = evaluateLine(reels);
    final payout = bet * multiplier;

    // Credit si gain.
    if (payout > 0) {
      _demoBalance += payout;
    }

    String? label;
    if (Paytable.isJackpot(multiplier)) {
      label = 'JACKPOT';
    } else if (Paytable.isBigWin(multiplier)) {
      label = 'BIG WIN';
    } else if (multiplier > 0) {
      label = 'WIN';
    }

    final result = SpinResult(
      reels: reels,
      bet: bet,
      multiplier: multiplier,
      payout: payout,
      newBalance: _demoBalance,
      winLabel: label,
    );

    _log.info('spin bet=$bet reels=$reels mult=$multiplier payout=$payout '
        'newBal=$_demoBalance');

    _history.insert(0, result);
    if (_history.length > 50) _history.removeLast();

    return result;
  }
}

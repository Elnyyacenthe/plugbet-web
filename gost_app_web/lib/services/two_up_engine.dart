// ============================================================
// 2Up — Moteur de decision (logique pure, testable)
// ============================================================
// Reference executable de la logique 2Up, MIROIR des RPC SQL de production
// (two_up_should_trigger / _finalize_bet_2up / settle_2up_for_match dans
// zz_20260716_2up_engine.sql). Aucune I/O : entierement testable hors ligne.
//
// Regles 2Up :
//  - S'applique aux paris PRE-MATCH marche "Resultat final" 1X2, selection
//    'home' ou 'away' UNIQUEMENT (le nul 'draw' n'est jamais eligible).
//  - Declenche des que l'equipe pariee atteint le seuil d'avance (par sport).
//  - Cote jamais reduite. Declenchement anticipe, pas condition supplementaire
//    (si l'equipe gagne sans jamais atteindre le seuil -> gagnant en normal).
//  - Idempotent : un meme depassement ne regle qu'une fois par selection.
//  - Combine : la selection 2Up est verrouillee gagnante, mais les autres
//    doivent gagner normalement pour que le ticket entier soit paye.
// ============================================================

/// Statut d'une selection (miroir de bet_selections.selection_status + won).
enum SelStatus { pending, won, lost, voided }

/// Verdict d'un ticket (miroir de la decision finale d'un pari).
enum BetOutcome { pending, won, lost, refund }

/// Seuil de declenchement d'un sport (miroir de sport_2up_config).
class TwoUpThreshold {
  final int lead; // 2 buts / 20 pts / 2 sets / 17 pts / 5 runs
  final bool enabled;
  final bool scoresSupported;
  const TwoUpThreshold({
    required this.lead,
    this.enabled = true,
    this.scoresSupported = true,
  });
}

class TwoUpEngine {
  const TwoUpEngine._();

  /// Avance de l'equipe pariee (cote 'home' ou 'away'). Negatif = en retard.
  /// Renvoie null si le marche n'est pas 2Up-eligible (draw ou autre).
  static int? leadForSide(String marketCode, int homeScore, int awayScore) {
    switch (marketCode) {
      case 'home':
        return homeScore - awayScore;
      case 'away':
        return awayScore - homeScore;
      default:
        return null; // 'draw' et tout autre marche : jamais eligible
    }
  }

  /// Le 2Up doit-il se declencher ? (seuil atteint, marche eligible, actif).
  static bool shouldTrigger({
    required String marketCode,
    required int homeScore,
    required int awayScore,
    required TwoUpThreshold threshold,
    bool globalEnabled = true,
  }) {
    if (!globalEnabled || !threshold.enabled) return false;
    final lead = leadForSide(marketCode, homeScore, awayScore);
    if (lead == null) return false;
    return lead >= threshold.lead;
  }

  /// Eligibilite au placement (fige un snapshot). Miroir du calcul dans
  /// place_bet : pre-match, marche home/away, sport actif & scores couverts,
  /// mise sous le plafond eligible.
  static bool isEligibleAtPlacement({
    required String marketCode,
    required bool isLive,
    required bool isVirtual,
    required TwoUpThreshold? threshold,
    required int stake,
    required int maxStakeEligible,
    bool globalEnabled = true,
  }) {
    if (!globalEnabled) return false;
    if (isLive || isVirtual) return false; // pre-match reel uniquement
    if (marketCode != 'home' && marketCode != 'away') return false;
    if (threshold == null || !threshold.enabled || !threshold.scoresSupported) {
      return false;
    }
    if (stake > maxStakeEligible) return false;
    return true;
  }

  /// Applique un declenchement 2Up a UNE selection (idempotent).
  /// Renvoie le nouveau statut + si l'action a reellement eu lieu.
  /// Ne fait rien si la selection n'est plus 'pending' (doublon d'evenement).
  static ({SelStatus status, bool didSettle}) applyTrigger(
    SelStatus current,
    bool triggered,
  ) {
    if (current != SelStatus.pending) {
      return (status: current, didSettle: false); // deja resolue -> idempotent
    }
    if (!triggered) {
      return (status: SelStatus.pending, didSettle: false);
    }
    return (status: SelStatus.won, didSettle: true);
  }

  /// Verdict d'un ticket a partir des statuts de ses selections.
  /// Miroir EXACT de la decision de settle_real_bets_with_results :
  ///  - une perdante -> ticket perdu
  ///  - une encore pending -> ticket en attente (combine)
  ///  - une void (aucune perte) -> remboursement
  ///  - sinon toutes gagnantes -> gagne
  /// Une selection gagnee via 2Up compte comme 'won' (verrouillee), meme si
  /// le match est ensuite annule/renverse.
  static BetOutcome resolveTicket(List<SelStatus> selections) {
    if (selections.isEmpty) return BetOutcome.pending;
    if (selections.contains(SelStatus.lost)) return BetOutcome.lost;
    if (selections.contains(SelStatus.pending)) return BetOutcome.pending;
    if (selections.contains(SelStatus.voided)) return BetOutcome.refund;
    return BetOutcome.won;
  }
}

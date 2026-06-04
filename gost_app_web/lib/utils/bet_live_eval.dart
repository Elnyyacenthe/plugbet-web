// ============================================================
// bet_live_eval — Evaluation live d'une selection vs match en cours
// ============================================================
// Pour un pari encore 'pending' dont le match est LIVE, on compare la
// selection (market_code) au score actuel pour savoir si l'utilisateur
// est, a cet instant T, en train de GAGNER ou PERDRE le ticket.
//
// Pas de prediction : c'est un snapshot du present, qui peut basculer
// a chaque action du match (but, faute, etc.). Le ticket reste 'pending'
// tant que le match n'est pas termine et settle cote serveur.
//
// Granularite :
//   - winning  : selection passerait si le match s'arretait maintenant
//   - losing   : selection echouerait
//   - locked   : resultat acquis quel que soit la suite (ex: total >= 3
//                pour over2.5, BTTS oui une fois 1-1)
//   - busted   : impossible de gagner desormais (ex: BTTS no apres 1-0
//                est encore possible mais BTTS yes a 0-0 reste possible)
//   - unknown  : market_code non reconnu ou donnees insuffisantes
// ============================================================

import '../services/statpal_service.dart';

enum BetLiveStatus { winning, losing, locked, busted, unknown }

class BetLiveEval {
  /// Evalue une selection (market_code) face au score live du match.
  /// Retourne `unknown` si le match n'est pas live ou si le market n'est
  /// pas supporte.
  static BetLiveStatus evaluate({
    required String marketCode,
    required BettingMatch match,
  }) {
    if (!match.isLive) return BetLiveStatus.unknown;
    final h = match.homeScore;
    final a = match.awayScore;
    if (h == null || a == null) return BetLiveStatus.unknown;
    final total = h + a;
    final code = marketCode.toLowerCase();

    // ── 1X2 ─────────────────────────────────────────────────
    if (code == 'home' || code == '1') {
      return h > a ? BetLiveStatus.winning : BetLiveStatus.losing;
    }
    if (code == 'draw' || code == 'x') {
      return h == a ? BetLiveStatus.winning : BetLiveStatus.losing;
    }
    if (code == 'away' || code == '2') {
      return a > h ? BetLiveStatus.winning : BetLiveStatus.losing;
    }

    // ── Over / Under ────────────────────────────────────────
    // over25 = (h+a) > 2.5 -> verrouille des que >= 3
    if (code == 'over25' || code == 'over_2_5' || code == 'o25') {
      if (total >= 3) return BetLiveStatus.locked;
      return BetLiveStatus.losing;
    }
    if (code == 'under25' || code == 'under_2_5' || code == 'u25') {
      if (total >= 3) return BetLiveStatus.busted;
      return BetLiveStatus.winning;
    }
    if (code == 'over15' || code == 'over_1_5' || code == 'o15') {
      if (total >= 2) return BetLiveStatus.locked;
      return BetLiveStatus.losing;
    }
    if (code == 'under15' || code == 'under_1_5' || code == 'u15') {
      if (total >= 2) return BetLiveStatus.busted;
      return BetLiveStatus.winning;
    }
    if (code == 'over35' || code == 'over_3_5' || code == 'o35') {
      if (total >= 4) return BetLiveStatus.locked;
      return BetLiveStatus.losing;
    }
    if (code == 'under35' || code == 'under_3_5' || code == 'u35') {
      if (total >= 4) return BetLiveStatus.busted;
      return BetLiveStatus.winning;
    }

    // ── BTTS (Both Teams To Score) ──────────────────────────
    if (code == 'btts_yes' || code == 'btts' || code == 'gg') {
      if (h > 0 && a > 0) return BetLiveStatus.locked;
      return BetLiveStatus.losing;
    }
    if (code == 'btts_no' || code == 'ng') {
      if (h > 0 && a > 0) return BetLiveStatus.busted;
      return BetLiveStatus.winning;
    }

    // ── Double chance ───────────────────────────────────────
    if (code == '1x' || code == 'home_draw') {
      return h >= a ? BetLiveStatus.winning : BetLiveStatus.losing;
    }
    if (code == 'x2' || code == 'draw_away') {
      return a >= h ? BetLiveStatus.winning : BetLiveStatus.losing;
    }
    if (code == '12' || code == 'home_away') {
      return h != a ? BetLiveStatus.winning : BetLiveStatus.losing;
    }

    return BetLiveStatus.unknown;
  }

  /// Agrege le statut d'un combine (toutes les selections doivent passer).
  /// Si UNE SEULE est `busted` ou `losing` -> le ticket est en train de
  /// perdre. Si toutes sont `winning`/`locked` -> en train de gagner.
  /// Si certaines sont `unknown` (match pas live), on prend en compte
  /// seulement celles qui sont live et on retourne `partialUnknown` si
  /// au moins une est unknown.
  static CombinedLiveStatus aggregate(List<BetLiveStatus> statuses) {
    if (statuses.isEmpty) {
      return const CombinedLiveStatus(winning: false, hasUnknown: false, isBust: false);
    }
    bool hasUnknown = false;
    bool anyLosing = false;
    bool anyBusted = false;
    int liveCount = 0;
    for (final s in statuses) {
      switch (s) {
        case BetLiveStatus.unknown:
          hasUnknown = true;
          break;
        case BetLiveStatus.losing:
          anyLosing = true;
          liveCount++;
          break;
        case BetLiveStatus.busted:
          anyBusted = true;
          liveCount++;
          break;
        case BetLiveStatus.winning:
        case BetLiveStatus.locked:
          liveCount++;
          break;
      }
    }
    if (liveCount == 0) {
      // Aucune selection live -> rien a dire
      return CombinedLiveStatus(winning: false, hasUnknown: hasUnknown, isBust: false);
    }
    // Si une selection est definitivement perdue ou actuellement losing,
    // le combine est actuellement perdant.
    final winning = !anyLosing && !anyBusted;
    return CombinedLiveStatus(
      winning: winning,
      hasUnknown: hasUnknown,
      isBust: anyBusted,
    );
  }
}

class CombinedLiveStatus {
  /// True si toutes les selections live sont currently winning/locked.
  /// (Les selections non-live ne comptent pas dans ce verdict.)
  final bool winning;
  /// True si au moins une selection a un statut inconnu (match pas live
  /// ou market non supporte).
  final bool hasUnknown;
  /// True si au moins une selection a un statut `busted` (deja
  /// definitivement perdue).
  final bool isBust;

  const CombinedLiveStatus({
    required this.winning,
    required this.hasUnknown,
    required this.isBust,
  });
}

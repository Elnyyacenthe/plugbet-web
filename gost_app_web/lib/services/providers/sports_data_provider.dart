// ============================================================
// Interface d'abstraction fournisseur de donnees sportives
// ============================================================
// Permet de brancher/debrancher un fournisseur (The Odds API, StatPal, ...)
// sans toucher l'UI de paris. La bascule de fournisseur passe par
// SportsData (facade) qui expose le provider actif.
//
// L'UI (betting_screen, bet_slip_odds_refresher, historique) consomme
// UNIQUEMENT cette interface via SportsData.active.
// ============================================================

import '../statpal_service.dart' show Sport, BettingMatch;

abstract class SportsDataProvider {
  /// Nom court (log / diagnostic).
  String get name;

  /// Matchs a venir + en cours AVEC cotes 1X2/totals/spreads deja peuplees.
  Future<List<BettingMatch>> getUpcomingMatches({required Sport sport});

  /// Matchs en cours avec score live (isLive=true, homeScore/awayScore).
  Future<List<BettingMatch>> getLiveMatches({required Sport sport});

  /// Le fournisseur couvre-t-il les scores live de ce sport (=> 2Up possible) ?
  bool supports2Up(Sport sport);
}

// ============================================================
// SportsData — facade fournisseur actif
// ============================================================
// Point d'entree unique de l'UI de paris. Par defaut : The Odds API
// (remplacement de StatPal). La couche d'abstraction permet de rebrancher
// StatPal (StatpalSportsProvider) sans toucher l'UI, si besoin futur.
// ============================================================

import '../statpal_service.dart' show Sport, BettingMatch, StatpalService;
import 'sports_data_provider.dart';
import 'the_odds_api_provider.dart';

class SportsData {
  SportsData._();

  static SportsDataProvider _active = TheOddsApiProvider();

  /// Fournisseur actif consomme par l'UI.
  static SportsDataProvider get active => _active;

  /// Bascule de fournisseur (tests / futur switch runtime).
  static void use(SportsDataProvider provider) => _active = provider;
}

/// Adaptateur StatPal derriere l'interface (fallback / reversibilite).
/// Note : StatPal fournit les matchs sans cotes inline (cotes via un appel
/// separe), donc cet adaptateur n'est pas un drop-in complet — il existe
/// pour garder StatPal branchable, pas comme source active par defaut.
class StatpalSportsProvider implements SportsDataProvider {
  @override
  String get name => 'statpal';

  @override
  Future<List<BettingMatch>> getUpcomingMatches({required Sport sport}) =>
      StatpalService.instance.getTodayMatches(sport: sport);

  @override
  Future<List<BettingMatch>> getLiveMatches({required Sport sport}) =>
      StatpalService.instance.getLiveMatches(sport: sport);

  @override
  bool supports2Up(Sport sport) => false;
}

// ============================================================
// StatpalService — Wrapper API StatPal.io V2 (Phase 1 : MOCK)
// ============================================================
// Phase 1 : aucun compte StatPal -> on retourne des donnees mockees
// pour valider l'UI/UX de l'onglet Paris.
//
// Phase 2 (quand l'abonnement StatPal payant est actif) :
//   1. Mettre _apiKey via Supabase app_settings (key='statpal_config')
//   2. Decommenter les blocs _real* dans chaque methode
//   3. Le reste de l'app (BettingScreen, BettingMatchCard) ne change pas
//
// Endpoints cibles (V2) :
//   GET /soccer/matches/live              -> matchs en direct
//   GET /soccer/matches/today             -> matchs du jour
//   GET /soccer/odds/pre-match?match_id=  -> cotes pre-match
//   GET /soccer/odds/live?match_id=       -> cotes inplay
//
// Polling : 10s pour live (cf BettingScreen). Pas de polling sur
// today (un fetch + pull-to-refresh suffit).
// ============================================================

import 'dart:async';
import '../utils/logger.dart';

// ── Modeles ───────────────────────────────────────────────

class BettingMatch {
  final String id;
  final String homeName;
  final String awayName;
  final String? homeLogo;
  final String? awayLogo;
  final String league;
  final DateTime startTime;
  final bool isLive;
  final int? minute;
  final int? homeScore;
  final int? awayScore;
  final MatchOdds? odds;

  const BettingMatch({
    required this.id,
    required this.homeName,
    required this.awayName,
    this.homeLogo,
    this.awayLogo,
    required this.league,
    required this.startTime,
    required this.isLive,
    this.minute,
    this.homeScore,
    this.awayScore,
    this.odds,
  });

  BettingMatch copyWith({MatchOdds? odds, int? minute, int? homeScore, int? awayScore}) =>
      BettingMatch(
        id: id, homeName: homeName, awayName: awayName,
        homeLogo: homeLogo, awayLogo: awayLogo, league: league,
        startTime: startTime, isLive: isLive,
        minute: minute ?? this.minute,
        homeScore: homeScore ?? this.homeScore,
        awayScore: awayScore ?? this.awayScore,
        odds: odds ?? this.odds,
      );
}

class MatchOdds {
  // 1X2
  final double? home;
  final double? draw;
  final double? away;
  // Over/Under 2.5
  final double? over25;
  final double? under25;
  // Both Teams To Score
  final double? bttsYes;
  final double? bttsNo;

  const MatchOdds({
    this.home, this.draw, this.away,
    this.over25, this.under25,
    this.bttsYes, this.bttsNo,
  });
}

// ── Service ───────────────────────────────────────────────

class StatpalService {
  StatpalService._();
  static final StatpalService instance = StatpalService._();

  static const _log = Logger('STATPAL');

  // Phase 2 : remplir via app_settings Supabase
  // ignore: unused_field
  static const String _baseUrl = 'https://statpal.io/api/v1';
  // ignore: unused_field
  static const String _apiKey = ''; // <- a injecter Phase 2

  /// Matchs en direct. Phase 1 : mock. Phase 2 : GET /soccer/matches/live.
  Future<List<BettingMatch>> getLiveMatches() async {
    _log.info('getLiveMatches (mock)');
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockLive;
  }

  /// Matchs du jour (a venir). Phase 1 : mock. Phase 2 : GET /soccer/matches/today.
  Future<List<BettingMatch>> getTodayMatches() async {
    _log.info('getTodayMatches (mock)');
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockToday;
  }

  /// Cotes d'un match. Phase 1 : retourne les odds du mock. Phase 2 :
  /// GET /soccer/odds/{live|pre-match}?match_id=...
  Future<MatchOdds?> getMatchOdds(String matchId, {required bool isLive}) async {
    _log.info('getMatchOdds $matchId live=$isLive (mock)');
    final all = [..._mockLive, ..._mockToday];
    final found = all.where((m) => m.id == matchId).toList();
    return found.isEmpty ? null : found.first.odds;
  }

  /// Place un pari. Phase 1 : stub -> retourne false (rien debite).
  /// Phase 2 : RPC place_bet idempotente (debit wallet + insert bets).
  Future<bool> placeBet({
    required String matchId,
    required String market,   // '1X2_home', 'OU25_over', 'BTTS_yes', ...
    required double odds,
    required int stake,       // FCFA
  }) async {
    _log.info('placeBet stub : $matchId $market @$odds stake=$stake');
    return false; // toujours stub Phase 1
  }
}

// ── Donnees mock pour Phase 1 (ne pas committer en prod final) ────

final List<BettingMatch> _mockLive = [
  BettingMatch(
    id: 'mock_live_1',
    homeName: 'Cameroun', awayName: 'Senegal',
    homeLogo: null, awayLogo: null,
    league: 'Coupe du Monde 2026',
    startTime: DateTime.now().subtract(const Duration(minutes: 38)),
    isLive: true, minute: 38,
    homeScore: 1, awayScore: 0,
    odds: const MatchOdds(
      home: 2.10, draw: 3.30, away: 3.50,
      over25: 1.85, under25: 1.95,
      bttsYes: 1.70, bttsNo: 2.05,
    ),
  ),
  BettingMatch(
    id: 'mock_live_2',
    homeName: 'France', awayName: 'Bresil',
    homeLogo: null, awayLogo: null,
    league: 'Match amical',
    startTime: DateTime.now().subtract(const Duration(minutes: 67)),
    isLive: true, minute: 67,
    homeScore: 2, awayScore: 2,
    odds: const MatchOdds(
      home: 2.40, draw: 3.10, away: 2.90,
      over25: 1.50, under25: 2.50,
      bttsYes: 1.25, bttsNo: 3.40,
    ),
  ),
];

final List<BettingMatch> _mockToday = [
  BettingMatch(
    id: 'mock_today_1',
    homeName: 'Maroc', awayName: 'Algerie',
    homeLogo: null, awayLogo: null,
    league: 'Coupe du Monde 2026',
    startTime: DateTime.now().add(const Duration(hours: 2)),
    isLive: false,
    odds: const MatchOdds(
      home: 1.95, draw: 3.20, away: 4.10,
      over25: 2.00, under25: 1.80,
      bttsYes: 1.85, bttsNo: 1.90,
    ),
  ),
  BettingMatch(
    id: 'mock_today_2',
    homeName: 'Argentine', awayName: 'Allemagne',
    homeLogo: null, awayLogo: null,
    league: 'Match amical',
    startTime: DateTime.now().add(const Duration(hours: 4, minutes: 30)),
    isLive: false,
    odds: const MatchOdds(
      home: 2.20, draw: 3.10, away: 3.20,
      over25: 1.75, under25: 2.05,
      bttsYes: 1.60, bttsNo: 2.25,
    ),
  ),
  BettingMatch(
    id: 'mock_today_3',
    homeName: 'Portugal', awayName: 'Espagne',
    homeLogo: null, awayLogo: null,
    league: 'Match amical',
    startTime: DateTime.now().add(const Duration(hours: 6)),
    isLive: false,
    odds: const MatchOdds(
      home: 2.50, draw: 3.00, away: 2.80,
      over25: 1.65, under25: 2.20,
      bttsYes: 1.45, bttsNo: 2.70,
    ),
  ),
];

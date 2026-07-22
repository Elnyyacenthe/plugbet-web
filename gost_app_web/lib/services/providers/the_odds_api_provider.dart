// ============================================================
// SportsDataProvider — implementation The Odds API
// ============================================================
// Appelle l'Edge Function `odds_api_proxy` (qui injecte la clef serveur
// THE_ODDS_API_KEY, cache court + backoff + log quota). Mappe les reponses
// vers BettingMatch/MatchOdds via the_odds_api_mapper (fonctions pures).
//
// Couverture : soccer + basketball + NFL + MLB + tennis pour l'UI de paris. Liste de ligues
// CURÉE (pas tous les sport_keys) pour borner la conso quota — modifiable
// sans redeploiement lourd. Les scores tennis ne sont pas fournis par
// The Odds API (=> 2Up tennis desactive, coherent avec sport_2up_config).
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/logger.dart';
import '../statpal_service.dart' show Sport, BettingMatch;
import '../the_odds_api_mapper.dart';
import 'sports_data_provider.dart';

class TheOddsApiProvider implements SportsDataProvider {
  TheOddsApiProvider();

  static const _log = Logger('ODDSAPI');
  static const _markets = 'h2h,totals,spreads';
  static const _regions = 'eu';
  static const _oddsFormat = 'decimal';

  // Cache memoire court cote client (le proxy a deja son cache serveur).
  static const _upcomingTtl = Duration(seconds: 25);
  static const _liveTtl = Duration(seconds: 15);
  final Map<Sport, List<BettingMatch>> _upcomingCache = {};
  final Map<Sport, DateTime> _upcomingAt = {};
  final Map<Sport, List<BettingMatch>> _liveCache = {};
  final Map<Sport, DateTime> _liveAt = {};

  // ── Decouverte dynamique des ligues (auto-saison) ──────────
  // On interroge /v4/sports (gratuit, 0 credit) pour ne garder que les
  // competitions ACTIVES du moment (les hors-saison disparaissent d'elles-
  // memes). Classees par priorite editoriale, puis plafonnees pour borner
  // la conso quota (chaque ligue = 1 appel /odds + 1 appel /scores / cycle).
  static const _sportsTtl = Duration(hours: 6);

  /// Nombre max de ligues interrogees par sport (garde-fou quota).
  static const int maxLeaguesPerSport = 20;

  /// Priorite editoriale : ces ligues passent en tete si actives. On en liste
  /// large (evenements grand public) — seules les ACTIVES du moment sont
  /// gardees, puis plafonnees a maxLeaguesPerSport. Les cles inexistantes/
  /// hors-saison sont simplement ignorees.
  static const List<String> priorityOrder = [
    // ── Football (soccer) ──
    'soccer_fifa_world_cup',
    'soccer_fifa_world_cup_qualifiers_europe',
    'soccer_uefa_champs_league',
    'soccer_uefa_europa_league',
    'soccer_uefa_europa_conference_league',
    'soccer_uefa_nations_league',
    'soccer_uefa_european_championship',
    'soccer_epl',
    'soccer_spain_la_liga',
    'soccer_italy_serie_a',
    'soccer_germany_bundesliga',
    'soccer_france_ligue_one',
    'soccer_england_efl_champ',
    'soccer_netherlands_eredivisie',
    'soccer_portugal_primeira_liga',
    'soccer_turkey_super_league',
    'soccer_belgium_first_div',
    'soccer_scotland_premiership',
    'soccer_greece_super_league',
    'soccer_usa_mls',
    'soccer_mexico_ligamx',
    'soccer_brazil_campeonato',
    'soccer_argentina_primera_division',
    'soccer_conmebol_copa_libertadores',
    'soccer_conmebol_copa_sudamericana',
    'soccer_africa_cup_of_nations',
    'soccer_spain_segunda_division',
    'soccer_italy_serie_b',
    'soccer_germany_bundesliga2',
    'soccer_france_ligue_two',
    'soccer_england_league1',
    'soccer_england_league2',
    'soccer_fa_cup',
    'soccer_spain_copa_del_rey',
    'soccer_italy_coppa_italia',
    'soccer_germany_dfb_pokal',
    'soccer_efl_cup',
    'soccer_switzerland_superleague',
    'soccer_austria_bundesliga',
    'soccer_denmark_superliga',
    'soccer_norway_eliteserien',
    'soccer_sweden_allsvenskan',
    'soccer_poland_ekstraklasa',
    'soccer_russia_premier_league',
    'soccer_japan_j_league',
    'soccer_australia_aleague',
    'soccer_china_superleague',
    // ── Basketball ──
    'basketball_nba',
    'basketball_euroleague',
    'basketball_ncaab',
    'basketball_wnba',
    'basketball_nbl',
    // ── Football americain ──
    'americanfootball_nfl',
    'americanfootball_ncaaf',
    // ── Baseball ──
    'baseball_mlb',
    'baseball_ncaa',
    'baseball_mlb_preseason',
    // ── Hockey sur glace ──
    'icehockey_nhl',
    'icehockey_sweden_hockey_league',
    'icehockey_finland_liiga',
    'icehockey_ahl',
    'icehockey_sweden_allsvenskan',
    // ── Rugby (League + Union) ──
    'rugbyleague_nrl',
    'rugbyunion_six_nations',
    'rugbyleague_super_league',
    // ── Handball ──
    'handball_germany_bundesliga',
    // ── Tennis ──
    'tennis_atp_australian_open',
    'tennis_wta_australian_open',
    'tennis_atp_french_open',
    'tennis_wta_french_open',
    'tennis_atp_wimbledon',
    'tennis_wta_wimbledon',
    'tennis_atp_us_open',
    'tennis_wta_us_open',
  ];

  /// Repli si /v4/sports echoue (hors-ligne / erreur API).
  static const Map<Sport, List<String>> fallbackKeys = {
    Sport.soccer: [
      'soccer_uefa_champs_league',
      'soccer_uefa_europa_league',
      'soccer_epl',
      'soccer_spain_la_liga',
      'soccer_italy_serie_a',
      'soccer_germany_bundesliga',
      'soccer_france_ligue_one',
      'soccer_netherlands_eredivisie',
      'soccer_portugal_primeira_liga',
      'soccer_usa_mls',
      'soccer_conmebol_copa_libertadores',
      'soccer_brazil_campeonato',
    ],
    Sport.basketball: [
      'basketball_nba',
      'basketball_euroleague',
      'basketball_ncaab',
      'basketball_wnba',
    ],
    Sport.americanFootball: [
      'americanfootball_nfl',
      'americanfootball_ncaaf',
    ],
    Sport.baseball: [
      'baseball_mlb',
      'baseball_ncaa',
    ],
    Sport.tennis: [
      'tennis_atp_australian_open',
      'tennis_wta_australian_open',
      'tennis_atp_french_open',
      'tennis_wta_french_open',
      'tennis_atp_wimbledon',
      'tennis_wta_wimbledon',
      'tennis_atp_us_open',
      'tennis_wta_us_open',
    ],
    Sport.iceHockey: [
      'icehockey_nhl',
      'icehockey_sweden_hockey_league',
      'icehockey_finland_liiga',
      'icehockey_ahl',
    ],
    Sport.rugby: [
      'rugbyleague_nrl',
      'rugbyunion_six_nations',
    ],
    Sport.handball: [
      'handball_germany_bundesliga',
    ],
  };

  // Cache des ligues actives decouvertes (par sport) + horodatage.
  Map<Sport, List<String>>? _discovered;
  DateTime? _discoveredAt;
  Future<void>? _discovering;

  @override
  String get name => 'the_odds_api';

  @override
  bool supports2Up(Sport sport) =>
      sport == Sport.soccer ||
      sport == Sport.basketball ||
      sport == Sport.americanFootball ||
      sport == Sport.baseball;

  @override
  Future<List<BettingMatch>> getUpcomingMatches({required Sport sport}) async {
    final at = _upcomingAt[sport];
    if (at != null && DateTime.now().difference(at) < _upcomingTtl) {
      return _upcomingCache[sport] ?? const [];
    }
    final keys = (await _sportKeys())[sport] ?? const <String>[];
    final all = <String, BettingMatch>{};
    await Future.wait(keys.map((k) async {
      final json = await _get('/v4/sports/$k/odds', {
        'regions': _regions,
        'markets': _markets,
        'oddsFormat': _oddsFormat,
      });
      for (final m in mapOddsEvents(json)) {
        all[m.id] = m; // dedup par id interne
      }
    }));
    final list = all.values.toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    _upcomingCache[sport] = list;
    _upcomingAt[sport] = DateTime.now();
    return list;
  }

  @override
  Future<List<BettingMatch>> getLiveMatches({required Sport sport}) async {
    final at = _liveAt[sport];
    if (at != null && DateTime.now().difference(at) < _liveTtl) {
      return _liveCache[sport] ?? const [];
    }
    final keys = (await _sportKeys())[sport] ?? const <String>[];
    final all = <String, BettingMatch>{};
    await Future.wait(keys.map((k) async {
      final json = await _get('/v4/sports/$k/scores', {'daysFrom': '1'});
      for (final m in mapScoreEvents(json, liveOnly: true)) {
        all[m.id] = m;
      }
    }));
    final list = all.values.toList();
    _liveCache[sport] = list;
    _liveAt[sport] = DateTime.now();
    return list;
  }

  /// Renvoie les sport_keys actifs par sport (decouverte /v4/sports, cache
  /// 6h). Ne leve jamais : repli sur fallbackKeys en cas d'echec.
  Future<Map<Sport, List<String>>> _sportKeys() async {
    final at = _discoveredAt;
    if (_discovered != null &&
        at != null &&
        DateTime.now().difference(at) < _sportsTtl) {
      return _discovered!;
    }
    final fut = _discovering ??= _discover();
    try {
      await fut;
    } catch (_) {/* _discover ne leve pas, ceinture+bretelles */}
    if (identical(_discovering, fut)) _discovering = null;
    return _discovered ?? fallbackKeys;
  }

  /// Appelle /v4/sports (gratuit) et retient les competitions ACTIVES,
  /// classees par priorite editoriale puis plafonnees (garde-fou quota).
  /// Exclut les marches "vainqueur" (has_outrights) qui n'ont pas de 1X2.
  Future<void> _discover() async {
    final json = await _get('/v4/sports', const {});
    if (json is! List || json.isEmpty) {
      _log.warn('discover /v4/sports vide -> fallback conserve');
      return; // garde l'ancien cache ou fallbackKeys
    }
    final soccer = <String>[];
    final basket = <String>[];
    final footballUs = <String>[];
    final baseball = <String>[];
    final tennis = <String>[];
    final iceHockey = <String>[];
    final rugby = <String>[];
    final handball = <String>[];
    for (final s in json) {
      if (s is! Map) continue;
      if (s['active'] != true) continue;
      if (s['has_outrights'] == true) continue;
      final key = s['key']?.toString() ?? '';
      if (key.startsWith('soccer')) {
        soccer.add(key);
      } else if (key.startsWith('basketball')) {
        basket.add(key);
      } else if (key.startsWith('americanfootball')) {
        footballUs.add(key);
      } else if (key.startsWith('baseball')) {
        baseball.add(key);
      } else if (key.startsWith('tennis')) {
        tennis.add(key);
      } else if (key.startsWith('icehockey')) {
        iceHockey.add(key);
      } else if (key.startsWith('rugbyleague') ||
          key.startsWith('rugbyunion')) {
        rugby.add(key);
      } else if (key.startsWith('handball')) {
        handball.add(key);
      }
    }
    _discovered = {
      Sport.soccer: _rankAndCap(soccer),
      Sport.basketball: _rankAndCap(basket),
      Sport.americanFootball: _rankAndCap(footballUs),
      Sport.baseball: _rankAndCap(baseball),
      Sport.tennis: _rankAndCap(tennis),
      Sport.iceHockey: _rankAndCap(iceHockey),
      Sport.rugby: _rankAndCap(rugby),
      Sport.handball: _rankAndCap(handball),
    };
    _discoveredAt = DateTime.now();
    _log.info('discover: soccer=${_discovered![Sport.soccer]!.length} '
        'basket=${_discovered![Sport.basketball]!.length} '
        'nfl=${_discovered![Sport.americanFootball]!.length} '
        'mlb=${_discovered![Sport.baseball]!.length} '
        'tennis=${_discovered![Sport.tennis]!.length} '
        'hockey=${_discovered![Sport.iceHockey]!.length} '
        'rugby=${_discovered![Sport.rugby]!.length} '
        'handball=${_discovered![Sport.handball]!.length} ligues actives');
  }

  /// Classe les cles decouvertes : prioritaires d'abord (ordre editorial),
  /// le reste ensuite (ordre API), puis coupe a maxLeaguesPerSport.
  List<String> _rankAndCap(List<String> keys) {
    final set = keys.toSet();
    final ordered = <String>[];
    for (final p in priorityOrder) {
      if (set.remove(p)) ordered.add(p);
    }
    ordered.addAll(set); // les autres competitions actives, apres les majeures
    return ordered.take(maxLeaguesPerSport).toList();
  }

  /// Appel proxy -> renvoie la liste JSON decodee (ou null en cas d'erreur).
  Future<dynamic> _get(String path, Map<String, String> query) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'odds_api_proxy',
        body: {'path': path, 'query': query},
      );
      if (res.status != 200) {
        _log.warn('odds_api_proxy $path -> ${res.status}');
        return null;
      }
      final data = res.data;
      if (data is List) return data;
      if (data is String) {
        final decoded = jsonDecode(data);
        return decoded;
      }
      return data;
    } catch (e) {
      _log.warn('_get($path) error: $e');
      return null;
    }
  }
}

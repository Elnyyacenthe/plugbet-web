// ============================================================
// StatpalService — Wrapper API StatPal.io V2 (Phase 2 : LIVE)
// ============================================================
// Phase 2 active : appels réels via edge function `statpal_proxy`
// (clé d'accès cachée côté serveur). Fallback automatique sur les
// mocks en cas d'erreur réseau / parsing -> jamais d'UI cassée.
//
// Endpoints utilisés (V2) :
//   GET /soccer/matches/live                       -> matchs en direct
//   GET /soccer/matches/daily?offset=0             -> matchs du jour
//   GET /soccer/leagues/{league-id}/odds/prematch  -> cotes pre-match
//   GET /soccer/odds/live                          -> cotes inplay (tous)
//
// Polling : 10s pour live (cf BettingScreen). Pas de polling sur
// today (un fetch + pull-to-refresh suffit).
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';
import 'statpal_disk_cache.dart';

// ── Modeles ───────────────────────────────────────────────

/// Sports supportes par l'abonnement StatPal ("Soccer and NBA - Data API").
enum Sport { soccer, basketball }

String _sportPath(Sport s) {
  switch (s) {
    case Sport.soccer:     return 'soccer';
    // StatPal expose le basket via /nba/* (V1), pas /basketball/* (n'existe pas).
    case Sport.basketball: return 'nba';
  }
}

class BettingMatch {
  final String id;
  final Sport sport;
  final String? leagueId;     // requis pour /{sport}/leagues/{id}/odds/prematch
  final String homeName;
  final String awayName;
  final String? homeTeamId;   // StatPal team id (pour fiche equipe)
  final String? awayTeamId;
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
    this.sport = Sport.soccer,
    this.leagueId,
    required this.homeName,
    required this.awayName,
    this.homeTeamId,
    this.awayTeamId,
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

  /// Serialisation JSON pour cache disque (StatpalDiskCache).
  /// Format compact - cles a 1-2 lettres pour reduire la taille SharedPreferences.
  Map<String, dynamic> toJson() => {
    'i': id,
    's': sport.index,
    'l': leagueId,
    'hn': homeName,
    'an': awayName,
    'ht': homeTeamId,
    'at': awayTeamId,
    'hl': homeLogo,
    'al': awayLogo,
    'lg': league,
    't': startTime.toUtc().millisecondsSinceEpoch,
    'iv': isLive,
    'mn': minute,
    'hs': homeScore,
    'as': awayScore,
    if (odds != null) 'o': odds!.toJson(),
  };

  factory BettingMatch.fromJson(Map<String, dynamic> j) => BettingMatch(
    id: j['i'] as String,
    sport: Sport.values[(j['s'] as int?) ?? 0],
    leagueId: j['l'] as String?,
    homeName: j['hn'] as String? ?? '',
    awayName: j['an'] as String? ?? '',
    homeTeamId: j['ht'] as String?,
    awayTeamId: j['at'] as String?,
    homeLogo: j['hl'] as String?,
    awayLogo: j['al'] as String?,
    league: j['lg'] as String? ?? '',
    startTime: DateTime.fromMillisecondsSinceEpoch(
        (j['t'] as int?) ?? 0, isUtc: true),
    isLive: j['iv'] as bool? ?? false,
    minute: j['mn'] as int?,
    homeScore: j['hs'] as int?,
    awayScore: j['as'] as int?,
    odds: j['o'] is Map<String, dynamic>
        ? MatchOdds.fromJson(j['o'] as Map<String, dynamic>)
        : null,
  );

  /// true = basket (pas de "match nul" possible -> UI 2 boutons au lieu de 3).
  bool get hasDrawMarket => sport == Sport.soccer;

  BettingMatch copyWith({MatchOdds? odds, int? minute, int? homeScore, int? awayScore}) =>
      BettingMatch(
        id: id, sport: sport, leagueId: leagueId,
        homeName: homeName, awayName: awayName,
        homeTeamId: homeTeamId, awayTeamId: awayTeamId,
        homeLogo: homeLogo, awayLogo: awayLogo, league: league,
        startTime: startTime, isLive: isLive,
        minute: minute ?? this.minute,
        homeScore: homeScore ?? this.homeScore,
        awayScore: awayScore ?? this.awayScore,
        odds: odds ?? this.odds,
      );
}

/// 1 ligne de Handicap Asiatique (ex: -1.5 cote home 2.10 / away 1.72).
/// Soccer + NBA. Quart-handicaps (-0.25, -0.75) exclus pour rester
/// compatible avec le settlement entier/demi.
class AsianHandicapLine {
  final double line;        // -1.5, -0.5, 0, +0.5, +1.5, etc.
  final double homeOdds;
  final double awayOdds;
  final bool isMain;        // ligne principale recommandee par le bookmaker

  const AsianHandicapLine({
    required this.line,
    required this.homeOdds,
    required this.awayOdds,
    this.isMain = false,
  });

  Map<String, dynamic> toJson() => {'l': line, 'h': homeOdds, 'a': awayOdds, 'm': isMain};
  factory AsianHandicapLine.fromJson(Map<String, dynamic> j) => AsianHandicapLine(
    line: (j['l'] as num).toDouble(),
    homeOdds: (j['h'] as num).toDouble(),
    awayOdds: (j['a'] as num).toDouble(),
    isMain: j['m'] as bool? ?? false,
  );
}

/// Une selection d'un marche generique (ex: "1:0" cote 7.50 d'un Correct Score).
class ExtraOdd {
  final String name;        // "1:0", "Home/Away", "Over 1.5", etc.
  final String code;        // code stable pour BetSlip (ex: "cs_1_0")
  final double value;       // la cote decimale
  final double? line;       // pour OU / handicap variants (1.5, -3.5, etc.)
  const ExtraOdd({
    required this.name,
    required this.code,
    required this.value,
    this.line,
  });

  Map<String, dynamic> toJson() => {
    'n': name, 'c': code, 'v': value,
    if (line != null) 'l': line,
  };
  factory ExtraOdd.fromJson(Map<String, dynamic> j) => ExtraOdd(
    name: j['n'] as String,
    code: j['c'] as String,
    value: (j['v'] as num).toDouble(),
    line: (j['l'] as num?)?.toDouble(),
  );
}

/// Un marche generique (non-core). Permet d'absorber les ~70 marches StatPal
/// sans cabler chacun en champ nomme dans MatchOdds.
/// Le widget UI itere sur cette liste pour generer dynamiquement les
/// sections de la fiche match.
class ExtraMarket {
  final String name;          // "Correct Score" (label StatPal brut)
  final String code;          // 'correct_score', 'htft_double', etc. (stable)
  final String displayName;   // "Score exact" (FR humain)
  final String? subtitle;     // sous-titre court
  final List<ExtraOdd> odds;  // 2-25 cotes selon le marche
  final String? bookmaker;
  final ExtraMarketLayout layout; // hint UI (grid / row2 / row3 / chips...)

  const ExtraMarket({
    required this.name,
    required this.code,
    required this.displayName,
    required this.odds,
    this.subtitle,
    this.bookmaker,
    this.layout = ExtraMarketLayout.grid,
  });

  Map<String, dynamic> toJson() => {
    'n': name, 'c': code, 'dn': displayName,
    if (subtitle != null) 'st': subtitle,
    if (bookmaker != null) 'bk': bookmaker,
    'l': layout.index,
    'o': odds.map((e) => e.toJson()).toList(),
  };
  factory ExtraMarket.fromJson(Map<String, dynamic> j) => ExtraMarket(
    name: j['n'] as String? ?? '',
    code: j['c'] as String? ?? '',
    displayName: j['dn'] as String? ?? '',
    subtitle: j['st'] as String?,
    bookmaker: j['bk'] as String?,
    layout: ExtraMarketLayout.values[(j['l'] as int?) ?? 0],
    odds: (j['o'] as List?)
        ?.cast<Map<String, dynamic>>()
        .map(ExtraOdd.fromJson)
        .toList() ?? const [],
  );
}

/// Hint d'affichage UI pour un ExtraMarket.
/// - row2/row3 : ligne unique avec 2/3 tiles equi-largeur (1X2, OU, Yes/No)
/// - grid     : grille multi-lignes (Correct Score, HT/FT 3x3)
/// - chips    : scroll horizontal de tiles (Exact Goals, Race To Points)
enum ExtraMarketLayout { row2, row3, grid, chips }

/// Metadonnees d'un marche connu (code stable, label FR, layout UI).
class _ExtraMeta {
  final String code;
  final String displayName;
  final String? subtitle;
  final ExtraMarketLayout layout;
  const _ExtraMeta(this.code, this.displayName, this.subtitle, this.layout);
}

// ============================================================
// Standings — Classement de ligue (soccer + NBA)
// ============================================================
class TeamStanding {
  final int position;
  final String teamId;
  final String teamName;
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;      // soccer : buts pour | NBA : points pour
  final int goalsAgainst;  // soccer : buts contre | NBA : points contre
  final int points;        // soccer : pts | NBA : games behind ou win% (cf raw)
  final String? form;      // ex: "WWDLL" (derniers matchs)
  const TeamStanding({
    required this.position,
    required this.teamId,
    required this.teamName,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.points,
    this.form,
  });
}

class LeagueStanding {
  final String leagueId;
  final String leagueName;
  final String country;
  final String season;
  final List<TeamStanding> teams;
  const LeagueStanding({
    required this.leagueId,
    required this.leagueName,
    required this.country,
    required this.season,
    required this.teams,
  });
}

// ============================================================
// TeamProfile — Fiche equipe complete (soccer)
// ============================================================
class TeamPlayer {
  final String id;
  final String name;
  final String? position;
  final int? age;
  final String? country;
  final int? number;
  const TeamPlayer({
    required this.id,
    required this.name,
    this.position,
    this.age,
    this.country,
    this.number,
  });
}

class TeamProfile {
  final String id;
  final String name;
  final String country;
  final String? founded;
  final String? coachName;
  final String? venueName;
  final String? venueCity;
  final int? venueCapacity;
  final String? venueSurface;
  final List<TeamPlayer> squad;
  const TeamProfile({
    required this.id,
    required this.name,
    required this.country,
    this.founded,
    this.coachName,
    this.venueName,
    this.venueCity,
    this.venueCapacity,
    this.venueSurface,
    this.squad = const [],
  });
}

class MatchOdds {
  // 1X2 — temps reglementaire (basket : home/away seulement, draw=null)
  final double? home;
  final double? draw;
  final double? away;
  // Total Over/Under (ligne main bookmaker)
  // Soccer : ligne fixe 2.5 buts. Basket : variable (~95-115 points).
  final double? over25;
  final double? under25;
  final double? mainOuLine;   // ex: 2.5 (soccer) ou 107.5 (NBA)
  // Spread / Handicap (NBA principalement)
  // Ex: Spurs -3.5 cote 1.85 / Knicks +3.5 cote 1.95
  final double? spreadHomeOdds;
  final double? spreadAwayOdds;
  final double? spreadHomeLine;   // ex: -3.5 (Spurs favori)
  final double? spreadAwayLine;   // ex: +3.5 (Knicks underdog)
  // Both Teams To Score (soccer only)
  final double? bttsYes;
  final double? bttsNo;
  // 1X2 mi-temps (soccer only)
  final double? htHome;
  final double? htDraw;
  final double? htAway;
  // OU 1.5 mi-temps (soccer only)
  final double? htOver15;
  final double? htUnder15;
  // Asian Handicap (soccer + NBA) — multi-lines.
  // Vide = marche non dispo. Tri : ligne principale d'abord, puis croissant.
  final List<AsianHandicapLine> asianHandicap;
  // Marches additionnels generiques (Correct Score, HT/FT, Odd/Even, etc.)
  // Affichage dynamique via _ExtraMarketSection. Ordre = ordre d'affichage UI.
  final List<ExtraMarket> extraMarkets;
  // Source par section (transparence - peut differer entre marches)
  final String? bookmaker;          // moneyline source (legacy)
  final String? mlBookmaker;        // moneyline
  final String? ouBookmaker;        // total OU
  final String? spreadBookmaker;    // handicap
  final String? ahBookmaker;        // asian handicap

  const MatchOdds({
    this.home, this.draw, this.away,
    this.over25, this.under25, this.mainOuLine,
    this.spreadHomeOdds, this.spreadAwayOdds,
    this.spreadHomeLine, this.spreadAwayLine,
    this.bttsYes, this.bttsNo,
    this.htHome, this.htDraw, this.htAway,
    this.htOver15, this.htUnder15,
    this.asianHandicap = const [],
    this.extraMarkets = const [],
    this.bookmaker,
    this.mlBookmaker, this.ouBookmaker, this.spreadBookmaker,
    this.ahBookmaker,
  });

  /// Ligne AH principale a afficher par defaut (premiere `isMain=true`,
  /// sinon premiere ligne dispo). Null si aucune ligne AH.
  AsianHandicapLine? get mainAh {
    if (asianHandicap.isEmpty) return null;
    for (final l in asianHandicap) {
      if (l.isMain) return l;
    }
    return asianHandicap.first;
  }

  /// Serialisation JSON pour le cache disque.
  Map<String, dynamic> toJson() => {
    if (home != null) 'h': home,
    if (draw != null) 'd': draw,
    if (away != null) 'a': away,
    if (over25 != null) 'ov': over25,
    if (under25 != null) 'un': under25,
    if (mainOuLine != null) 'mol': mainOuLine,
    if (spreadHomeOdds != null) 'sho': spreadHomeOdds,
    if (spreadAwayOdds != null) 'sao': spreadAwayOdds,
    if (spreadHomeLine != null) 'shl': spreadHomeLine,
    if (spreadAwayLine != null) 'sal': spreadAwayLine,
    if (bttsYes != null) 'by': bttsYes,
    if (bttsNo != null) 'bn': bttsNo,
    if (htHome != null) 'hh': htHome,
    if (htDraw != null) 'hd': htDraw,
    if (htAway != null) 'ha': htAway,
    if (htOver15 != null) 'ho': htOver15,
    if (htUnder15 != null) 'hu': htUnder15,
    if (asianHandicap.isNotEmpty)
      'ah': asianHandicap.map((l) => l.toJson()).toList(),
    if (extraMarkets.isNotEmpty)
      'em': extraMarkets.map((m) => m.toJson()).toList(),
    if (bookmaker != null) 'bk': bookmaker,
    if (mlBookmaker != null) 'mb': mlBookmaker,
    if (ouBookmaker != null) 'ob': ouBookmaker,
    if (spreadBookmaker != null) 'sb': spreadBookmaker,
    if (ahBookmaker != null) 'ab': ahBookmaker,
  };

  factory MatchOdds.fromJson(Map<String, dynamic> j) => MatchOdds(
    home: (j['h'] as num?)?.toDouble(),
    draw: (j['d'] as num?)?.toDouble(),
    away: (j['a'] as num?)?.toDouble(),
    over25: (j['ov'] as num?)?.toDouble(),
    under25: (j['un'] as num?)?.toDouble(),
    mainOuLine: (j['mol'] as num?)?.toDouble(),
    spreadHomeOdds: (j['sho'] as num?)?.toDouble(),
    spreadAwayOdds: (j['sao'] as num?)?.toDouble(),
    spreadHomeLine: (j['shl'] as num?)?.toDouble(),
    spreadAwayLine: (j['sal'] as num?)?.toDouble(),
    bttsYes: (j['by'] as num?)?.toDouble(),
    bttsNo: (j['bn'] as num?)?.toDouble(),
    htHome: (j['hh'] as num?)?.toDouble(),
    htDraw: (j['hd'] as num?)?.toDouble(),
    htAway: (j['ha'] as num?)?.toDouble(),
    htOver15: (j['ho'] as num?)?.toDouble(),
    htUnder15: (j['hu'] as num?)?.toDouble(),
    asianHandicap: (j['ah'] as List?)
        ?.cast<Map<String, dynamic>>()
        .map(AsianHandicapLine.fromJson)
        .toList() ?? const [],
    extraMarkets: (j['em'] as List?)
        ?.cast<Map<String, dynamic>>()
        .map(ExtraMarket.fromJson)
        .toList() ?? const [],
    bookmaker: j['bk'] as String?,
    mlBookmaker: j['mb'] as String?,
    ouBookmaker: j['ob'] as String?,
    spreadBookmaker: j['sb'] as String?,
    ahBookmaker: j['ab'] as String?,
  );

  // Cotes Double Chance calculees depuis le 1X2 (approximation sans marge).
  // 1X = 1 / (1/home + 1/draw)
  // 12 = 1 / (1/home + 1/away)
  // X2 = 1 / (1/draw + 1/away)
  double? get dc1X => _dc(home, draw);
  double? get dc12 => _dc(home, away);
  double? get dcX2 => _dc(draw, away);

  double? _dc(double? a, double? b) {
    if (a == null || b == null || a <= 0 || b <= 0) return null;
    final p = (1 / a) + (1 / b);
    if (p <= 0) return null;
    return 1 / p;
  }

  bool get hasAny =>
      home != null || draw != null || away != null ||
      over25 != null || under25 != null ||
      spreadHomeOdds != null || spreadAwayOdds != null ||
      bttsYes != null || bttsNo != null ||
      htHome != null || htDraw != null || htAway != null ||
      asianHandicap.isNotEmpty ||
      extraMarkets.isNotEmpty;
}

// ── Service ───────────────────────────────────────────────

class StatpalService {
  StatpalService._();
  static final StatpalService instance = StatpalService._();

  static const _log = Logger('STATPAL');

  /// Toggle global. false = StatPal live (Phase 2). true = mocks (Phase 1).
  /// Le fallback automatique vers les mocks reste actif en cas d'erreur réseau
  /// ou parsing : useMocks=false ne casse jamais l'UI.
  static const bool useMocks = false;

  /// Ligues "featured" toujours fetchees en plus des top 10 du jour.
  /// Permet d'afficher les matchs futurs des grands evenements meme
  /// s'ils n'ont aucun match aujourd'hui.
  /// Liste curee depuis StatPal /soccer/leagues (1005 ligues totales) :
  static const _featuredSoccerLeagueIds = <String>[
    // ── International majeur ──
    '2889',   // World Cup 2026 (11.06 - 28.06.2026)
    '2838',   // UEFA Champions League 2025/2026
    '2840',   // UEFA Europa League 2025/2026
    '20686',  // UEFA Europa Conference League 2025/2026
    '3346',   // CAF Champions League 2025/2026
    '2855',   // AFC Champions League 2025/2026
    // ── Top 5 europeen ──
    '3037',   // Premier League (England) 2025/2026
    '3232',   // Primera / La Liga (Spain) 2025/2026
    '3102',   // Serie A (Italy) 2025/2026
    '3054',   // Ligue 1 (France) 2025/2026
    '3062',   // Bundesliga (Germany) 2025/2026
    // ── Autres ligues populaires globalement ──
    '2974',   // Brazil Serie A 2026 (EN COURS Jan-Dec)
    '3141',   // Liga MX (Mexico) 2025/2026
    '3201',   // Saudi Professional League 2025/2026
    // ── Ligues IN-SEASON ete 2026 (compensation intersaison Europe) ──
    '7151',   // Canadian Premier League 2026 (avr-oct 2026)
    '3091',   // Ireland Premier League 2026 (fev-oct 2026)
    '21042',  // Chile Copa De La Liga 2026 (mar-juin 2026)
    // ── Afrique (audience Plugbet) ──
    '2988',   // Cameroun Elite One 2025/2026 (marche local Plugbet)
    '3026',   // Egypt Premier League 2025/2026
    '3253',   // Tunisia Ligue 1 2025/2026
    '3159',   // Nigeria Premier League 2025/2026
    '3227',   // South Africa Premier League 2025/2026
    '3064',   // Ghana Premier League 2025/2026
    // Retire (saisons finies, 500 silencieux jusqu'a reprise aout/nov 2026) :
    //   '3155' Eredivisie -> reprend aout 2026
    //   '3863' Senegal Ligue 1 -> reprend novembre 2026
    //   '3004' Ivory Coast Ligue 1 -> reprend aout 2026
  ];

  // Caches moyens (90s) par sport. v2 a 2 endpoints distincts :
  // - live  : /{sport}/matches/live
  // - daily : /{sport}/matches/daily?offset=0
  // TTL 90s pour permettre warmup au splash -> data dispo instantanement
  // quand l'utilisateur ouvre l'onglet Paris.
  final Map<Sport, List<BettingMatch>> _liveCache = {};
  final Map<Sport, DateTime> _liveCacheAt = {};
  final Map<Sport, List<BettingMatch>> _dailyCache = {};
  final Map<Sport, DateTime> _dailyCacheAt = {};
  static const _cacheTtl = Duration(seconds: 90);

  // Cache prematch odds par leagueId (TTL 5 min). Garde les cotes prefetchees
  // au splash en memoire pour eviter de refaire 15 appels au mount du screen.
  final Map<String, Map<String, MatchOdds>> _leagueOddsCache = {};
  final Map<String, DateTime> _leagueOddsCacheAt = {};
  static const _leagueOddsTtl = Duration(minutes: 5);

  bool _warmedUpFast = false;
  bool _warmedUpFull = false;
  bool _hydratedFromDisk = false;
  Future<void>? _warmupFastFuture;
  Future<void>? _warmupFullFuture;

  /// True si on a hydrate les caches memoire depuis le disque (au boot).
  /// Le splash regarde ce flag pour decider s'il peut quitter immediatement
  /// (stale-while-revalidate : on a des donnees affichables tout de suite).
  bool get hasDiskCache => _hydratedFromDisk &&
      (_liveCache.isNotEmpty || _dailyCache.isNotEmpty);

  /// Hydrate les caches memoire depuis le disque (Hive). Appele AVANT le
  /// warmup reseau. Synchrone une fois StatpalDiskCache.init() termine.
  /// Marque toutes les entrees comme "stale" pour forcer un refresh, mais
  /// laisse les donnees affichables tant que le reseau n'a pas repondu.
  void hydrateFromDisk() {
    if (_hydratedFromDisk) return;
    final sw = Stopwatch()..start();
    final cache = StatpalDiskCache.instance;
    int n = 0;
    for (final sport in Sport.values) {
      final live = cache.getLive(sport);
      if (live != null) {
        _liveCache[sport] = live;
        // Date d'origine sur disque -> on garde mais on marque expire
        _liveCacheAt[sport] = DateTime.fromMillisecondsSinceEpoch(0);
        n += live.length;
      }
      final daily = cache.getDaily(sport);
      if (daily != null) {
        _dailyCache[sport] = daily;
        _dailyCacheAt[sport] = DateTime.fromMillisecondsSinceEpoch(0);
        n += daily.length;
      }
    }
    _hydratedFromDisk = true;
    _log.info(
        'hydrateFromDisk: $n matchs charges en ${sw.elapsedMilliseconds}ms');
  }

  /// Warmup RAPIDE (~4 calls HTTP) : juste live + daily des 2 sports en
  /// QUICK MODE (pas de fetch des 23+ ligues featured). Le splash attend
  /// ca seulement -> navigation < 2s. L'enrichissement complet (featured
  /// leagues + top odds) demarre automatiquement en background apres.
  Future<void> warmupFast() {
    if (_warmedUpFast) return Future.value();
    return _warmupFastFuture ??= _doWarmupFast();
  }

  /// Warmup COMPLET : ajoute les fetchs featured leagues + cotes prematch
  /// des top 6 ligues. Appele en background apres warmupFast().
  Future<void> warmupFull() {
    if (_warmedUpFull) return Future.value();
    return _warmupFullFuture ??= _doWarmupFull();
  }

  Future<void> _doWarmupFast() async {
    try {
      // 4 calls en parallele - aucun fetch des ligues featured
      await Future.wait([
        _fetchLive(Sport.soccer),
        _fetchDaily(Sport.soccer, quickMode: true),
        _fetchLive(Sport.basketball),
        _fetchDaily(Sport.basketball),
      ]);
      _warmedUpFast = true;
    } catch (e) {
      _log.warn('warmupFast error: $e');
    }
  }

  Future<void> _doWarmupFull() async {
    try {
      // Vide le cache daily soccer pour forcer le full fetch (avec featured)
      _dailyCache.remove(Sport.soccer);
      _dailyCacheAt.remove(Sport.soccer);
      final fullSoccer = await _fetchDaily(Sport.soccer, quickMode: false);
      final soccerToday = fullSoccer.where((m) => !m.isLive).toList();

      // Top 6 ligues soccer par matchs du jour - cotes prematch
      final byLeague = <String, int>{};
      for (final m in soccerToday) {
        final lid = m.leagueId;
        if (lid != null && lid.isNotEmpty) {
          byLeague[lid] = (byLeague[lid] ?? 0) + 1;
        }
      }
      final topLeagues = byLeague.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final leagueIds = topLeagues.take(6).map((e) => e.key).toList();

      await Future.wait([
        getLiveOdds(sport: Sport.soccer).catchError(
            (_) => <String, MatchOdds>{}),
        getLiveOdds(sport: Sport.basketball).catchError(
            (_) => <String, MatchOdds>{}),
        for (final lid in leagueIds)
          getLeagueOdds(lid, sport: Sport.soccer).catchError(
              (_) => <String, MatchOdds>{}),
      ]);
      _warmedUpFull = true;
    } catch (e) {
      _log.warn('warmupFull error: $e');
    }
  }

  /// Compat : ancien nom. Lance fast + full sequentiellement (full attend pas).
  Future<void> warmup() async {
    await warmupFast();
    unawaited(warmupFull());
  }

  /// Appelle l'edge function `statpal_proxy` et retourne la réponse JSON
  /// brute (String). Utilisé pour découvrir la structure des réponses
  /// StatPal avant d'écrire les parsers de Phase 2.
  ///
  /// Exemple : `await debugRawCall('/soccer/livescores');`
  Future<String?> debugRawCall(String path, {Map<String, String>? query}) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {
          'path': path,
          if (query != null) 'query': query,
        },
      );
      _log.info('debugRawCall $path -> status=${res.status}');
      return res.data is String ? res.data as String : res.data?.toString();
    } catch (e) {
      _log.warn('debugRawCall $path failed: $e');
      return null;
    }
  }

  /// Décode `res.data` (Map déjà décodée ou String JSON).
  Map<String, dynamic>? _decodeJson(dynamic data) {
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  /// Fetch matchs live. Path different selon sport :
  /// - Soccer V2 : /soccer/matches/live (struct live_matches.league[].match[])
  /// - NBA V1    : /nba/livescores (struct livescores...)
  Future<List<BettingMatch>> _fetchLive(Sport sport) async {
    final cached = _liveCache[sport];
    final cachedAt = _liveCacheAt[sport];
    if (cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }
    final path = sport == Sport.basketball
        ? '/nba/livescores'
        : '/${_sportPath(sport)}/matches/live';
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {'path': path},
      );
      if (res.status != 200) {
        _log.warn('_fetchLive($sport): HTTP ${res.status}, fallback mocks');
        return const <BettingMatch>[];
      }
      final json = _decodeJson(res.data);
      if (json == null) return const <BettingMatch>[];
      final result = sport == Sport.basketball
          ? _parseNbaLivescores(json)
          : _parseMatchesPayload(json, ['live_matches', 'livescore'], sport);
      _liveCache[sport] = result;
      _liveCacheAt[sport] = DateTime.now();
      StatpalDiskCache.instance.saveLive(sport, result);
      _log.info('_fetchLive($sport): ${result.length} matchs live');
      return result;
    } catch (e) {
      _log.warn('_fetchLive($sport) error: $e -> fallback mocks');
      return const <BettingMatch>[];
    }
  }

  /// Fetch matchs aujourd'hui + futurs.
  /// Strategie :
  /// 1. /{sport}/matches/daily?offset=0 -> tous les matchs today (1 call)
  /// 2. Pour les TOP 10 ligues du jour -> /{sport}/leagues/{id}/matches
  ///    qui renvoie ALL matchs de la ligue (today + futurs + passes).
  ///    On filtre les passes (>30j) cote client.
  /// 3. Merge + dedupe par main_id.
  ///
  /// Note : offset>0 sur /matches/daily NE MARCHE PAS chez StatPal v2
  /// (renvoie 0 ligues ou 400). Cette technique par-ligue est la seule.
  /// quickMode=true : skip les 23+ ligues featured ET le top-10 du jour.
  /// Retourne UNIQUEMENT le payload /matches/daily de base (~1 call HTTP).
  /// Utilise au splash pour navigation rapide. Le pipeline complet (avec
  /// featured leagues) tourne ensuite en background via _enrichDailyAsync.
  Future<List<BettingMatch>> _fetchDaily(Sport sport,
      {bool quickMode = false}) async {
    final cached = _dailyCache[sport];
    final cachedAt = _dailyCacheAt[sport];
    if (cached != null && cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return cached;
    }

    // ── Basketball / NBA : un seul endpoint /nba/odds renvoie les
    //    matchs upcoming AVEC odds embarquees. Pas de leagues/{id}/matches.
    if (sport == Sport.basketball) {
      try {
        final res = await Supabase.instance.client.functions.invoke(
          'statpal_proxy',
          body: {'path': '/nba/odds'},
        );
        if (res.status != 200) return const <BettingMatch>[];
        final json = _decodeJson(res.data);
        if (json == null) return const <BettingMatch>[];
        final result = _parseNbaOdds(json);
        _dailyCache[sport] = result;
        _dailyCacheAt[sport] = DateTime.now();
        StatpalDiskCache.instance.saveDaily(sport, result);
        _log.info('_fetchDaily(NBA): ${result.length} matchs');
        return result;
      } catch (e) {
        _log.warn('_fetchDaily(NBA) error: $e');
        return const <BettingMatch>[];
      }
    }

    final path = '/${_sportPath(sport)}/matches/daily';

    // ── 1. Fetch today (rapide, base de la liste) ──
    List<BettingMatch> today = const [];
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {'path': path, 'query': {'offset': '0'}},
      );
      if (res.status == 200) {
        final json = _decodeJson(res.data);
        if (json != null) {
          today = _parseMatchesPayload(json, [
            'daily_matches', 'scores', 'matches', 'live_matches', 'livescore',
          ], sport);
        }
      }
    } catch (e) {
      _log.warn('_fetchDaily today error: $e');
    }
    if (today.isEmpty) {
      return const <BettingMatch>[];
    }

    // ── QUICK MODE : retourne juste les matchs du jour, pas de 33+ calls
    //    supplementaires. Le pipeline complet tournera plus tard via
    //    _fetchDaily(sport, quickMode: false) en background.
    if (quickMode) {
      _dailyCache[sport] = today;
      _dailyCacheAt[sport] = DateTime.now();
      StatpalDiskCache.instance.saveDaily(sport, today);
      return today;
    }

    // ── 2. Identifie les top 10 ligues du jour ──
    final byLeague = <String, int>{};
    for (final m in today) {
      final lid = m.leagueId;
      if (lid != null && lid.isNotEmpty) {
        byLeague[lid] = (byLeague[lid] ?? 0) + 1;
      }
    }
    final topLeagues = byLeague.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // Top 10 du jour + ligues featured (CDM, etc.) toujours incluses
    final featured = sport == Sport.soccer ? _featuredSoccerLeagueIds : const [];
    final toFetch = {
      ...topLeagues.take(10).map((e) => e.key),
      ...featured,
    }.toList();

    // ── 3. Fetch tous les matchs de ces ligues (en parallele) ──
    final futures = toFetch.map(
        (lid) => getLeagueAllMatches(lid, sport: sport));
    final results = await Future.wait(futures);

    // ── 4. Merge today + ligues. Dedupe par id. Filtre matchs > 30j passe ──
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    final byId = <String, BettingMatch>{};
    for (final m in today) {
      byId[m.id] = m;
    }
    for (final list in results) {
      for (final m in list) {
        if (m.startTime.isBefore(cutoff)) continue;   // skip matchs passes
        byId.putIfAbsent(m.id, () => m);
      }
    }
    final combined = byId.values.toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    _dailyCache[sport] = combined;
    _dailyCacheAt[sport] = DateTime.now();
    StatpalDiskCache.instance.saveDaily(sport, combined);
    _log.info(
        '_fetchDaily($sport): ${today.length} today + futurs -> ${combined.length} total');
    return combined;
  }

  // Helpers _mocksLiveFor / _mocksTodayFor supprimes : on n'affiche PLUS
  // de matchs fictifs (Cameroun vs Senegal, Maroc, etc.) quand l'API
  // renvoie 0 match ou plante. Cas vide => empty state propre cote UI.

  // ── Parsers NBA V1 ─────────────────────────────────────
  // Structure StatPal NBA :
  //   odds.category.matches.match           (object ou array)
  //   match.odds.type[]                     (array de marches)
  //     - value: "3Way Result" / "Home/Away" / "Totals" / ...
  //     - bookmaker[].odd[]                 (Home/Draw/Away ou Over/Under)
  //
  // On utilise "Home/Away" pour le moneyline (basket sans draw).

  List<BettingMatch> _parseNbaOdds(Map<String, dynamic> json) {
    final root = json['odds'];
    if (root is! Map) return [];
    final category = root['category'];
    if (category is! Map) return [];
    final lid = category['id']?.toString();
    final lname = category['name']?.toString() ?? 'NBA';
    final matchesRaw = category['matches'];
    if (matchesRaw is! Map) return [];
    final mRaw = matchesRaw['match'];
    final matches = mRaw is List ? mRaw : (mRaw is Map ? [mRaw] : const []);

    final result = <BettingMatch>[];
    for (final m in matches) {
      if (m is! Map) continue;
      try {
        result.add(_parseNbaMatch(m, lid, lname));
      } catch (e) {
        _log.warn('parse NBA match: $e');
      }
    }
    return result;
  }

  List<BettingMatch> _parseNbaLivescores(Map<String, dynamic> json) {
    // Structure quand y a des matchs live : meme que odds (livescores.category.matches.match).
    // Quand pas de match live : juste {livescores: {sport: 'basketball'}} -> 0 match.
    final root = json['livescores'];
    if (root is! Map) return [];
    final category = root['category'];
    if (category is! Map) return [];
    final lid = category['id']?.toString();
    final lname = category['name']?.toString() ?? 'NBA';
    final matchesRaw = category['matches'];
    if (matchesRaw is! Map) return [];
    final mRaw = matchesRaw['match'];
    final matches = mRaw is List ? mRaw : (mRaw is Map ? [mRaw] : const []);

    final result = <BettingMatch>[];
    for (final m in matches) {
      if (m is! Map) continue;
      try {
        result.add(_parseNbaMatch(m, lid, lname));
      } catch (e) {
        _log.warn('parse NBA livescore: $e');
      }
    }
    return result;
  }

  BettingMatch _parseNbaMatch(Map m, String? leagueId, String leagueName) {
    final home = (m['home'] as Map?) ?? const {};
    final away = (m['away'] as Map?) ?? const {};
    final id = m['id']?.toString() ?? 'nba_${DateTime.now().microsecondsSinceEpoch}';
    final date = m['date']?.toString() ?? '';
    final time = m['time']?.toString() ?? '';
    final status = m['status']?.toString() ?? '';

    // NBA score : 'totalscore' (vide tant que match pas commence)
    final homeScore = int.tryParse(home['totalscore']?.toString() ?? '');
    final awayScore = int.tryParse(away['totalscore']?.toString() ?? '');

    final statusLower = status.toLowerCase();
    final isFinished = statusLower.contains('finished') ||
        statusLower.contains('ft') ||
        statusLower.contains('ended');
    final isNotStarted = statusLower.contains('not started') ||
        statusLower.isEmpty;
    final isLive = !isFinished && !isNotStarted && homeScore != null;

    final odds = _parseNbaOddsObject(m['odds']);

    // StatPal renvoie date+time en UTC (verifie via updated_ts unix epoch).
    // -> on parse en UTC, l'UI convertit en local via _formatTime(.toLocal()).
    DateTime startTime;
    try {
      final d = date.split('.');
      final t = time.split(':');
      startTime = DateTime.utc(
        int.parse(d[2]), int.parse(d[1]), int.parse(d[0]),
        int.parse(t[0]), int.parse(t[1]),
      );
    } catch (_) {
      startTime = DateTime.now().toUtc();
    }

    return BettingMatch(
      id: id,
      sport: Sport.basketball,
      leagueId: leagueId,
      homeName: home['name']?.toString() ?? 'Home',
      awayName: away['name']?.toString() ?? 'Away',
      league: leagueName,
      startTime: startTime,
      isLive: isLive,
      homeScore: homeScore,
      awayScore: awayScore,
      odds: odds,
    );
  }

  /// Extrait moneyline + Totals (avec ligne) + Spread du match.odds NBA.
  /// MATCHING STRICT par value.trim().toLowerCase() pour eviter de mixer
  /// avec des variantes "Home/Away - 1st Half" / "Spread Q1" etc.
  /// Bookmaker source TRACKE PAR MARCHE (peut differer entre sections).
  MatchOdds? _parseNbaOddsObject(dynamic oddsRaw) {
    if (oddsRaw is! Map) return null;
    final typeRaw = oddsRaw['type'];
    if (typeRaw is! List) return null;

    double? home, away, over, under, mainLine;
    double? spHome, spAway, spHomeLine, spAwayLine;
    String? mlBm, ouBm, spBm;
    bool mlDone = false, ouDone = false, spDone = false;
    final ahLines = <AsianHandicapLine>[];
    String? ahBm;
    final extraList = <ExtraMarket>[];

    Map? pickActiveBm(List bms) {
      for (final b in bms) {
        if (b is Map &&
            (b['stop']?.toString() ?? '').toLowerCase() != 'true') {
          return b;
        }
      }
      return bms.isNotEmpty && bms.first is Map ? bms.first as Map : null;
    }

    for (final mkt in typeRaw) {
      if (mkt is! Map) continue;
      final value = (mkt['value']?.toString() ?? '').trim().toLowerCase();
      final bmRaw = mkt['bookmaker'];
      final bms = bmRaw is List
          ? bmRaw
          : (bmRaw is Map ? [bmRaw] : const []);
      if (bms.isEmpty) continue;

      // Moneyline pure (Home/Away) - STRICT match du full game uniquement.
      // On skip toute variante 1st half/quarter/etc.
      if (!mlDone && (value == 'home/away' || value == 'moneyline')) {
        final activeBm = pickActiveBm(bms);
        if (activeBm == null) continue;
        final oddRaw = activeBm['odd'];
        final oddList = oddRaw is List
            ? oddRaw
            : (oddRaw is Map ? [oddRaw] : const []);
        for (final o in oddList) {
          if (o is! Map) continue;
          final n = (o['name']?.toString() ?? '').toLowerCase();
          final v = double.tryParse(o['value']?.toString() ?? '');
          if (n == 'home' || n == '1') {
            home = v;
          } else if (n == 'away' || n == '2') {
            away = v;
          }
        }
        if (home != null || away != null) {
          mlBm = activeBm['name']?.toString();
          mlDone = true;
        }
      } else if (!ouDone &&
          (value == 'totals' || value == 'total' ||
           value == 'over/under')) {
        final activeBm = pickActiveBm(bms);
        if (activeBm == null) continue;
        final totRaw = activeBm['total'];
        final totals = totRaw is List
            ? totRaw
            : (totRaw is Map ? [totRaw] : const []);
        for (final t in totals) {
          if (t is! Map) continue;
          if ((t['ismain']?.toString() ?? '').toLowerCase() != 'true') {
            continue;
          }
          mainLine = double.tryParse(t['name']?.toString() ?? '');
          final oddRaw = t['odd'];
          final oddList = oddRaw is List
              ? oddRaw
              : (oddRaw is Map ? [oddRaw] : const []);
          for (final o in oddList) {
            if (o is! Map) continue;
            final n = (o['name']?.toString() ?? '').toLowerCase();
            final v = double.tryParse(o['value']?.toString() ?? '');
            if (n == 'over') {
              over = v;
            } else if (n == 'under') {
              under = v;
            }
          }
          break;
        }
        if (over != null || under != null) {
          ouBm = activeBm['name']?.toString();
          ouDone = true;
        }
      } else if (!spDone &&
          (value == 'spread' || value == 'handicap')) {
        // Spread classique : 1 seule ligne (la main)
        final activeBm = pickActiveBm(bms);
        if (activeBm == null) continue;
        final hcRaw = activeBm['handicap'];
        final handicaps = hcRaw is List
            ? hcRaw
            : (hcRaw is Map ? [hcRaw] : const []);
        for (final h in handicaps) {
          if (h is! Map) continue;
          if ((h['ismain']?.toString() ?? '').toLowerCase() != 'true') {
            continue;
          }
          final raw = h['name']?.toString() ?? '';
          spHomeLine = double.tryParse(raw);
          if (spHomeLine != null) spAwayLine = -spHomeLine;
          final oddRaw = h['odd'];
          final oddList = oddRaw is List
              ? oddRaw
              : (oddRaw is Map ? [oddRaw] : const []);
          for (final o in oddList) {
            if (o is! Map) continue;
            final n = (o['name']?.toString() ?? '').toLowerCase();
            final v = double.tryParse(o['value']?.toString() ?? '');
            if (n == 'home' || n == '1') {
              spHome = v;
            } else if (n == 'away' || n == '2') {
              spAway = v;
            }
          }
          break;
        }
        if (spHome != null || spAway != null) {
          spBm = activeBm['name']?.toString();
          spDone = true;
        }
      } else if (value == 'asian handicap') {
        // AH NBA : multi-lines, meme structure que soccer
        final activeBm = pickActiveBm(bms);
        if (activeBm == null) continue;
        ahBm ??= activeBm['name']?.toString();
        final hcRaw = activeBm['handicap'];
        final handicaps = hcRaw is List
            ? hcRaw
            : (hcRaw is Map ? [hcRaw] : const []);
        for (final hc in handicaps) {
          if (hc is! Map) continue;
          if ((hc['stop']?.toString().toLowerCase()) == 'true') continue;
          final rawLine = hc['name']?.toString() ?? '';
          final line = double.tryParse(rawLine.replaceAll(RegExp(r'[^0-9.\-]'), ''));
          if (line == null) continue;
          // Skip quart-handicaps (NBA peut avoir 0.25, 0.75, etc.)
          final frac = (line * 100).abs() % 100;
          if (frac != 0 && frac != 50) continue;
          final isMain = (hc['ismain']?.toString().toLowerCase()) == 'true' ||
              (hc['is_main']?.toString().toLowerCase()) == 'true';
          final oddRaw2 = hc['odd'];
          final ahValues = oddRaw2 is List
              ? oddRaw2
              : (oddRaw2 is Map ? [oddRaw2] : const []);
          double? homeAh, awayAh;
          for (final v in ahValues) {
            if (v is! Map) continue;
            final n = (v['name']?.toString() ?? '').toLowerCase();
            final val = double.tryParse(v['value']?.toString() ?? '');
            if (n == 'home' || n == '1') {
              homeAh = val;
            } else if (n == 'away' || n == '2') {
              awayAh = val;
            }
          }
          if (homeAh == null || awayAh == null) continue;
          ahLines.add(AsianHandicapLine(
            line: line,
            homeOdds: homeAh,
            awayOdds: awayAh,
            isMain: isMain,
          ));
        }
      } else {
        // ── Marche generique NBA -> extraMarkets ──
        // Skip les marches deja capturés (1X2-style 3way result, etc. on les
        // laisse passer pour les avoir en plus).
        // Skip Player Props (complexite UI excessive sans roster mapping).
        if (value.startsWith('player ')) continue;
        final activeBm = pickActiveBm(bms);
        if (activeBm == null) continue;
        // Convertir la map en format compatible avec _buildExtraMarket :
        // le helper attend Map firstBm avec odd[], total[], handicap[].
        final rawName = mkt['value']?.toString() ?? '';
        final extra = _buildExtraMarket(value, rawName, activeBm);
        if (extra != null) extraList.add(extra);
      }
    }

    // Tri AH par ligne croissante (mains en premier)
    ahLines.sort((a, b) {
      if (a.isMain != b.isMain) return a.isMain ? -1 : 1;
      return a.line.compareTo(b.line);
    });
    // Tri extras
    extraList.sort((x, y) => _extraMarketPriority(x.code)
        .compareTo(_extraMarketPriority(y.code)));

    final allNull = home == null && away == null && over == null &&
        under == null && spHome == null && spAway == null &&
        ahLines.isEmpty && extraList.isEmpty;
    if (allNull) return null;

    return MatchOdds(
      home: home,
      away: away,
      over25: over,
      under25: under,
      mainOuLine: mainLine,
      spreadHomeOdds: spHome,
      spreadAwayOdds: spAway,
      spreadHomeLine: spHomeLine,
      spreadAwayLine: spAwayLine,
      asianHandicap: ahLines,
      extraMarkets: extraList,
      bookmaker: mlBm,         // legacy fallback
      mlBookmaker: mlBm,
      ouBookmaker: ouBm,
      spreadBookmaker: spBm,
      ahBookmaker: ahBm ?? mlBm,
    );
  }

  /// Parse une payload v2 contenant `{root}.league[].match[]`.
  List<BettingMatch> _parseMatchesPayload(
    Map<String, dynamic> json,
    List<String> rootKeys,
    Sport sport,
  ) {
    dynamic root;
    for (final k in rootKeys) {
      if (json[k] is Map) {
        root = json[k];
        break;
      }
    }
    if (root is! Map) return [];

    final leaguesRaw = root['league'];
    final leagues = leaguesRaw is List
        ? leaguesRaw
        : (leaguesRaw is Map ? [leaguesRaw] : const []);

    final result = <BettingMatch>[];
    for (final lg in leagues) {
      if (lg is! Map) continue;
      final leagueId = lg['id']?.toString();
      final leagueName = lg['name']?.toString() ?? 'Unknown league';
      final raw = lg['match'];
      final matches = raw is List ? raw : (raw is Map ? [raw] : const []);
      for (final m in matches) {
        if (m is! Map) continue;
        try {
          result.add(_parseSingleMatch(m, sport, leagueId, leagueName));
        } catch (e) {
          _log.warn('parse match ignored: $e');
        }
      }
    }
    return result;
  }

  BettingMatch _parseSingleMatch(Map m, Sport sport, String? leagueId, String leagueName) {
    final home = (m['home'] as Map?) ?? const {};
    final away = (m['away'] as Map?) ?? const {};
    // v2 utilise main_id ; v1 utilisait id. On accepte les 2.
    final id = m['main_id']?.toString()
        ?? m['id']?.toString()
        ?? 'sp_${DateTime.now().microsecondsSinceEpoch}';
    final date = m['date']?.toString() ?? '';   // ex "01.06.2026"
    final time = m['time']?.toString() ?? '';   // ex "19:00"
    final status = m['status']?.toString() ?? '';

    final homeScore = int.tryParse(home['goals']?.toString() ?? '');
    final awayScore = int.tryParse(away['goals']?.toString() ?? '');
    // isLive = scores parseables (pas "?") -> match en cours ou terminé.
    final isLive = homeScore != null && awayScore != null;

    int? minute;
    if (isLive) {
      final cleaned = status.replaceAll(RegExp(r'[^\d]'), '');
      minute = int.tryParse(cleaned);
    }

    // StatPal renvoie date+time en UTC -> parse UTC, UI affiche en local.
    DateTime startTime;
    try {
      final d = date.split('.');
      final t = time.split(':');
      startTime = DateTime.utc(
        int.parse(d[2]), int.parse(d[1]), int.parse(d[0]),
        int.parse(t[0]), int.parse(t[1]),
      );
    } catch (_) {
      startTime = DateTime.now().toUtc();
    }

    // StatPal expose parfois un logo selon le tier d'abonnement. On essaie
    // plusieurs noms de champs courants ; sinon null -> BetTeamCrest affiche
    // un avatar genere a partir des initiales.
    String? extractLogo(Map t) {
      for (final k in ['logo', 'image', 'logo_url', 'crest', 'badge']) {
        final v = t[k];
        if (v is String && v.isNotEmpty && v.startsWith('http')) return v;
      }
      return null;
    }

    return BettingMatch(
      id: id,
      sport: sport,
      leagueId: leagueId,
      homeName: home['name']?.toString() ?? 'Home',
      awayName: away['name']?.toString() ?? 'Away',
      homeLogo: extractLogo(home),
      awayLogo: extractLogo(away),
      league: leagueName,
      startTime: startTime,
      isLive: isLive,
      minute: minute,
      homeScore: homeScore,
      awayScore: awayScore,
      odds: null,
    );
  }

  /// Matchs en direct (score live) pour un sport donne.
  Future<List<BettingMatch>> getLiveMatches({Sport sport = Sport.soccer}) async {
    return _fetchLive(sport);
  }

  /// Matchs du jour (hors live) pour un sport donne.
  Future<List<BettingMatch>> getTodayMatches({Sport sport = Sport.soccer}) async {
    final all = await _fetchDaily(sport);
    return all.where((m) => !m.isLive).toList();
  }

  /// Cotes réelles d'un match.
  Future<MatchOdds?> getMatchOdds(
    String matchId, {
    required bool isLive,
    Sport sport = Sport.soccer,
  }) async {

    String? leagueId;
    for (final list in [_liveCache[sport], _dailyCache[sport]]) {
      if (list == null) continue;
      for (final m in list) {
        if (m.id == matchId) {
          leagueId = m.leagueId;
          break;
        }
      }
      if (leagueId != null) break;
    }

    try {
      final sp = _sportPath(sport);
      final String path;
      if (isLive) {
        path = '/$sp/odds/live';
      } else {
        if (leagueId == null) {
          _log.warn('getMatchOdds: leagueId inconnu pour $matchId');
          return null;
        }
        path = '/$sp/leagues/$leagueId/odds/prematch';
      }
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {'path': path},
      );
      if (res.status != 200) {
        _log.warn('getMatchOdds: HTTP ${res.status} sur $path');
        return null;
      }
      final json = _decodeJson(res.data);
      if (json == null) return null;
      return _parseOddsForMatch(json, matchId, isLive: isLive);
    } catch (e) {
      _log.warn('getMatchOdds error: $e');
      return null;
    }
  }

  /// Extrait les cotes du match `matchId` depuis une payload odds.
  /// Structure prematch_odds : `{league: {match: [{main_id, odds: [...]}]}}`
  /// Structure live_odds     : équivalente (league peut être liste ou objet).
  MatchOdds? _parseOddsForMatch(
    Map<String, dynamic> json,
    String matchId, {
    required bool isLive,
  }) {
    final candidateRoots = isLive
        ? ['live_odds', 'live_matches', 'livescore']
        : ['prematch_odds'];
    dynamic root;
    for (final k in candidateRoots) {
      if (json[k] is Map) {
        root = json[k];
        break;
      }
    }
    if (root is! Map) return null;

    final leagueRaw = root['league'];
    final leagues = leagueRaw is List
        ? leagueRaw
        : (leagueRaw is Map ? [leagueRaw] : const []);

    for (final lg in leagues) {
      if (lg is! Map) continue;
      final matchesRaw = lg['match'];
      final matches = matchesRaw is List
          ? matchesRaw
          : (matchesRaw is Map ? [matchesRaw] : const []);
      for (final m in matches) {
        if (m is! Map) continue;
        final mid = m['main_id']?.toString() ?? m['id']?.toString();
        if (mid != matchId) continue;
        return _parseMatchOdds(m['odds']);
      }
    }
    return null;
  }

  /// Parse `odds: [{name:"1x2", bookmaker:[{name, odd:[{name,value}]}]}, ...]`.
  /// MVP : on prend le 1er bookmaker disponible pour chaque marché.
  /// Capture aussi les marches mi-temps (HT 1X2 + HT OU 1.5).
  MatchOdds? _parseMatchOdds(dynamic odds) {
    if (odds is! List) return null;

    double? h, d, a, ov25, un25, bttsY, bttsN;
    double? htH, htD, htA, htOv15, htUn15;
    String? bookmakerName;
    final ahLines = <AsianHandicapLine>[];
    String? ahBookmaker;
    final extraList = <ExtraMarket>[];

    for (final market in odds) {
      if (market is! Map) continue;
      final marketName = (market['name']?.toString() ?? '').toLowerCase();
      final bmRaw = market['bookmaker'];
      final bookmakers = bmRaw is List
          ? bmRaw
          : (bmRaw is Map ? [bmRaw] : const []);
      if (bookmakers.isEmpty) continue;
      final firstBm = bookmakers.first;
      if (firstBm is! Map) continue;
      bookmakerName ??= firstBm['name']?.toString();
      final oddRaw = firstBm['odd'];
      final values = oddRaw is List
          ? oddRaw
          : (oddRaw is Map ? [oddRaw] : const []);

      final isHalfTime = marketName.contains('1st half') ||
          marketName.contains('half time') ||
          marketName.contains('halftime') ||
          marketName.contains('mi-temps') ||
          marketName.contains('1ere mi-temps') ||
          marketName.contains('1st period');

      if (marketName.contains('1x2') && !isHalfTime) {
        for (final v in values) {
          if (v is! Map) continue;
          final n = (v['name']?.toString() ?? '').toLowerCase();
          final val = double.tryParse(v['value']?.toString() ?? '');
          if (n == 'home' || n == '1') {
            h = val;
          } else if (n == 'draw' || n == 'x') {
            d = val;
          } else if (n == 'away' || n == '2') {
            a = val;
          }
        }
      } else if (marketName.contains('1x2') && isHalfTime) {
        for (final v in values) {
          if (v is! Map) continue;
          final n = (v['name']?.toString() ?? '').toLowerCase();
          final val = double.tryParse(v['value']?.toString() ?? '');
          if (n == 'home' || n == '1') {
            htH = val;
          } else if (n == 'draw' || n == 'x') {
            htD = val;
          } else if (n == 'away' || n == '2') {
            htA = val;
          }
        }
      } else if (marketName.contains('match goals') ||
          marketName.contains('over/under') ||
          marketName.contains('total goals') ||
          marketName.contains('total')) {
        final wantedHandicap = isHalfTime ? '1.5' : '2.5';
        for (final v in values) {
          if (v is! Map) continue;
          final n = (v['name']?.toString() ?? '').toLowerCase();
          final handicap = v['handicap']?.toString();
          if (handicap != null && handicap.isNotEmpty && handicap != wantedHandicap) {
            continue;
          }
          final val = double.tryParse(v['value']?.toString() ?? '');
          if (isHalfTime) {
            if (n.contains('over')) {
              htOv15 = val;
            } else if (n.contains('under')) {
              htUn15 = val;
            }
          } else {
            if (n.contains('over')) {
              ov25 = val;
            } else if (n.contains('under')) {
              un25 = val;
            }
          }
        }
      } else if (marketName.contains('both teams') ||
          marketName.contains('btts')) {
        for (final v in values) {
          if (v is! Map) continue;
          final n = (v['name']?.toString() ?? '').toLowerCase();
          final val = double.tryParse(v['value']?.toString() ?? '');
          if (n == 'yes') {
            bttsY = val;
          } else if (n == 'no') {
            bttsN = val;
          }
        }
      } else if (marketName.contains('double chance') &&
          !marketName.contains('half') && !marketName.contains('quarter')) {
        // Double Chance natif (preferer aux derives 1X2). Skip si HT/Q variants.
        // Pas integre en V1 - on garde le calcul derivé existant.
        continue;
      } else if (marketName == 'asian handicap') {
        // Structure differente : bookmaker.handicap[] (pas bookmaker.odd[])
        // Chaque entry : { name: "-1.5", is_main: "True", odd: [{name:"Home", value:".."}, {name:"Away", value:".."}] }
        // V1 : on garde uniquement entiers + demi-lines, skip les quart (-0.25, -0.75)
        ahBookmaker ??= firstBm['name']?.toString();
        final hcRaw = firstBm['handicap'];
        final handicaps = hcRaw is List
            ? hcRaw
            : (hcRaw is Map ? [hcRaw] : const []);
        for (final hc in handicaps) {
          if (hc is! Map) continue;
          if ((hc['stop']?.toString().toLowerCase()) == 'true') continue;
          final rawLine = hc['name']?.toString() ?? '';
          // Normalisation : "+0" -> 0.0, "-1.25" -> 1.25
          final line = double.tryParse(rawLine.replaceAll(RegExp(r'[^0-9.\-]'), ''));
          if (line == null) continue;
          // Skip quart-handicaps (settlement incompatible V1)
          final frac = (line * 100).abs() % 100;
          if (frac != 0 && frac != 50) continue;
          final isMain = (hc['is_main']?.toString().toLowerCase()) == 'true';
          final oddRaw2 = hc['odd'];
          final ahValues = oddRaw2 is List
              ? oddRaw2
              : (oddRaw2 is Map ? [oddRaw2] : const []);
          double? homeAh, awayAh;
          for (final v in ahValues) {
            if (v is! Map) continue;
            final n = (v['name']?.toString() ?? '').toLowerCase();
            final val = double.tryParse(v['value']?.toString() ?? '');
            if (n == 'home' || n == '1') {
              homeAh = val;
            } else if (n == 'away' || n == '2') {
              awayAh = val;
            }
          }
          if (homeAh == null || awayAh == null) continue;
          ahLines.add(AsianHandicapLine(
            line: line,
            homeOdds: homeAh,
            awayOdds: awayAh,
            isMain: isMain,
          ));
        }
        // Tri : mains d'abord, puis ligne croissante
        ahLines.sort((a, b) {
          if (a.isMain != b.isMain) return a.isMain ? -1 : 1;
          return a.line.compareTo(b.line);
        });
      } else {
        // ── Marche generique : on tente de le capturer dans extraMarkets ──
        final extra = _buildExtraMarket(
          marketName,
          market['name']?.toString() ?? '',
          firstBm,
        );
        if (extra != null) extraList.add(extra);
      }
    }

    // Tri des extras : marches "premium" en premier (Correct Score, HT/FT...)
    extraList.sort((x, y) => _extraMarketPriority(x.code)
        .compareTo(_extraMarketPriority(y.code)));

    final odds_ = MatchOdds(
      home: h, draw: d, away: a,
      over25: ov25, under25: un25,
      // Soccer : ligne OU fixee a 2.5 (filtree par handicap dans le parser)
      mainOuLine: (ov25 != null || un25 != null) ? 2.5 : null,
      bttsYes: bttsY, bttsNo: bttsN,
      htHome: htH, htDraw: htD, htAway: htA,
      htOver15: htOv15, htUnder15: htUn15,
      asianHandicap: ahLines,
      extraMarkets: extraList,
      bookmaker: bookmakerName,
      // Soccer : meme bookmaker pour la plupart des sections
      mlBookmaker: bookmakerName,
      ouBookmaker: bookmakerName,
      ahBookmaker: ahBookmaker ?? bookmakerName,
    );
    return odds_.hasAny ? odds_ : null;
  }

  // ============================================================
  // Helpers ExtraMarket : mapping name brut -> code + displayName + layout
  // ============================================================
  // Catalogue centralise des marches StatPal connus. La cle est le nom
  // brut tel que retourne par /odds/prematch (case-insensitive) ; pour les
  // marches non listes, le builder genere un code par defaut (kebab-case).
  static const Map<String, _ExtraMeta> _kExtraCatalog = {
    // === SOCCER ===
    'correct score':              _ExtraMeta('correct_score', 'Score exact', 'Pronostic du score final', ExtraMarketLayout.grid),
    'correct score 1st half':     _ExtraMeta('correct_score_ht', 'Score exact mi-temps', 'Score a la fin de la 1ere mi-temps', ExtraMarketLayout.grid),
    'ht/ft double':               _ExtraMeta('htft_double', 'Mi-temps / Fin de match', 'Mene a la pause + gagne au final', ExtraMarketLayout.grid),
    'ht/ft (including ot)':       _ExtraMeta('htft_ot', 'Mi-temps / Fin de match (avec prol.)', null, ExtraMarketLayout.grid),
    'odd/even':                   _ExtraMeta('odd_even', 'Pair ou impair', 'Nombre total de buts', ExtraMarketLayout.row2),
    'odd/even 1st half':          _ExtraMeta('odd_even_ht', 'Pair / impair mi-temps', null, ExtraMarketLayout.row2),
    'odd/even (2nd half)':        _ExtraMeta('odd_even_2h', 'Pair / impair 2e mi-temps', null, ExtraMarketLayout.row2),
    'home odd/even':              _ExtraMeta('odd_even_home', 'Pair / impair domicile', null, ExtraMarketLayout.row2),
    'away odd/even':              _ExtraMeta('odd_even_away', 'Pair / impair exterieur', null, ExtraMarketLayout.row2),
    'clean sheet - home':         _ExtraMeta('clean_sheet_home', 'Clean sheet domicile', 'Domicile n\'encaisse aucun but', ExtraMarketLayout.row2),
    'clean sheet - away':         _ExtraMeta('clean_sheet_away', 'Clean sheet exterieur', 'Exterieur n\'encaisse aucun but', ExtraMarketLayout.row2),
    'win to nil - home':          _ExtraMeta('win_to_nil_home', 'Domicile gagne sans encaisser', null, ExtraMarketLayout.row2),
    'win to nil - away':          _ExtraMeta('win_to_nil_away', 'Exterieur gagne sans encaisser', null, ExtraMarketLayout.row2),
    'win to nil':                 _ExtraMeta('win_to_nil', 'Gagne sans encaisser', null, ExtraMarketLayout.row3),
    'win both halves':            _ExtraMeta('win_both_halves', 'Gagne les 2 mi-temps', null, ExtraMarketLayout.row2),
    'to win either half':         _ExtraMeta('win_either_half', 'Gagne au moins une mi-temps', null, ExtraMarketLayout.row2),
    'highest scoring half':       _ExtraMeta('highest_half', 'Mi-temps la plus prolifique', null, ExtraMarketLayout.row3),
    'team to score first':        _ExtraMeta('team_score_first', 'Premiere equipe a marquer', null, ExtraMarketLayout.row3),
    'team to score last':         _ExtraMeta('team_score_last', 'Derniere equipe a marquer', null, ExtraMarketLayout.row3),
    'first goal method':          _ExtraMeta('first_goal_method', 'Methode du 1er but', 'Penalty / coup-franc / tete / etc.', ExtraMarketLayout.chips),
    'own goal':                   _ExtraMeta('own_goal', 'But contre son camp', null, ExtraMarketLayout.row2),
    'exact goals number':         _ExtraMeta('exact_goals', 'Nombre exact de buts', null, ExtraMarketLayout.chips),
    '1st half exact goals number':_ExtraMeta('exact_goals_ht', 'Buts exacts mi-temps', null, ExtraMarketLayout.chips),
    '2nd half exact goals number':_ExtraMeta('exact_goals_2h', 'Buts exacts 2e mi-temps', null, ExtraMarketLayout.chips),
    'home team exact goals number':_ExtraMeta('exact_goals_home', 'Buts exacts domicile', null, ExtraMarketLayout.chips),
    'away team exact goals number':_ExtraMeta('exact_goals_away', 'Buts exacts exterieur', null, ExtraMarketLayout.chips),
    'home team total goals(1st half)':_ExtraMeta('team_total_home_ht', 'Total buts domicile (MT)', null, ExtraMarketLayout.row2),
    'away team total goals(1st half)':_ExtraMeta('team_total_away_ht', 'Total buts exterieur (MT)', null, ExtraMarketLayout.row2),
    'home team total goals(2nd half)':_ExtraMeta('team_total_home_2h', 'Total buts domicile (2e MT)', null, ExtraMarketLayout.row2),
    'away team total goals(2nd half)':_ExtraMeta('team_total_away_2h', 'Total buts exterieur (2e MT)', null, ExtraMarketLayout.row2),
    'total - home':               _ExtraMeta('total_home', 'Total buts domicile (match)', null, ExtraMarketLayout.row2),
    'total - away':               _ExtraMeta('total_away', 'Total buts exterieur (match)', null, ExtraMarketLayout.row2),
    'over/under 1st half':        _ExtraMeta('ou_ht', 'Total buts mi-temps', null, ExtraMarketLayout.row2),
    'over/under 2nd half':        _ExtraMeta('ou_2h', 'Total buts 2e mi-temps', null, ExtraMarketLayout.row2),
    'winning margin':             _ExtraMeta('winning_margin', 'Ecart de victoire', null, ExtraMarketLayout.chips),
    'scoring draw':               _ExtraMeta('scoring_draw', 'Match nul avec buts', null, ExtraMarketLayout.row2),
    'home team will score in both halves':_ExtraMeta('home_score_both', 'Domicile marque dans les 2 MT', null, ExtraMarketLayout.row2),
    'away team will score in both halves':_ExtraMeta('away_score_both', 'Exterieur marque dans les 2 MT', null, ExtraMarketLayout.row2),
    'to score in both halves':    _ExtraMeta('btts_both_halves', 'BTTS dans les 2 MT', null, ExtraMarketLayout.row2),
    'to score in both halves by teams':_ExtraMeta('btts_both_halves_team', 'Equipe marque dans les 2 MT', null, ExtraMarketLayout.row3),
    'both teams to score - 1st half':_ExtraMeta('btts_ht', 'BTTS mi-temps', null, ExtraMarketLayout.row2),
    'both teams to score - 2nd half':_ExtraMeta('btts_2h', 'BTTS 2e mi-temps', null, ExtraMarketLayout.row2),
    'home team score a goal':     _ExtraMeta('home_score', 'Domicile marque', null, ExtraMarketLayout.row2),
    'away team score a goal':     _ExtraMeta('away_score', 'Exterieur marque', null, ExtraMarketLayout.row2),
    'first 10 min winner':        _ExtraMeta('first10_winner', 'Gagnant 10 premieres min', null, ExtraMarketLayout.row3),
    '1x2 - 15 minutes':           _ExtraMeta('1x2_15', '1X2 - 15 minutes', null, ExtraMarketLayout.row3),
    '1x2 - 30 minutes':           _ExtraMeta('1x2_30', '1X2 - 30 minutes', null, ExtraMarketLayout.row3),
    '1x2 - 60 minutes':           _ExtraMeta('1x2_60', '1X2 - 60 minutes', null, ExtraMarketLayout.row3),
    '1x2 - 75 minutes':           _ExtraMeta('1x2_75', '1X2 - 75 minutes', null, ExtraMarketLayout.row3),
    '1x2 2nd half':               _ExtraMeta('1x2_2h', '1X2 2e mi-temps', null, ExtraMarketLayout.row3),
    'first team to score (3 way) 1st half':_ExtraMeta('first_score_ht', '1ere equipe a marquer (MT)', null, ExtraMarketLayout.row3),
    'handicap result':            _ExtraMeta('handicap_eu', 'Handicap europeen', null, ExtraMarketLayout.row3),
    'handicap result 1st half':   _ExtraMeta('handicap_eu_ht', 'Handicap europeen MT', null, ExtraMarketLayout.row3),
    'european handicap (2nd half)':_ExtraMeta('handicap_eu_2h', 'Handicap europeen 2e MT', null, ExtraMarketLayout.row3),
    'asian handicap (2nd half)':  _ExtraMeta('ah_2h', 'Handicap asiatique 2e MT', null, ExtraMarketLayout.chips),
    'asian handicap first half':  _ExtraMeta('ah_ht', 'Handicap asiatique MT', null, ExtraMarketLayout.chips),
    'goal line':                  _ExtraMeta('goal_line', 'Goal line (asiatique)', null, ExtraMarketLayout.chips),
    'goal line (1st half)':       _ExtraMeta('goal_line_ht', 'Goal line MT', null, ExtraMarketLayout.chips),
    'results/both teams to score':_ExtraMeta('result_btts', 'Resultat + BTTS', null, ExtraMarketLayout.grid),
    'result/total goals':         _ExtraMeta('result_total', 'Resultat + Total buts', null, ExtraMarketLayout.grid),
    'result/total goals (1st half)':_ExtraMeta('result_total_ht', 'Resultat + Total (MT)', null, ExtraMarketLayout.grid),
    'total goals/both teams to score':_ExtraMeta('total_btts', 'Total buts + BTTS', null, ExtraMarketLayout.grid),
    'anytime goal scorer':        _ExtraMeta('any_scorer', 'Buteur dans le match', null, ExtraMarketLayout.chips),
    'first goal scorer':          _ExtraMeta('first_scorer', 'Premier buteur', null, ExtraMarketLayout.chips),
    'last goal scorer':           _ExtraMeta('last_scorer', 'Dernier buteur', null, ExtraMarketLayout.chips),

    // === NBA (V1) ===
    '3way result':                _ExtraMeta('3way', '3 voies (avec nul)', 'Inclut la possibilite d\'un match nul fin de temps reglementaire', ExtraMarketLayout.row3),
    '1st half 3way result':       _ExtraMeta('3way_ht', '3 voies mi-temps', null, ExtraMarketLayout.row3),
    '2nd half 3way result':       _ExtraMeta('3way_2h', '3 voies 2e mi-temps', null, ExtraMarketLayout.row3),
    '3way result - 1st qtr':      _ExtraMeta('3way_q1', '3 voies Q1', null, ExtraMarketLayout.row3),
    '3way result - 2nd qtr':      _ExtraMeta('3way_q2', '3 voies Q2', null, ExtraMarketLayout.row3),
    '3way result - 3rd qtr':      _ExtraMeta('3way_q3', '3 voies Q3', null, ExtraMarketLayout.row3),
    '3way result - 4th qtr':      _ExtraMeta('3way_q4', '3 voies Q4', null, ExtraMarketLayout.row3),
    'home/away - 1st half':       _ExtraMeta('ml_ht', 'Vainqueur 1ere mi-temps', null, ExtraMarketLayout.row2),
    'home/away - 2nd half':       _ExtraMeta('ml_2h', 'Vainqueur 2e mi-temps', null, ExtraMarketLayout.row2),
    'home/away - 1st qtr':        _ExtraMeta('ml_q1', 'Vainqueur Q1', null, ExtraMarketLayout.row2),
    'home/away - 2nd qtr':        _ExtraMeta('ml_q2', 'Vainqueur Q2', null, ExtraMarketLayout.row2),
    'home/away - 3rd qtr':        _ExtraMeta('ml_q3', 'Vainqueur Q3', null, ExtraMarketLayout.row2),
    'home/away - 4th qtr':        _ExtraMeta('ml_q4', 'Vainqueur Q4', null, ExtraMarketLayout.row2),
    'over/under 1st qtr':         _ExtraMeta('ou_q1', 'Total points Q1', null, ExtraMarketLayout.row2),
    'over/under 2nd qtr':         _ExtraMeta('ou_q2', 'Total points Q2', null, ExtraMarketLayout.row2),
    'over/under 3rd qtr':         _ExtraMeta('ou_q3', 'Total points Q3', null, ExtraMarketLayout.row2),
    'over/under 4th qtr':         _ExtraMeta('ou_q4', 'Total points Q4', null, ExtraMarketLayout.row2),
    'race to 30 points':          _ExtraMeta('race_30', 'Course aux 30 points', null, ExtraMarketLayout.row2),
    'race to 40 points':          _ExtraMeta('race_40', 'Course aux 40 points', null, ExtraMarketLayout.row2),
    'race to 50 points':          _ExtraMeta('race_50', 'Course aux 50 points', null, ExtraMarketLayout.row2),
    'highest scoring quarter':    _ExtraMeta('highest_qtr', 'Quart-temps le plus prolifique', null, ExtraMarketLayout.chips),
    'team with highest scoring quarter':_ExtraMeta('team_highest_qtr', 'Equipe du quart-temps top', null, ExtraMarketLayout.row2),
    'overtime':                   _ExtraMeta('overtime', 'Prolongation', 'Y aura-t-il des prolongations ?', ExtraMarketLayout.row2),
    'odd/even (including ot)':    _ExtraMeta('odd_even_ot', 'Pair / impair (avec prol.)', null, ExtraMarketLayout.row2),
    'home team total points (1st quarter)':_ExtraMeta('team_total_home_q1', 'Total points domicile Q1', null, ExtraMarketLayout.row2),
    'away team total points (1st quarter)':_ExtraMeta('team_total_away_q1', 'Total points exterieur Q1', null, ExtraMarketLayout.row2),
    'home team total points (2nd quarter)':_ExtraMeta('team_total_home_q2', 'Total points domicile Q2', null, ExtraMarketLayout.row2),
    'away team total points (2nd quarter)':_ExtraMeta('team_total_away_q2', 'Total points exterieur Q2', null, ExtraMarketLayout.row2),
    'home team total points (3rd quarter)':_ExtraMeta('team_total_home_q3', 'Total points domicile Q3', null, ExtraMarketLayout.row2),
    'away team total points (3rd quarter)':_ExtraMeta('team_total_away_q3', 'Total points exterieur Q3', null, ExtraMarketLayout.row2),
    'home team total points (4th quarter)':_ExtraMeta('team_total_home_q4', 'Total points domicile Q4', null, ExtraMarketLayout.row2),
    'away team total points (4th quarter)':_ExtraMeta('team_total_away_q4', 'Total points exterieur Q4', null, ExtraMarketLayout.row2),
    'home team total goals (including ot)':_ExtraMeta('team_total_home_ot', 'Total points domicile (avec prol.)', null, ExtraMarketLayout.row2),
    'away team total goals (including ot)':_ExtraMeta('team_total_away_ot', 'Total points exterieur (avec prol.)', null, ExtraMarketLayout.row2),
  };

  /// Mappe le nom raw du marche vers son ExtraMeta connu.
  /// Pour les noms inconnus : on genere un code kebab-case + on garde le nom
  /// brut comme displayName (fallback degrade mais affichable).
  _ExtraMeta _resolveExtraMeta(String rawName) {
    final key = rawName.trim().toLowerCase();
    final hit = _kExtraCatalog[key];
    if (hit != null) return hit;
    // Fallback : code stable derive du nom raw
    final code = key.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return _ExtraMeta(code.isEmpty ? 'unknown' : code, rawName, null, ExtraMarketLayout.row2);
  }

  /// Priorite de tri (plus petit = affiche en premier).
  /// Les marches "stars" (Correct Score, HT/FT, Race) remontent.
  int _extraMarketPriority(String code) {
    const top = {
      'correct_score': 10, 'htft_double': 11, 'ou_ht': 12, 'ou_2h': 13,
      '3way': 14, 'race_30': 15, 'race_40': 16, 'race_50': 17,
      'ou_q1': 20, 'ou_q2': 21, 'ou_q3': 22, 'ou_q4': 23,
      'odd_even': 30, 'overtime': 31, 'highest_half': 32, 'highest_qtr': 33,
    };
    return top[code] ?? 100;
  }

  /// Construit un ExtraMarket depuis le nom + le 1er bookmaker du marche.
  /// Supporte 3 structures StatPal :
  ///   - bookmaker.odd[]                 (most markets)
  ///   - bookmaker.total[].odd[]         (OU variantes avec ligne)
  ///   - bookmaker.handicap[].odd[]      (AH-like avec ligne)
  /// Retourne null si aucune cote valide.
  ExtraMarket? _buildExtraMarket(String marketName, String rawName, Map firstBm) {
    final meta = _resolveExtraMeta(rawName.isEmpty ? marketName : rawName);
    final extraOdds = <ExtraOdd>[];

    // ── Structure 1 : odd[] direct ──
    final oddRaw = firstBm['odd'];
    final flatOdds = oddRaw is List
        ? oddRaw
        : (oddRaw is Map ? [oddRaw] : const []);
    for (final v in flatOdds) {
      if (v is! Map) continue;
      final n = v['name']?.toString() ?? '';
      final val = double.tryParse(v['value']?.toString() ?? '');
      if (n.isEmpty || val == null || val < 1.01) continue;
      extraOdds.add(ExtraOdd(
        name: n,
        code: '${meta.code}_${_slugify(n)}',
        value: val,
      ));
    }

    // ── Structure 2 : total[] (OU variantes) ──
    final totalRaw = firstBm['total'];
    final totals = totalRaw is List
        ? totalRaw
        : (totalRaw is Map ? [totalRaw] : const []);
    for (final t in totals) {
      if (t is! Map) continue;
      if ((t['stop']?.toString().toLowerCase()) == 'true') continue;
      final line = double.tryParse(t['name']?.toString() ?? '');
      if (line == null) continue;
      final tOdd = t['odd'];
      final tValues = tOdd is List ? tOdd : (tOdd is Map ? [tOdd] : const []);
      for (final v in tValues) {
        if (v is! Map) continue;
        final n = (v['name']?.toString() ?? '').toLowerCase();
        final val = double.tryParse(v['value']?.toString() ?? '');
        if (val == null || val < 1.01) continue;
        final side = n.contains('over') ? 'over' : (n.contains('under') ? 'under' : n);
        extraOdds.add(ExtraOdd(
          name: '${side == 'over' ? '+' : '-'}${_fmtNum(line)}',
          code: '${meta.code}_$side@${_fmtNum(line)}',
          value: val,
          line: line,
        ));
      }
    }

    // ── Structure 3 : handicap[] (lignes asymetriques) ──
    final hcRaw = firstBm['handicap'];
    final handicaps = hcRaw is List
        ? hcRaw
        : (hcRaw is Map ? [hcRaw] : const []);
    for (final hc in handicaps) {
      if (hc is! Map) continue;
      if ((hc['stop']?.toString().toLowerCase()) == 'true') continue;
      final line = double.tryParse(hc['name']?.toString() ?? '');
      if (line == null) continue;
      final hOdd = hc['odd'];
      final hValues = hOdd is List ? hOdd : (hOdd is Map ? [hOdd] : const []);
      for (final v in hValues) {
        if (v is! Map) continue;
        final n = (v['name']?.toString() ?? '').toLowerCase();
        final val = double.tryParse(v['value']?.toString() ?? '');
        if (val == null || val < 1.01) continue;
        extraOdds.add(ExtraOdd(
          name: '$n ${_fmtSignedNum(line)}',
          code: '${meta.code}_$n@${_fmtSignedNum(line)}',
          value: val,
          line: line,
        ));
      }
    }

    if (extraOdds.isEmpty) return null;
    return ExtraMarket(
      name: marketName,
      code: meta.code,
      displayName: meta.displayName,
      subtitle: meta.subtitle,
      odds: extraOdds,
      bookmaker: firstBm['name']?.toString(),
      layout: meta.layout,
    );
  }

  static String _slugify(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  static String _fmtSignedNum(double v) {
    if (v == 0) return '0';
    final s = _fmtNum(v.abs());
    return v > 0 ? '+$s' : '-$s';
  }

  // ============================================================
  // STANDINGS / TEAM PROFILE (Phase 1)
  // ============================================================
  // Cache long (30 min standings, 1h team) - donnees lentes.
  final Map<String, LeagueStanding> _standingsCache = {};
  final Map<String, DateTime> _standingsCacheAt = {};
  static const _standingsTtl = Duration(minutes: 30);

  final Map<String, TeamProfile> _teamCache = {};
  final Map<String, DateTime> _teamCacheAt = {};
  static const _teamTtl = Duration(hours: 1);

  /// Classement d'une ligue. Soccer : `/soccer/leagues/{id}/standings`,
  /// NBA : `/nba/standings`. Renvoie null si plan ne couvre pas ou erreur.
  Future<LeagueStanding?> getLeagueStanding(
    String leagueId, {
    required Sport sport,
  }) async {
    if (useMocks) return null;
    final cacheKey = '${sport.name}:$leagueId';
    final at = _standingsCacheAt[cacheKey];
    if (at != null && DateTime.now().difference(at) < _standingsTtl) {
      return _standingsCache[cacheKey];
    }
    // Stale-while-revalidate : hydrate depuis disque si pas en memoire
    if (!_standingsCache.containsKey(cacheKey)) {
      final fromDisk = StatpalDiskCache.instance.getStanding(sport, leagueId);
      if (fromDisk != null) {
        _standingsCache[cacheKey] = fromDisk;
        _standingsCacheAt[cacheKey] = DateTime.fromMillisecondsSinceEpoch(0);
        // Continue le fetch reseau pour rafraichir, mais on a deja qqchose
      }
    }
    try {
      final path = sport == Sport.basketball
          ? '/nba/standings'
          : '/soccer/leagues/$leagueId/standings';
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {'path': path},
      );
      if (res.status != 200) return _standingsCache[cacheKey];
      final json = _decodeJson(res.data);
      if (json == null) return _standingsCache[cacheKey];
      final parsed = sport == Sport.basketball
          ? _parseNbaStandings(json)
          : _parseSoccerStandings(json, leagueId);
      if (parsed != null) {
        _standingsCache[cacheKey] = parsed;
        _standingsCacheAt[cacheKey] = DateTime.now();
        StatpalDiskCache.instance.saveStanding(sport, leagueId, parsed);
      }
      return parsed ?? _standingsCache[cacheKey];
    } catch (e) {
      _log.warn('getLeagueStanding($leagueId): $e');
      return _standingsCache[cacheKey];
    }
  }

  LeagueStanding? _parseSoccerStandings(Map<String, dynamic> json, String fallbackId) {
    // Structure : standings.tournament.team[]
    final root = json['standings'];
    if (root is! Map) return null;
    final tour = root['tournament'];
    if (tour is! Map) return null;
    final teamRaw = tour['team'];
    final teams = teamRaw is List
        ? teamRaw
        : (teamRaw is Map ? [teamRaw] : const []);
    final list = <TeamStanding>[];
    for (final t in teams) {
      if (t is! Map) continue;
      final pos = int.tryParse(t['position']?.toString() ?? '') ??
          int.tryParse(t['rank']?.toString() ?? '') ?? (list.length + 1);
      list.add(TeamStanding(
        position: pos,
        teamId: t['id']?.toString() ?? '',
        teamName: t['name']?.toString() ?? '?',
        played: int.tryParse(t['gp']?.toString() ?? '') ??
            int.tryParse(t['played']?.toString() ?? '') ?? 0,
        wins: int.tryParse(t['w']?.toString() ?? '') ??
            int.tryParse(t['wins']?.toString() ?? '') ?? 0,
        draws: int.tryParse(t['d']?.toString() ?? '') ??
            int.tryParse(t['draws']?.toString() ?? '') ?? 0,
        losses: int.tryParse(t['l']?.toString() ?? '') ??
            int.tryParse(t['losses']?.toString() ?? '') ?? 0,
        goalsFor: int.tryParse(t['gs']?.toString() ?? '') ??
            int.tryParse(t['goals_for']?.toString() ?? '') ?? 0,
        goalsAgainst: int.tryParse(t['ga']?.toString() ?? '') ??
            int.tryParse(t['goals_against']?.toString() ?? '') ?? 0,
        points: int.tryParse(t['pts']?.toString() ?? '') ??
            int.tryParse(t['points']?.toString() ?? '') ?? 0,
        form: t['form']?.toString(),
      ));
    }
    list.sort((a, b) => a.position.compareTo(b.position));
    return LeagueStanding(
      leagueId: tour['id']?.toString() ?? fallbackId,
      leagueName: tour['league']?.toString() ?? 'Classement',
      country: root['country']?.toString() ?? '',
      season: tour['season']?.toString() ?? '',
      teams: list,
    );
  }

  LeagueStanding? _parseNbaStandings(Map<String, dynamic> json) {
    // Structure : standings.tournament.league[].division[].team[]
    final root = json['standings'];
    if (root is! Map) return null;
    final tour = root['tournament'];
    if (tour is! Map) return null;
    final leagueRaw = tour['league'];
    final leagues = leagueRaw is List
        ? leagueRaw
        : (leagueRaw is Map ? [leagueRaw] : const []);
    final list = <TeamStanding>[];
    int globalPos = 1;
    for (final lg in leagues) {
      if (lg is! Map) continue;
      final divRaw = lg['division'];
      final divisions = divRaw is List
          ? divRaw
          : (divRaw is Map ? [divRaw] : const []);
      for (final div in divisions) {
        if (div is! Map) continue;
        final tRaw = div['team'];
        final teams = tRaw is List ? tRaw : (tRaw is Map ? [tRaw] : const []);
        for (final t in teams) {
          if (t is! Map) continue;
          list.add(TeamStanding(
            position: globalPos++,
            teamId: t['id']?.toString() ?? '',
            teamName: t['name']?.toString() ?? '?',
            played: int.tryParse(t['played']?.toString() ?? '') ??
                int.tryParse(t['gp']?.toString() ?? '') ?? 0,
            wins: int.tryParse(t['won']?.toString() ?? '') ??
                int.tryParse(t['w']?.toString() ?? '') ?? 0,
            draws: 0,  // pas de match nul en NBA
            losses: int.tryParse(t['lost']?.toString() ?? '') ??
                int.tryParse(t['l']?.toString() ?? '') ?? 0,
            goalsFor: int.tryParse(t['points_for']?.toString() ?? '') ?? 0,
            goalsAgainst: int.tryParse(t['points_against']?.toString() ?? '') ?? 0,
            points: int.tryParse(t['points']?.toString() ?? '') ??
                int.tryParse(t['won']?.toString() ?? '') ?? 0,
          ));
        }
      }
    }
    return LeagueStanding(
      leagueId: tour['id']?.toString() ?? '',
      leagueName: tour['name']?.toString() ?? 'NBA Standings',
      country: tour['country']?.toString() ?? 'USA',
      season: tour['season']?.toString() ?? '',
      teams: list,
    );
  }

  /// Fiche equipe soccer. Endpoint `/soccer/teams/{id}`.
  Future<TeamProfile?> getTeamProfile(String teamId) async {
    if (useMocks) return null;
    final at = _teamCacheAt[teamId];
    if (at != null && DateTime.now().difference(at) < _teamTtl) {
      return _teamCache[teamId];
    }
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {'path': '/soccer/teams/$teamId'},
      );
      if (res.status != 200) return null;
      final json = _decodeJson(res.data);
      if (json == null) return null;
      final t = json['team'];
      if (t is! Map) return null;
      final coachRaw = t['coach'];
      final coachName = coachRaw is Map ? coachRaw['name']?.toString() : null;
      final squadRaw = t['squad'];
      final players = <TeamPlayer>[];
      if (squadRaw is Map) {
        final playerRaw = squadRaw['player'];
        final pList = playerRaw is List
            ? playerRaw
            : (playerRaw is Map ? [playerRaw] : const []);
        for (final p in pList) {
          if (p is! Map) continue;
          players.add(TeamPlayer(
            id: p['id']?.toString() ?? '',
            name: p['name']?.toString() ?? '?',
            position: p['position']?.toString(),
            age: int.tryParse(p['age']?.toString() ?? ''),
            country: p['country']?.toString(),
            number: int.tryParse(p['shirt_number']?.toString() ?? ''),
          ));
        }
      }
      final profile = TeamProfile(
        id: t['id']?.toString() ?? teamId,
        name: t['name']?.toString() ?? '?',
        country: t['country']?.toString() ?? '',
        founded: t['founded']?.toString(),
        coachName: coachName,
        venueName: t['venue_name']?.toString(),
        venueCity: t['venue_city']?.toString(),
        venueCapacity: int.tryParse(t['venue_capacity']?.toString() ?? ''),
        venueSurface: t['venue_surface']?.toString(),
        squad: players,
      );
      _teamCache[teamId] = profile;
      _teamCacheAt[teamId] = DateTime.now();
      return profile;
    } catch (e) {
      _log.warn('getTeamProfile($teamId): $e');
      return null;
    }
  }

  /// Fetch TOUS les matchs d'une ligue (today + futurs).
  /// Endpoint /{sport}/leagues/{id}/matches : seule facon (confirmee via
  /// tests directs) d'obtenir les matchs futurs chez StatPal v2.
  /// Structure :
  ///   matches.tournament.stage[].match[]
  /// Match utilise `home.score` (PAS `home.goals` comme /matches/daily)
  /// et status text ("Not Started" / "Live" / "FT") au lieu de l'heure.
  Future<List<BettingMatch>> getLeagueAllMatches(
    String leagueId, {
    required Sport sport,
  }) async {
    if (useMocks) return const [];
    final sp = _sportPath(sport);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {'path': '/$sp/leagues/$leagueId/matches'},
      );
      if (res.status != 200) return const [];
      final json = _decodeJson(res.data);
      if (json == null) return const [];
      return _parseLeagueAllMatches(json, sport);
    } catch (e) {
      _log.warn('getLeagueAllMatches($leagueId) error: $e');
      return const [];
    }
  }

  List<BettingMatch> _parseLeagueAllMatches(
      Map<String, dynamic> json, Sport sport) {
    final result = <BettingMatch>[];
    final root = json['matches'];
    if (root is! Map) return result;
    final tournament = root['tournament'];
    if (tournament is! Map) return result;
    final leagueName = tournament['league']?.toString() ?? 'Unknown';
    final leagueId = tournament['id']?.toString();
    final country = root['country']?.toString() ?? '';
    final displayLeague = country.isNotEmpty
        ? '$country: $leagueName'.toLowerCase().replaceAllMapped(
            RegExp(r'(?:^|\s|:)\w'), (m) => m.group(0)!.toUpperCase())
        : leagueName;

    final stageRaw = tournament['stage'];
    final stages = stageRaw is List
        ? stageRaw
        : (stageRaw is Map ? [stageRaw] : const []);

    for (final stage in stages) {
      if (stage is! Map) continue;
      final matchRaw = stage['match'];
      final matches = matchRaw is List
          ? matchRaw
          : (matchRaw is Map ? [matchRaw] : const []);
      for (final m in matches) {
        if (m is! Map) continue;
        try {
          result.add(_parseLeagueMatchObj(m, sport, leagueId, displayLeague));
        } catch (e) {
          _log.warn('parse league match ignored: $e');
        }
      }
    }
    return result;
  }

  BettingMatch _parseLeagueMatchObj(
      Map m, Sport sport, String? leagueId, String leagueName) {
    final home = (m['home'] as Map?) ?? const {};
    final away = (m['away'] as Map?) ?? const {};
    final id = m['main_id']?.toString() ??
        m['id']?.toString() ??
        'sp_${DateTime.now().microsecondsSinceEpoch}';
    final date = m['date']?.toString() ?? '';
    final time = m['time']?.toString() ?? '';
    final status = m['status']?.toString() ?? '';

    // ⚠️ Different de /matches/daily : `score` au lieu de `goals`
    final homeScore = int.tryParse(home['score']?.toString() ?? '');
    final awayScore = int.tryParse(away['score']?.toString() ?? '');

    final statusLower = status.toLowerCase();
    final isFinished = statusLower.contains('ft') ||
        statusLower.contains('finished') ||
        statusLower == 'aet';
    final isNotStarted = statusLower.contains('not started') ||
        statusLower.isEmpty;
    final isLive = !isFinished && !isNotStarted &&
        (homeScore != null || awayScore != null);

    int? minute;
    if (isLive) {
      final cleaned = status.replaceAll(RegExp(r'[^\d]'), '');
      minute = int.tryParse(cleaned);
    }

    // StatPal renvoie date+time en UTC -> parse UTC, UI affiche en local.
    DateTime startTime;
    try {
      final d = date.split('.');
      final t = time.split(':');
      startTime = DateTime.utc(
        int.parse(d[2]), int.parse(d[1]), int.parse(d[0]),
        int.parse(t[0]), int.parse(t[1]),
      );
    } catch (_) {
      startTime = DateTime.now().toUtc();
    }

    return BettingMatch(
      id: id,
      sport: sport,
      leagueId: leagueId,
      homeName: home['name']?.toString() ?? 'Home',
      awayName: away['name']?.toString() ?? 'Away',
      homeLogo: null, awayLogo: null,
      league: leagueName,
      startTime: startTime,
      isLive: isLive,
      minute: minute,
      homeScore: homeScore,
      awayScore: awayScore,
      odds: null,
    );
  }

  /// Prefetch des cotes prematch pour une ligue entiere (upcoming).
  /// Retourne Map<matchId, MatchOdds>. 1 appel API renvoie tous les matchs.
  Future<Map<String, MatchOdds>> getLeagueOdds(
    String leagueId, {
    required Sport sport,
  }) async {
    if (useMocks) return const {};
    final key = '${sport.name}:$leagueId';
    final cached = _leagueOddsCache[key];
    final at = _leagueOddsCacheAt[key];
    if (cached != null && at != null &&
        DateTime.now().difference(at) < _leagueOddsTtl) {
      return cached;
    }
    final sp = _sportPath(sport);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {'path': '/$sp/leagues/$leagueId/odds/prematch'},
      );
      if (res.status != 200) return const {};
      final json = _decodeJson(res.data);
      if (json == null) return const {};
      final parsed = _parseOddsCollection(json, ['prematch_odds']);
      _leagueOddsCache[key] = parsed;
      _leagueOddsCacheAt[key] = DateTime.now();
      return parsed;
    } catch (e) {
      _log.warn('getLeagueOdds($leagueId) error: $e');
      return const {};
    }
  }

  /// Prefetch des cotes live (inplay) pour TOUS les matchs en cours.
  /// 1 seul appel API : /{sport}/odds/live renvoie tous les matchs live.
  Future<Map<String, MatchOdds>> getLiveOdds({required Sport sport}) async {
    if (useMocks) return const {};
    final sp = _sportPath(sport);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'statpal_proxy',
        body: {'path': '/$sp/odds/live'},
      );
      if (res.status != 200) return const {};
      final json = _decodeJson(res.data);
      if (json == null) return const {};
      return _parseOddsCollection(json, ['live_odds', 'odds_live', 'live']);
    } catch (e) {
      _log.warn('getLiveOdds error: $e');
      return const {};
    }
  }

  /// Parser unifie odds prematch / live. Accepte :
  /// - {root}.league[].match[]  (prematch : avec league objet OU liste)
  /// - {root}.match[]           (flat, sans wrapper league)
  /// - {root: array de live_match} (live odds endpoint - format different)
  Map<String, MatchOdds> _parseOddsCollection(
    Map<String, dynamic> json,
    List<String> rootKeys,
  ) {
    final result = <String, MatchOdds>{};

    // ── Format LIVE : { "live_matches": [...] } direct sur le json racine ──
    final liveMatches = json['live_matches'];
    if (liveMatches is List) {
      for (final lm in liveMatches) {
        if (lm is! Map) continue;
        final info = lm['match_info'];
        final mid = info is Map
            ? (info['main_id']?.toString() ?? info['id']?.toString())
            : (lm['main_id']?.toString() ?? lm['id']?.toString());
        if (mid == null) continue;
        final o = _parseLiveMatchOdds(lm['odds']);
        if (o != null) result[mid] = o;
      }
      if (result.isNotEmpty) return result;
    }

    dynamic root;
    for (final k in rootKeys) {
      if (json[k] is Map) { root = json[k]; break; }
    }
    if (root is! Map) return result;

    void absorb(dynamic matchesRaw) {
      final matches = matchesRaw is List
          ? matchesRaw
          : (matchesRaw is Map ? [matchesRaw] : const []);
      for (final m in matches) {
        if (m is! Map) continue;
        final mid = m['main_id']?.toString() ?? m['id']?.toString();
        if (mid == null) continue;
        final o = _parseMatchOdds(m['odds']);
        if (o != null) result[mid] = o;
      }
    }

    final leagueRaw = root['league'];
    if (leagueRaw != null) {
      final leagues = leagueRaw is List
          ? leagueRaw
          : (leagueRaw is Map ? [leagueRaw] : const []);
      for (final lg in leagues) {
        if (lg is Map) absorb(lg['match']);
      }
    } else {
      absorb(root['match']);
    }
    return result;
  }

  /// Parser LIVE soccer. Structure :
  ///   odds[]: { market_id, market_name, suspended, lines[]: {name, odd, handicap?} }
  /// Mappe vers les memes codes que prematch (home/draw/away/over25/etc.)
  /// + extraMarkets pour le reste.
  MatchOdds? _parseLiveMatchOdds(dynamic odds) {
    if (odds is! List) return null;
    double? h, d, a, ov25, un25, bttsY, bttsN;
    double? htH, htD, htA, htOv15, htUn15;
    final ahLines = <AsianHandicapLine>[];
    final extraList = <ExtraMarket>[];

    for (final mkt in odds) {
      if (mkt is! Map) continue;
      if ((mkt['suspended']?.toString() ?? '') == '1') continue;
      final name = (mkt['market_name']?.toString() ?? '').trim().toLowerCase();
      final linesRaw = mkt['lines'];
      final lines = linesRaw is List
          ? linesRaw
          : (linesRaw is Map ? [linesRaw] : const []);
      if (lines.isEmpty) continue;

      // Helper extract Home/Draw/Away
      double? lh, ld, la;
      for (final l in lines) {
        if (l is! Map) continue;
        if ((l['suspended']?.toString() ?? '') == '1') continue;
        final n = (l['name']?.toString() ?? '').toLowerCase();
        final v = double.tryParse(l['odd']?.toString() ?? '');
        if (n == 'home' || n == '1') {
          lh = v;
        } else if (n == 'draw' || n == 'x') {
          ld = v;
        } else if (n == 'away' || n == '2') {
          la = v;
        }
      }

      // ── 1X2 / Fulltime Result / Final Score ──
      if (name == 'fulltime result' || name == 'final score' || name == '1x2') {
        h ??= lh; d ??= ld; a ??= la;
      }
      // ── 1X2 1st Half ──
      else if (name == '1x2 (1st half)') {
        htH ??= lh; htD ??= ld; htA ??= la;
      }
      // ── Over/Under fixe 2.5 (Match Goals) ──
      else if (name == 'match goals') {
        for (final l in lines) {
          if (l is! Map) continue;
          final n = (l['name']?.toString() ?? '').toLowerCase();
          final v = double.tryParse(l['odd']?.toString() ?? '');
          final hc = double.tryParse(l['handicap']?.toString() ?? '');
          if (hc != null && hc != 2.5) continue;
          if (n.contains('over')) {
            ov25 ??= v;
          } else if (n.contains('under')) {
            un25 ??= v;
          }
        }
      }
      // ── OU 1st Half ──
      else if (name == 'over/under (1st half)') {
        for (final l in lines) {
          if (l is! Map) continue;
          final n = (l['name']?.toString() ?? '').toLowerCase();
          final v = double.tryParse(l['odd']?.toString() ?? '');
          final hc = double.tryParse(l['handicap']?.toString() ?? '');
          if (hc != null && hc != 1.5) continue;
          if (n.contains('over')) {
            htOv15 ??= v;
          } else if (n.contains('under')) {
            htUn15 ??= v;
          }
        }
      }
      // ── BTTS via "Both teams to score" si present (pas dans liste actuelle mais possible) ──
      else if (name == 'both teams to score' || name == 'btts') {
        for (final l in lines) {
          if (l is! Map) continue;
          final n = (l['name']?.toString() ?? '').toLowerCase();
          final v = double.tryParse(l['odd']?.toString() ?? '');
          if (n == 'yes') {
            bttsY ??= v;
          } else if (n == 'no') {
            bttsN ??= v;
          }
        }
      }
      // ── Asian Handicap (multi-lignes) ──
      else if (name == 'asian handicap') {
        // En live, chaque line a son handicap. Regroupe par handicap.
        final byLine = <double, ({double? h, double? a})>{};
        for (final l in lines) {
          if (l is! Map) continue;
          final n = (l['name']?.toString() ?? '').toLowerCase();
          final v = double.tryParse(l['odd']?.toString() ?? '');
          final hc = double.tryParse(l['handicap']?.toString() ?? '');
          if (hc == null || v == null) continue;
          final frac = (hc * 100).abs() % 100;
          if (frac != 0 && frac != 50) continue;  // skip quarts
          final existing = byLine[hc] ?? (h: null, a: null);
          if (n == 'home' || n == '1') {
            byLine[hc] = (h: v, a: existing.a);
          } else if (n == 'away' || n == '2') {
            byLine[hc] = (h: existing.h, a: v);
          }
        }
        byLine.forEach((line, pair) {
          if (pair.h != null && pair.a != null) {
            ahLines.add(AsianHandicapLine(
              line: line,
              homeOdds: pair.h!,
              awayOdds: pair.a!,
              isMain: ahLines.isEmpty,  // premiere = main par defaut
            ));
          }
        });
      }
      // ── Tous les autres -> generic extra ──
      else {
        final meta = _resolveExtraMeta(mkt['market_name']?.toString() ?? '');
        final extraOdds = <ExtraOdd>[];
        for (final l in lines) {
          if (l is! Map) continue;
          if ((l['suspended']?.toString() ?? '') == '1') continue;
          final n = l['name']?.toString() ?? '';
          final v = double.tryParse(l['odd']?.toString() ?? '');
          if (n.isEmpty || v == null || v < 1.01) continue;
          final hc = double.tryParse(l['handicap']?.toString() ?? '');
          extraOdds.add(ExtraOdd(
            name: hc != null ? '$n ${_fmtSignedNum(hc)}' : n,
            code: hc != null
                ? '${meta.code}_${_slugify(n)}@${_fmtNum(hc)}'
                : '${meta.code}_${_slugify(n)}',
            value: v,
            line: hc,
          ));
        }
        if (extraOdds.isNotEmpty) {
          extraList.add(ExtraMarket(
            name: mkt['market_name']?.toString() ?? '',
            code: meta.code,
            displayName: meta.displayName,
            subtitle: meta.subtitle,
            odds: extraOdds,
            layout: meta.layout,
          ));
        }
      }
    }

    ahLines.sort((a, b) {
      if (a.isMain != b.isMain) return a.isMain ? -1 : 1;
      return a.line.compareTo(b.line);
    });
    extraList.sort((x, y) => _extraMarketPriority(x.code)
        .compareTo(_extraMarketPriority(y.code)));

    final odds_ = MatchOdds(
      home: h, draw: d, away: a,
      over25: ov25, under25: un25,
      mainOuLine: (ov25 != null || un25 != null) ? 2.5 : null,
      bttsYes: bttsY, bttsNo: bttsN,
      htHome: htH, htDraw: htD, htAway: htA,
      htOver15: htOv15, htUnder15: htUn15,
      asianHandicap: ahLines,
      extraMarkets: extraList,
    );
    return odds_.hasAny ? odds_ : null;
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

// Mocks supprimes : seuls les vrais matchs StatPal s'affichent dans l'app.
// Pour les matchs simules pedagogiques -> VirtualMatchService (UI separee).

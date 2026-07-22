// ============================================================
// The Odds API — Mapper pur (JSON -> BettingMatch / MatchOdds)
// ============================================================
// Fonctions PURES (aucune I/O reseau) => entierement testables hors ligne.
// Transforme les reponses The Odds API vers les MEMES modeles que
// l'ancien StatPal (BettingMatch / MatchOdds), pour que betting_screen /
// bet_slip_odds_refresher continuent de fonctionner apres bascule.
//
// Formats source (the-odds-api.com v4) :
//   /v4/sports/{key}/odds  -> [{ id, sport_key, sport_title, commence_time,
//     home_team, away_team, bookmakers:[{ key, title, markets:[
//       { key:'h2h'|'totals'|'spreads', outcomes:[{name, price, point?}] }]}]}]
//   /v4/sports/{key}/scores -> [{ id, sport_key, commence_time, completed,
//     home_team, away_team, scores: null | [{name, score:"3"}], last_update }]
//
// Regle cotes : on selectionne UN bookmaker principal par event (le plus
// complet sur h2h/totals/spreads) pour garder des cotes coherentes entre
// marches. Les scores sont matches par NOM d'equipe (pas par position).
//
// Convention d'ID : match_id interne = 'oa_' + <event id The Odds API>
// (identique a external_event_map.internal_match_id). Disjoint des IDs
// StatPal (main_id) et virtuels (virt_xxx).
// ============================================================

import 'statpal_service.dart'
    show Sport, BettingMatch, MatchOdds, AsianHandicapLine;

const String kOddsApiPrefix = 'oa_';

/// Prefixe l'id event The Odds API en match_id interne.
String oddsApiInternalId(String eventId) => '$kOddsApiPrefix$eventId';

/// Sport canonique 2Up pour un Sport de l'UI.
/// Correspond aux clefs de sport_2up_config (soccer -> 'football').
String canonicalSportName(Sport s) {
  switch (s) {
    case Sport.soccer:
      return 'football';
    case Sport.basketball:
      return 'basketball';
    case Sport.americanFootball:
      return 'american_football';
    case Sport.baseball:
      return 'baseball';
    case Sport.tennis:
      return 'tennis';
    case Sport.iceHockey:
      return 'ice_hockey';
    case Sport.rugby:
      return 'rugby';
    case Sport.handball:
      return 'handball';
  }
}

/// Sport canonique (enum courant) depuis un sport_key The Odds API.
/// Gere les familles affichees dans l'onglet Sports.
Sport? sportFromKey(String? sportKey) {
  if (sportKey == null) return null;
  if (sportKey.startsWith('soccer')) return Sport.soccer;
  if (sportKey.startsWith('basketball')) return Sport.basketball;
  if (sportKey.startsWith('americanfootball')) {
    return Sport.americanFootball;
  }
  if (sportKey.startsWith('baseball')) return Sport.baseball;
  if (sportKey.startsWith('tennis')) return Sport.tennis;
  if (sportKey.startsWith('icehockey')) return Sport.iceHockey;
  // Rugby : The Odds API separe League et Union -> on les regroupe.
  if (sportKey.startsWith('rugbyleague') || sportKey.startsWith('rugbyunion')) {
    return Sport.rugby;
  }
  if (sportKey.startsWith('handball')) return Sport.handball;
  return null;
}

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _i(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

DateTime _parseTime(dynamic v) {
  if (v is String) {
    final t = DateTime.tryParse(v);
    if (t != null) return t.toUtc();
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// Marches qu'on sait mapper. Sert a scorer la completude d'un bookmaker.
const _wantedMarkets = {'h2h', 'totals', 'spreads'};

/// Selectionne le bookmaker le plus complet (max de marches voulus presents),
/// tie-break sur l'ordre d'apparition. Renvoie null si aucun.
Map<String, dynamic>? pickPrimaryBookmaker(dynamic bookmakersRaw) {
  if (bookmakersRaw is! List) return null;
  Map<String, dynamic>? best;
  int bestScore = -1;
  for (final b in bookmakersRaw) {
    if (b is! Map) continue;
    final bm = b.cast<String, dynamic>();
    final markets = bm['markets'];
    int score = 0;
    if (markets is List) {
      for (final m in markets) {
        if (m is Map && _wantedMarkets.contains(m['key'])) score++;
      }
    }
    if (score > bestScore) {
      bestScore = score;
      best = bm;
    }
  }
  return bestScore > 0 ? best : null;
}

Map<String, dynamic>? _marketByKey(Map<String, dynamic> bookmaker, String key) {
  final markets = bookmaker['markets'];
  if (markets is! List) return null;
  for (final m in markets) {
    if (m is Map && m['key'] == key) return m.cast<String, dynamic>();
  }
  return null;
}

/// Construit MatchOdds a partir d'UN bookmaker + noms d'equipes.
MatchOdds? oddsFromBookmaker(
  Map<String, dynamic>? bookmaker,
  String homeTeam,
  String awayTeam,
  Sport sport,
) {
  if (bookmaker == null) return null;
  final bookTitle =
      bookmaker['title'] as String? ?? bookmaker['key'] as String?;

  double? home, draw, away;
  double? over, under, ouLine;
  double? spHomeOdds, spAwayOdds, spHomeLine, spAwayLine;
  final ah = <AsianHandicapLine>[];

  // ── h2h -> 1X2 (match par nom d'equipe) ──
  final h2h = _marketByKey(bookmaker, 'h2h');
  if (h2h != null && h2h['outcomes'] is List) {
    for (final o in (h2h['outcomes'] as List)) {
      if (o is! Map) continue;
      final name = o['name']?.toString();
      final price = _d(o['price']);
      if (price == null) continue;
      if (name == homeTeam) {
        home = price;
      } else if (name == awayTeam) {
        away = price;
      } else if (name == 'Draw' || name == 'Nul') {
        draw = price;
      }
    }
  }

  // ── totals -> Over/Under (ligne principale) ──
  final totals = _marketByKey(bookmaker, 'totals');
  if (totals != null && totals['outcomes'] is List) {
    for (final o in (totals['outcomes'] as List)) {
      if (o is! Map) continue;
      final name = (o['name']?.toString() ?? '').toLowerCase();
      final price = _d(o['price']);
      final point = _d(o['point']);
      if (price == null) continue;
      if (name == 'over') {
        over = price;
        ouLine ??= point;
      } else if (name == 'under') {
        under = price;
        ouLine ??= point;
      }
    }
  }

  // ── spreads -> handicap (home/away) + 1 ligne AH ──
  final spreads = _marketByKey(bookmaker, 'spreads');
  if (spreads != null && spreads['outcomes'] is List) {
    for (final o in (spreads['outcomes'] as List)) {
      if (o is! Map) continue;
      final name = o['name']?.toString();
      final price = _d(o['price']);
      final point = _d(o['point']);
      if (price == null) continue;
      if (name == homeTeam) {
        spHomeOdds = price;
        spHomeLine = point;
      } else if (name == awayTeam) {
        spAwayOdds = price;
        spAwayLine = point;
      }
    }
    // Ligne AH cote home (exclut quart-handicaps .25/.75 -> settlement entier/demi)
    if (spHomeOdds != null && spAwayOdds != null && spHomeLine != null) {
      final frac = (spHomeLine.abs() * 4) % 2; // 0 pour .0/.5, 1 pour .25/.75
      if (frac == 0) {
        ah.add(AsianHandicapLine(
          line: spHomeLine,
          homeOdds: spHomeOdds,
          awayOdds: spAwayOdds,
          isMain: true,
        ));
      }
    }
  }

  final odds = MatchOdds(
    home: home,
    // Le nul (X) n'existe qu'aux sports qui l'autorisent : foot, rugby, handball.
    draw: (sport == Sport.soccer ||
            sport == Sport.rugby ||
            sport == Sport.handball)
        ? draw
        : null,
    away: away,
    over25: over,
    under25: under,
    mainOuLine: ouLine,
    spreadHomeOdds: spHomeOdds,
    spreadAwayOdds: spAwayOdds,
    spreadHomeLine: spHomeLine,
    spreadAwayLine: spAwayLine,
    asianHandicap: ah,
    bookmaker: bookTitle,
    mlBookmaker: bookTitle,
    ouBookmaker: bookTitle,
    spreadBookmaker: bookTitle,
    ahBookmaker: bookTitle,
  );
  return odds.hasAny ? odds : null;
}

/// Un event /odds -> BettingMatch (avec MatchOdds inline). Null si sport
/// non gere par l'UI ou event invalide.
BettingMatch? matchFromOddsEvent(Map<String, dynamic> event) {
  final id = event['id']?.toString();
  final sportKey = event['sport_key']?.toString();
  final sport = sportFromKey(sportKey);
  final home = event['home_team']?.toString();
  final away = event['away_team']?.toString();
  if (id == null || sport == null || home == null || away == null) return null;

  final book = pickPrimaryBookmaker(event['bookmakers']);
  final odds = oddsFromBookmaker(book, home, away, sport);

  return BettingMatch(
    id: oddsApiInternalId(id),
    sport: sport,
    leagueId: sportKey,
    homeName: home,
    awayName: away,
    league: event['sport_title']?.toString() ?? '',
    startTime: _parseTime(event['commence_time']),
    isLive: false,
    odds: odds,
  );
}

/// Liste d'events /odds -> BettingMatch (filtre les non geres).
List<BettingMatch> mapOddsEvents(dynamic eventsRaw) {
  if (eventsRaw is! List) return const [];
  final out = <BettingMatch>[];
  for (final e in eventsRaw) {
    if (e is! Map) continue;
    final m = matchFromOddsEvent(e.cast<String, dynamic>());
    if (m != null) out.add(m);
  }
  return out;
}

/// Un event /scores -> BettingMatch (scores live). Null si sport non gere.
/// isLive = a un score ET pas termine. Les scores sont matches par NOM.
BettingMatch? matchFromScoreEvent(Map<String, dynamic> event) {
  final id = event['id']?.toString();
  final sport = sportFromKey(event['sport_key']?.toString());
  final home = event['home_team']?.toString();
  final away = event['away_team']?.toString();
  if (id == null || sport == null || home == null || away == null) return null;

  int? homeScore, awayScore;
  final scores = event['scores'];
  if (scores is List) {
    for (final s in scores) {
      if (s is! Map) continue;
      final name = s['name']?.toString();
      final val = _i(s['score']);
      if (name == home) {
        homeScore = val;
      } else if (name == away) {
        awayScore = val;
      }
    }
  }
  final completed = event['completed'] == true;
  final hasScore = homeScore != null || awayScore != null;

  return BettingMatch(
    id: oddsApiInternalId(id),
    sport: sport,
    leagueId: event['sport_key']?.toString(),
    homeName: home,
    awayName: away,
    league: event['sport_title']?.toString() ?? '',
    startTime: _parseTime(event['commence_time']),
    isLive: hasScore && !completed,
    homeScore: homeScore,
    awayScore: awayScore,
  );
}

/// Liste d'events /scores -> BettingMatch. Si [liveOnly], ne garde que les
/// matchs en cours (score present & non termine).
List<BettingMatch> mapScoreEvents(dynamic eventsRaw, {bool liveOnly = true}) {
  if (eventsRaw is! List) return const [];
  final out = <BettingMatch>[];
  for (final e in eventsRaw) {
    if (e is! Map) continue;
    final m = matchFromScoreEvent(e.cast<String, dynamic>());
    if (m == null) continue;
    if (liveOnly && !m.isLive) continue;
    out.add(m);
  }
  return out;
}

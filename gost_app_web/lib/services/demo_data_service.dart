// ============================================================
// Plugbet – Données de démonstration
// Se déclenche automatiquement quand l'API est inaccessible
// Avec les vrais logos SVG de football-data.org
// ============================================================

import '../models/football_models.dart';

class DemoDataService {
  /// Génère des matchs de démo réalistes avec vrais logos
  static List<FootballMatch> generateDemoMatches() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return [
      // === MATCHS EN DIRECT ===
      _createMatch(
        id: 90001,
        competition: _premierLeague,
        home: _liverpool,
        away: _arsenal,
        homeScore: 2,
        awayScore: 1,
        status: 'IN_PLAY',
        minute: 67,
        date: now.subtract(const Duration(minutes: 67)),
        matchday: 24,
      ),
      _createMatch(
        id: 90002,
        competition: _laLiga,
        home: _barcelona,
        away: _realMadrid,
        homeScore: 1,
        awayScore: 1,
        status: 'IN_PLAY',
        minute: 34,
        date: now.subtract(const Duration(minutes: 34)),
        matchday: 22,
      ),
      _createMatch(
        id: 90003,
        competition: _serieA,
        home: _napoli,
        away: _inter,
        homeScore: 0,
        awayScore: 0,
        status: 'PAUSED',
        minute: 45,
        date: now.subtract(const Duration(minutes: 48)),
        matchday: 23,
      ),

      // === MATCHS À VENIR ===
      _createMatch(
        id: 90004,
        competition: _premierLeague,
        home: _manCity,
        away: _manUnited,
        homeScore: null,
        awayScore: null,
        status: 'TIMED',
        date: today.add(const Duration(hours: 17, minutes: 30)),
        matchday: 24,
      ),
      _createMatch(
        id: 90005,
        competition: _ligue1,
        home: _psg,
        away: _marseille,
        homeScore: null,
        awayScore: null,
        status: 'TIMED',
        date: today.add(const Duration(hours: 20, minutes: 45)),
        matchday: 22,
      ),
      _createMatch(
        id: 90006,
        competition: _bundesliga,
        home: _bayern,
        away: _dortmund,
        homeScore: null,
        awayScore: null,
        status: 'TIMED',
        date: today.add(const Duration(hours: 18, minutes: 30)),
        matchday: 20,
      ),
      _createMatch(
        id: 90007,
        competition: _championsLeague,
        home: _liverpool,
        away: _barcelona,
        homeScore: null,
        awayScore: null,
        status: 'TIMED',
        date: today.add(const Duration(days: 1, hours: 21)),
        matchday: 7,
      ),

      // === MATCHS TERMINÉS ===
      _createMatch(
        id: 90008,
        competition: _premierLeague,
        home: _chelsea,
        away: _tottenham,
        homeScore: 3,
        awayScore: 1,
        status: 'FINISHED',
        date: today.subtract(const Duration(hours: 4)),
        matchday: 24,
      ),
      _createMatch(
        id: 90009,
        competition: _laLiga,
        home: _athletic,
        away: _atletico,
        homeScore: 0,
        awayScore: 2,
        status: 'FINISHED',
        date: today.subtract(const Duration(hours: 6)),
        matchday: 22,
      ),
      _createMatch(
        id: 90010,
        competition: _serieA,
        home: _juventus,
        away: _milan,
        homeScore: 2,
        awayScore: 2,
        status: 'FINISHED',
        date: today.subtract(const Duration(hours: 3)),
        matchday: 23,
      ),
    ];
  }

  /// Génère des événements de démo pour un match
  static List<MatchEvent> generateDemoEvents(int matchId) {
    switch (matchId) {
      case 90001: // Liverpool 2-1 Arsenal
        return [
          MatchEvent(minute: 12, type: 'GOAL', playerName: 'M. Salah', teamName: 'Liverpool FC', isHomeTeam: true, assistPlayerName: 'T. Alexander-Arnold'),
          MatchEvent(minute: 23, type: 'BOOKING', playerName: 'D. Rice', teamName: 'Arsenal FC', isHomeTeam: false),
          MatchEvent(minute: 31, type: 'GOAL', playerName: 'B. Saka', teamName: 'Arsenal FC', isHomeTeam: false, assistPlayerName: 'M. Ødegaard'),
          MatchEvent(minute: 45, type: 'BOOKING', playerName: 'A. Mac Allister', teamName: 'Liverpool FC', isHomeTeam: true),
          MatchEvent(minute: 58, type: 'GOAL', playerName: 'C. Gakpo', teamName: 'Liverpool FC', isHomeTeam: true, assistPlayerName: 'M. Salah'),
          MatchEvent(minute: 62, type: 'SUBSTITUTION', playerName: 'D. Núñez', teamName: 'Liverpool FC', isHomeTeam: true, detail: 'Remplace L. Díaz'),
        ];
      case 90002: // Barcelona 1-1 Real Madrid
        return [
          MatchEvent(minute: 8, type: 'GOAL', playerName: 'R. Lewandowski', teamName: 'FC Barcelona', isHomeTeam: true, assistPlayerName: 'Pedri'),
          MatchEvent(minute: 18, type: 'BOOKING', playerName: 'Pedri', teamName: 'FC Barcelona', isHomeTeam: true),
          MatchEvent(minute: 27, type: 'GOAL', playerName: 'Vinícius Júnior', teamName: 'Real Madrid CF', isHomeTeam: false, assistPlayerName: 'J. Bellingham'),
        ];
      case 90008: // Chelsea 3-1 Tottenham
        return [
          MatchEvent(minute: 15, type: 'GOAL', playerName: 'C. Palmer', teamName: 'Chelsea FC', isHomeTeam: true),
          MatchEvent(minute: 28, type: 'GOAL', playerName: 'Son Heung-min', teamName: 'Tottenham', isHomeTeam: false, assistPlayerName: 'J. Maddison'),
          MatchEvent(minute: 34, type: 'BOOKING', playerName: 'C. Romero', teamName: 'Tottenham', isHomeTeam: false),
          MatchEvent(minute: 52, type: 'GOAL', playerName: 'N. Jackson', teamName: 'Chelsea FC', isHomeTeam: true, assistPlayerName: 'C. Palmer'),
          MatchEvent(minute: 67, type: 'DISMISSAL', playerName: 'C. Romero', teamName: 'Tottenham', isHomeTeam: false, detail: 'Second Yellow'),
          MatchEvent(minute: 78, type: 'GOAL', playerName: 'C. Palmer', teamName: 'Chelsea FC', isHomeTeam: true, assistPlayerName: 'M. Mudryk'),
          MatchEvent(minute: 80, type: 'SUBSTITUTION', playerName: 'M. Gusto', teamName: 'Chelsea FC', isHomeTeam: true, detail: 'Remplace R. James'),
        ];
      case 90009: // Athletic 0-2 Atletico
        return [
          MatchEvent(minute: 22, type: 'GOAL', playerName: 'A. Griezmann', teamName: 'Atlético Madrid', isHomeTeam: false, assistPlayerName: 'Á. Correa'),
          MatchEvent(minute: 55, type: 'BOOKING', playerName: 'Iñaki Williams', teamName: 'Athletic Club', isHomeTeam: true),
          MatchEvent(minute: 71, type: 'GOAL', playerName: 'J. Álvarez', teamName: 'Atlético Madrid', isHomeTeam: false),
        ];
      case 90010: // Juventus 2-2 Milan
        return [
          MatchEvent(minute: 11, type: 'GOAL', playerName: 'D. Vlahović', teamName: 'Juventus', isHomeTeam: true),
          MatchEvent(minute: 33, type: 'GOAL', playerName: 'R. Leão', teamName: 'AC Milan', isHomeTeam: false, assistPlayerName: 'T. Hernández'),
          MatchEvent(minute: 44, type: 'BOOKING', playerName: 'M. Locatelli', teamName: 'Juventus', isHomeTeam: true),
          MatchEvent(minute: 56, type: 'GOAL', playerName: 'C. Pulisic', teamName: 'AC Milan', isHomeTeam: false),
          MatchEvent(minute: 82, type: 'GOAL', playerName: 'T. Weah', teamName: 'Juventus', isHomeTeam: true, assistPlayerName: 'F. Chiesa'),
        ];
      default:
        return [];
    }
  }

  /// Génère des stats de démo pour un match
  static MatchStats? generateDemoStats(int matchId) {
    switch (matchId) {
      case 90001:
        return MatchStats(homePossession: 58, awayPossession: 42, homeShots: 14, awayShots: 9, homeShotsOnTarget: 6, awayShotsOnTarget: 4, homeCorners: 7, awayCorners: 3, homeFouls: 11, awayFouls: 14, homeXg: 1.8, awayXg: 1.1);
      case 90002:
        return MatchStats(homePossession: 62, awayPossession: 38, homeShots: 8, awayShots: 6, homeShotsOnTarget: 3, awayShotsOnTarget: 3, homeCorners: 5, awayCorners: 2, homeFouls: 8, awayFouls: 10, homeXg: 0.9, awayXg: 0.7);
      case 90003:
        return MatchStats(homePossession: 51, awayPossession: 49, homeShots: 5, awayShots: 4, homeShotsOnTarget: 1, awayShotsOnTarget: 2, homeCorners: 3, awayCorners: 2, homeFouls: 6, awayFouls: 7);
      case 90008:
        return MatchStats(homePossession: 55, awayPossession: 45, homeShots: 18, awayShots: 8, homeShotsOnTarget: 8, awayShotsOnTarget: 3, homeCorners: 9, awayCorners: 4, homeFouls: 10, awayFouls: 16, homeXg: 2.5, awayXg: 0.9);
      case 90009:
        return MatchStats(homePossession: 53, awayPossession: 47, homeShots: 10, awayShots: 12, homeShotsOnTarget: 2, awayShotsOnTarget: 5, homeCorners: 5, awayCorners: 6, homeFouls: 15, awayFouls: 11, homeXg: 0.8, awayXg: 1.6);
      case 90010:
        return MatchStats(homePossession: 48, awayPossession: 52, homeShots: 12, awayShots: 15, homeShotsOnTarget: 5, awayShotsOnTarget: 6, homeCorners: 6, awayCorners: 7, homeFouls: 13, awayFouls: 12, homeXg: 1.5, awayXg: 1.7);
      default:
        return null;
    }
  }

  // === Compétitions ===
  static final _premierLeague = Competition(id: 2021, name: 'Premier League', code: 'PL', areaName: 'England', emblemUrl: 'https://crests.football-data.org/PL.png');
  static final _laLiga = Competition(id: 2014, name: 'La Liga', code: 'PD', areaName: 'Spain', emblemUrl: 'https://crests.football-data.org/PD.png');
  static final _bundesliga = Competition(id: 2002, name: 'Bundesliga', code: 'BL1', areaName: 'Germany', emblemUrl: 'https://crests.football-data.org/BL1.png');
  static final _serieA = Competition(id: 2019, name: 'Serie A', code: 'SA', areaName: 'Italy', emblemUrl: 'https://crests.football-data.org/SA.png');
  static final _ligue1 = Competition(id: 2015, name: 'Ligue 1', code: 'FL1', areaName: 'France', emblemUrl: 'https://crests.football-data.org/FL1.png');
  static final _championsLeague = Competition(id: 2001, name: 'UEFA Champions League', code: 'CL', areaName: 'Europe', emblemUrl: 'https://crests.football-data.org/CL.png');

  // === Équipes avec logos PNG depuis Wikimedia (accessibles partout) ===
  static const _wk = 'https://upload.wikimedia.org/wikipedia';
  static final _liverpool = Team(id: 64, name: 'Liverpool FC', shortName: 'Liverpool', tla: 'LIV', crestUrl: '$_wk/en/thumb/0/0c/Liverpool_FC.svg/180px-Liverpool_FC.svg.png');
  static final _arsenal = Team(id: 57, name: 'Arsenal FC', shortName: 'Arsenal', tla: 'ARS', crestUrl: '$_wk/en/thumb/5/53/Arsenal_FC.svg/180px-Arsenal_FC.svg.png');
  static final _barcelona = Team(id: 81, name: 'FC Barcelona', shortName: 'Barcelona', tla: 'BAR', crestUrl: '$_wk/en/thumb/4/47/FC_Barcelona_%28crest%29.svg/180px-FC_Barcelona_%28crest%29.svg.png');
  static final _realMadrid = Team(id: 86, name: 'Real Madrid CF', shortName: 'Real Madrid', tla: 'RMA', crestUrl: '$_wk/en/thumb/5/56/Real_Madrid_CF.svg/180px-Real_Madrid_CF.svg.png');
  static final _napoli = Team(id: 113, name: 'SSC Napoli', shortName: 'Napoli', tla: 'NAP', crestUrl: '$_wk/commons/thumb/2/27/SSC_Neapel.svg/180px-SSC_Neapel.svg.png');
  static final _inter = Team(id: 108, name: 'FC Internazionale Milano', shortName: 'Inter', tla: 'INT', crestUrl: '$_wk/commons/thumb/0/05/FC_Internazionale_Milano_2021.svg/180px-FC_Internazionale_Milano_2021.svg.png');
  static final _manCity = Team(id: 65, name: 'Manchester City FC', shortName: 'Man City', tla: 'MCI', crestUrl: '$_wk/en/thumb/e/eb/Manchester_City_FC_badge.svg/180px-Manchester_City_FC_badge.svg.png');
  static final _manUnited = Team(id: 66, name: 'Manchester United FC', shortName: 'Man United', tla: 'MUN', crestUrl: '$_wk/en/thumb/7/7a/Manchester_United_FC_crest.svg/180px-Manchester_United_FC_crest.svg.png');
  static final _psg = Team(id: 524, name: 'Paris Saint-Germain FC', shortName: 'PSG', tla: 'PSG', crestUrl: '$_wk/en/thumb/a/a7/Paris_Saint-Germain_F.C..svg/180px-Paris_Saint-Germain_F.C..svg.png');
  static final _marseille = Team(id: 516, name: 'Olympique de Marseille', shortName: 'Marseille', tla: 'OM', crestUrl: '$_wk/commons/thumb/d/d8/Olympique_Marseille_logo.svg/180px-Olympique_Marseille_logo.svg.png');
  static final _bayern = Team(id: 5, name: 'FC Bayern München', shortName: 'Bayern', tla: 'BAY', crestUrl: '$_wk/commons/thumb/1/1b/FC_Bayern_M%C3%BCnchen_logo_%282017%29.svg/180px-FC_Bayern_M%C3%BCnchen_logo_%282017%29.svg.png');
  static final _dortmund = Team(id: 4, name: 'Borussia Dortmund', shortName: 'Dortmund', tla: 'BVB', crestUrl: '$_wk/commons/thumb/6/67/Borussia_Dortmund_logo.svg/180px-Borussia_Dortmund_logo.svg.png');
  static final _chelsea = Team(id: 61, name: 'Chelsea FC', shortName: 'Chelsea', tla: 'CHE', crestUrl: '$_wk/en/thumb/c/cc/Chelsea_FC.svg/180px-Chelsea_FC.svg.png');
  static final _tottenham = Team(id: 73, name: 'Tottenham Hotspur FC', shortName: 'Tottenham', tla: 'TOT', crestUrl: '$_wk/en/thumb/b/b4/Tottenham_Hotspur.svg/180px-Tottenham_Hotspur.svg.png');
  static final _athletic = Team(id: 77, name: 'Athletic Club', shortName: 'Athletic', tla: 'ATH', crestUrl: '$_wk/en/thumb/9/98/Club_Athletic_Bilbao_logo.svg/180px-Club_Athletic_Bilbao_logo.svg.png');
  static final _atletico = Team(id: 78, name: 'Club Atlético de Madrid', shortName: 'Atlético', tla: 'ATM', crestUrl: '$_wk/en/thumb/f/f4/Atletico_Madrid_2017_logo.svg/180px-Atletico_Madrid_2017_logo.svg.png');
  static final _juventus = Team(id: 109, name: 'Juventus FC', shortName: 'Juventus', tla: 'JUV', crestUrl: '$_wk/commons/thumb/a/a8/Juventus_FC_-_pictogram.svg/180px-Juventus_FC_-_pictogram.svg.png');
  static final _milan = Team(id: 98, name: 'AC Milan', shortName: 'Milan', tla: 'MIL', crestUrl: '$_wk/commons/thumb/d/d0/Logo_of_AC_Milan.svg/180px-Logo_of_AC_Milan.svg.png');

  static FootballMatch _createMatch({
    required int id,
    required Competition competition,
    required Team home,
    required Team away,
    int? homeScore,
    int? awayScore,
    required String status,
    int? minute,
    required DateTime date,
    int? matchday,
  }) {
    return FootballMatch(
      id: id,
      competition: competition,
      homeTeam: home,
      awayTeam: away,
      score: Score(
        homeFullTime: homeScore,
        awayFullTime: awayScore,
        homeHalfTime: status == 'FINISHED' || status == 'PAUSED'
            ? (homeScore != null ? (homeScore ~/ 2) : null)
            : null,
        awayHalfTime: status == 'FINISHED' || status == 'PAUSED'
            ? (awayScore != null ? (awayScore ~/ 2) : null)
            : null,
      ),
      statusStr: status,
      utcDate: date.toUtc().toIso8601String(),
      matchday: matchday,
      minute: minute,
      lastUpdated: DateTime.now(),
    );
  }
}

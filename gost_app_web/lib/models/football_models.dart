// ============================================================
// Plugbet – Modèles de données
// Mapping JSON de football-data.org (v4) + cache Hive
// ============================================================

import 'package:hive/hive.dart';

part 'football_models.g.dart';

// --- Statuts possibles d'un match ---
enum MatchStatus {
  scheduled,    // Programmé
  timed,        // Heure confirmée
  inPlay,       // En cours
  paused,       // Mi-temps
  finished,     // Terminé
  suspended,    // Suspendu
  postponed,    // Reporté
  cancelled,    // Annulé
  awarded,      // Attribué
  unknown;      // Inconnu

  /// Convertit la chaîne API en enum
  static MatchStatus fromString(String? status) {
    switch (status?.toUpperCase()) {
      case 'SCHEDULED': return MatchStatus.scheduled;
      case 'TIMED': return MatchStatus.timed;
      case 'IN_PLAY': return MatchStatus.inPlay;
      case 'PAUSED': return MatchStatus.paused;
      case 'FINISHED': return MatchStatus.finished;
      case 'SUSPENDED': return MatchStatus.suspended;
      case 'POSTPONED': return MatchStatus.postponed;
      case 'CANCELLED': return MatchStatus.cancelled;
      case 'AWARDED': return MatchStatus.awarded;
      default: return MatchStatus.unknown;
    }
  }

  /// Indique si le match est "live" (en jeu ou en pause)
  bool get isLive => this == inPlay || this == paused;

  /// Indique si le match est à venir
  bool get isUpcoming => this == scheduled || this == timed;

  /// Label lisible
  String get label {
    switch (this) {
      case MatchStatus.scheduled: return 'Programmé';
      case MatchStatus.timed: return 'Programmé';
      case MatchStatus.inPlay: return 'EN DIRECT';
      case MatchStatus.paused: return 'MI-TEMPS';
      case MatchStatus.finished: return 'Terminé';
      case MatchStatus.suspended: return 'Suspendu';
      case MatchStatus.postponed: return 'Reporté';
      case MatchStatus.cancelled: return 'Annulé';
      case MatchStatus.awarded: return 'Attribué';
      case MatchStatus.unknown: return 'Inconnu';
    }
  }
}

// ============================================================
// Compétition (Ligue / Coupe)
// ============================================================
@HiveType(typeId: 0)
class Competition {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String? emblemUrl;

  @HiveField(3)
  final String? code;

  @HiveField(4)
  final String? areaName;

  @HiveField(5)
  final String? areaFlag;

  Competition({
    required this.id,
    required this.name,
    this.emblemUrl,
    this.code,
    this.areaName,
    this.areaFlag,
  });

  factory Competition.fromJson(Map<String, dynamic> json) {
    final area = json['area'] as Map<String, dynamic>?;
    return Competition(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Inconnu',
      emblemUrl: json['emblem'],
      code: json['code'],
      areaName: area?['name'],
      areaFlag: area?['flag'],
    );
  }
}

// ============================================================
// Équipe
// ============================================================
@HiveType(typeId: 1)
class Team {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String shortName;

  @HiveField(3)
  final String? crestUrl;

  @HiveField(4)
  final String? tla; // Abréviation 3 lettres (ex: PSG, BAR)

  Team({
    required this.id,
    required this.name,
    required this.shortName,
    this.crestUrl,
    this.tla,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Inconnu',
      shortName: json['shortName'] ?? json['name'] ?? 'INC',
      crestUrl: json['crest'],
      tla: json['tla'],
    );
  }
}

// ============================================================
// Score détaillé
// ============================================================
@HiveType(typeId: 2)
class Score {
  @HiveField(0)
  final int? homeFullTime;

  @HiveField(1)
  final int? awayFullTime;

  @HiveField(2)
  final int? homeHalfTime;

  @HiveField(3)
  final int? awayHalfTime;

  Score({
    this.homeFullTime,
    this.awayFullTime,
    this.homeHalfTime,
    this.awayHalfTime,
  });

  factory Score.fromJson(Map<String, dynamic> json) {
    final fullTime = json['fullTime'] as Map<String, dynamic>?;
    final halfTime = json['halfTime'] as Map<String, dynamic>?;
    return Score(
      homeFullTime: fullTime?['home'],
      awayFullTime: fullTime?['away'],
      homeHalfTime: halfTime?['home'],
      awayHalfTime: halfTime?['away'],
    );
  }

  /// Score affiché (full time si terminé, sinon score actuel)
  String get display {
    final h = homeFullTime ?? 0;
    final a = awayFullTime ?? 0;
    return '$h - $a';
  }
}

// ============================================================
// Match complet
// ============================================================
@HiveType(typeId: 3)
class FootballMatch {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final Competition competition;

  @HiveField(2)
  final Team homeTeam;

  @HiveField(3)
  final Team awayTeam;

  @HiveField(4)
  final Score score;

  @HiveField(5)
  final String statusStr;

  @HiveField(6)
  final String utcDate;

  @HiveField(7)
  final int? matchday;

  @HiveField(8)
  final int? minute;

  @HiveField(9)
  final String? stage;

  @HiveField(10)
  final String? group;

  @HiveField(11)
  final DateTime lastUpdated;

  FootballMatch({
    required this.id,
    required this.competition,
    required this.homeTeam,
    required this.awayTeam,
    required this.score,
    required this.statusStr,
    required this.utcDate,
    this.matchday,
    this.minute,
    this.stage,
    this.group,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  MatchStatus get status => MatchStatus.fromString(statusStr);
  DateTime get dateTime => DateTime.parse(utcDate).toLocal();

  /// Retourne la minute du match (fournie par l'API ou estimée)
  int? get displayMinute {
    // Si l'API fournit la minute, on l'utilise
    if (minute != null) return minute;

    // Sinon, estimation pour les matchs live sans minute fournie
    if (!status.isLive) return null;

    final now = DateTime.now();
    final kickoff = dateTime;
    final elapsed = now.difference(kickoff).inMinutes;

    // Si le match n'a pas encore commencé, pas de minute
    if (elapsed < 0) return null;

    // Estimation simple : on suppose que le match est en cours
    // Limitation à 90+ pour rester réaliste
    if (elapsed > 105) return 90; // Affiche 90' au lieu de 120'
    return elapsed.clamp(0, 90);
  }

  /// Copie avec mise à jour partielle
  FootballMatch copyWith({
    Score? score,
    String? statusStr,
    int? minute,
  }) {
    return FootballMatch(
      id: id,
      competition: competition,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      score: score ?? this.score,
      statusStr: statusStr ?? this.statusStr,
      utcDate: utcDate,
      matchday: matchday,
      minute: minute ?? this.minute,
      stage: stage,
      group: group,
      lastUpdated: DateTime.now(),
    );
  }

  factory FootballMatch.fromJson(Map<String, dynamic> json) {
    return FootballMatch(
      id: json['id'] ?? 0,
      competition: Competition.fromJson(json['competition'] ?? {}),
      homeTeam: Team.fromJson(json['homeTeam'] ?? {}),
      awayTeam: Team.fromJson(json['awayTeam'] ?? {}),
      score: Score.fromJson(json['score'] ?? {}),
      statusStr: json['status'] ?? 'UNKNOWN',
      utcDate: json['utcDate'] ?? DateTime.now().toIso8601String(),
      matchday: json['matchday'],
      minute: json['minute'],
      stage: json['stage'],
      group: json['group'],
      lastUpdated: DateTime.now(),
    );
  }
}

// ============================================================
// Événement de match (but, carton, remplacement, VAR)
// ============================================================
enum EventType {
  goal,
  yellowCard,
  redCard,
  substitution,
  varDecision,
  penalty,
  ownGoal,
  unknown;

  static EventType fromString(String? type, String? detail) {
    switch (type?.toUpperCase()) {
      case 'GOAL':
        if (detail?.toUpperCase().contains('OWN') == true) return EventType.ownGoal;
        if (detail?.toUpperCase().contains('PENALTY') == true) return EventType.penalty;
        return EventType.goal;
      case 'YELLOW_CARD':
      case 'BOOKING':
        return EventType.yellowCard;
      case 'RED_CARD':
      case 'DISMISSAL':
        if (detail?.toUpperCase().contains('YELLOW') == true) return EventType.yellowCard;
        return EventType.redCard;
      case 'SUBSTITUTION':
        return EventType.substitution;
      case 'VAR':
        return EventType.varDecision;
      default:
        return EventType.unknown;
    }
  }
}

@HiveType(typeId: 4)
class MatchEvent {
  @HiveField(0)
  final int minute;

  @HiveField(1)
  final String type;

  @HiveField(2)
  final String? detail;

  @HiveField(3)
  final String? playerName;

  @HiveField(4)
  final String? teamName;

  @HiveField(5)
  final bool isHomeTeam;

  @HiveField(6)
  final String? assistPlayerName;

  MatchEvent({
    required this.minute,
    required this.type,
    this.detail,
    this.playerName,
    this.teamName,
    required this.isHomeTeam,
    this.assistPlayerName,
  });

  EventType get eventType => EventType.fromString(type, detail);

  factory MatchEvent.fromJson(Map<String, dynamic> json, {bool isHome = true}) {
    return MatchEvent(
      minute: json['minute'] ?? 0,
      type: json['type'] ?? 'UNKNOWN',
      detail: json['detail'],
      playerName: json['player']?['name'],
      teamName: json['team']?['name'],
      isHomeTeam: isHome,
      assistPlayerName: json['assist']?['name'],
    );
  }
}

// ============================================================
// Statistiques de match
// ============================================================
@HiveType(typeId: 5)
class MatchStats {
  @HiveField(0)
  final int? homePossession;

  @HiveField(1)
  final int? awayPossession;

  @HiveField(2)
  final int? homeShots;

  @HiveField(3)
  final int? awayShots;

  @HiveField(4)
  final int? homeShotsOnTarget;

  @HiveField(5)
  final int? awayShotsOnTarget;

  @HiveField(6)
  final int? homeCorners;

  @HiveField(7)
  final int? awayCorners;

  @HiveField(8)
  final int? homeFouls;

  @HiveField(9)
  final int? awayFouls;

  @HiveField(10)
  final double? homeXg;

  @HiveField(11)
  final double? awayXg;

  MatchStats({
    this.homePossession,
    this.awayPossession,
    this.homeShots,
    this.awayShots,
    this.homeShotsOnTarget,
    this.awayShotsOnTarget,
    this.homeCorners,
    this.awayCorners,
    this.homeFouls,
    this.awayFouls,
    this.homeXg,
    this.awayXg,
  });
}

// ============================================================
// Joueur (pour compositions)
// ============================================================
@HiveType(typeId: 6)
class Player {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int? shirtNumber;

  @HiveField(3)
  final String? position;

  Player({
    required this.id,
    required this.name,
    this.shirtNumber,
    this.position,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Inconnu',
      shirtNumber: json['shirtNumber'],
      position: json['position'],
    );
  }
}

// ============================================================
// Lineup (composition d'équipe)
// ============================================================
@HiveType(typeId: 7)
class Lineup {
  @HiveField(0)
  final String? formation;

  @HiveField(1)
  final List<Player> startingXI;

  @HiveField(2)
  final List<Player> substitutes;

  @HiveField(3)
  final String? coach;

  Lineup({
    this.formation,
    required this.startingXI,
    required this.substitutes,
    this.coach,
  });
}

// ============================================================
// Détail complet d'un match (events + stats + compositions)
// Non-persisté en Hive, chargé à la demande dans le detail screen
// ============================================================
class MatchDetailData {
  final List<MatchEvent> events;
  final MatchStats? stats;
  final Lineup? homeLineup;
  final Lineup? awayLineup;

  const MatchDetailData({
    this.events = const [],
    this.stats,
    this.homeLineup,
    this.awayLineup,
  });

  bool get hasEvents => events.isNotEmpty;
  bool get hasLineups => homeLineup != null || awayLineup != null;
  bool get hasStats =>
      stats != null &&
      (stats!.homePossession != null ||
          stats!.homeShots != null ||
          stats!.homeCorners != null);
}

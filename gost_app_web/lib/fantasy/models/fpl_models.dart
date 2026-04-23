// ============================================================
// FANTASY MODULE – Modèles de données FPL
// Couvre bootstrap-static, live, entry, picks, fixtures
// ============================================================

import 'dart:convert';

// ─── Bootstrap (joueurs, équipes, gameweeks) ───────────────

class FplBootstrap {
  final List<FplElement> elements;
  final List<FplElementType> elementTypes;
  final List<FplTeam> teams;
  final List<FplEvent> events;

  const FplBootstrap({
    required this.elements,
    required this.elementTypes,
    required this.teams,
    required this.events,
  });

  FplEvent? get currentEvent =>
      events.where((e) => e.isCurrent).firstOrNull ??
      events.where((e) => e.isNext).firstOrNull;

  FplEvent? get nextEvent =>
      events.where((e) => e.isNext).firstOrNull;

  FplTeam? teamById(int id) =>
      teams.where((t) => t.id == id).firstOrNull;

  FplElement? elementById(int id) =>
      elements.where((e) => e.id == id).firstOrNull;

  factory FplBootstrap.fromJson(Map<String, dynamic> json) {
    return FplBootstrap(
      elements: (json['elements'] as List? ?? [])
          .map((e) => FplElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      elementTypes: (json['element_types'] as List? ?? [])
          .map((e) => FplElementType.fromJson(e as Map<String, dynamic>))
          .toList(),
      teams: (json['teams'] as List? ?? [])
          .map((e) => FplTeam.fromJson(e as Map<String, dynamic>))
          .toList(),
      events: (json['events'] as List? ?? [])
          .map((e) => FplEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ─── Joueur FPL ───────────────────────────────────────────

class FplElement {
  final int id;
  final String firstName;
  final String secondName;
  final String webName;
  final int teamId;
  final int elementType; // 1=GK, 2=DEF, 3=MID, 4=FWD
  final int nowCost;     // /10 = £M
  final int totalPoints;
  final String form;
  final String selectedByPercent;
  final String? news;
  final int chanceOfPlayingNextRound;
  final int epThis;
  final int epNext;
  final int transfersIn;
  final int transfersOut;
  final int minutes;
  final int goalsScored;
  final int assists;
  final int cleanSheets;
  final int yellowCards;
  final int redCards;
  final int bonus;
  final String pointsPerGame;

  const FplElement({
    required this.id,
    required this.firstName,
    required this.secondName,
    required this.webName,
    required this.teamId,
    required this.elementType,
    required this.nowCost,
    required this.totalPoints,
    required this.form,
    required this.selectedByPercent,
    this.news,
    required this.chanceOfPlayingNextRound,
    required this.epThis,
    required this.epNext,
    required this.transfersIn,
    required this.transfersOut,
    required this.minutes,
    required this.goalsScored,
    required this.assists,
    required this.cleanSheets,
    required this.yellowCards,
    required this.redCards,
    required this.bonus,
    required this.pointsPerGame,
  });

  /// Prix en FCFA de l'app (now_cost × 10, ex: 45 → 450 FCFA)
  int get coinsValue => nowCost * 10;
  /// Ancien getter conservé pour compatibilité interne
  double get costInMillions => nowCost / 10.0;
  String get displayName => webName;
  String get positionLabel {
    switch (elementType) {
      case 1: return 'GK';
      case 2: return 'DEF';
      case 3: return 'MID';
      case 4: return 'FWD';
      default: return '?';
    }
  }

  factory FplElement.fromJson(Map<String, dynamic> json) {
    return FplElement(
      id: json['id'] as int,
      firstName: json['first_name'] as String? ?? '',
      secondName: json['second_name'] as String? ?? '',
      webName: json['web_name'] as String? ?? '',
      teamId: json['team'] as int? ?? 0,
      elementType: json['element_type'] as int? ?? 0,
      nowCost: json['now_cost'] as int? ?? 0,
      totalPoints: json['total_points'] as int? ?? 0,
      form: json['form'] as String? ?? '0.0',
      selectedByPercent: json['selected_by_percent'] as String? ?? '0.0',
      news: json['news'] as String?,
      chanceOfPlayingNextRound: json['chance_of_playing_next_round'] as int? ?? 100,
      epThis: ((json['ep_this'] as String?) ?? '0').isNotEmpty
          ? double.tryParse(json['ep_this'] as String? ?? '0')?.toInt() ?? 0
          : 0,
      epNext: ((json['ep_next'] as String?) ?? '0').isNotEmpty
          ? double.tryParse(json['ep_next'] as String? ?? '0')?.toInt() ?? 0
          : 0,
      transfersIn: json['transfers_in_event'] as int? ?? 0,
      transfersOut: json['transfers_out_event'] as int? ?? 0,
      minutes: json['minutes'] as int? ?? 0,
      goalsScored: json['goals_scored'] as int? ?? 0,
      assists: json['assists'] as int? ?? 0,
      cleanSheets: json['clean_sheets'] as int? ?? 0,
      yellowCards: json['yellow_cards'] as int? ?? 0,
      redCards: json['red_cards'] as int? ?? 0,
      bonus: json['bonus'] as int? ?? 0,
      pointsPerGame: json['points_per_game'] as String? ?? '0.0',
    );
  }
}

// ─── Type de position ─────────────────────────────────────

class FplElementType {
  final int id;
  final String singularName;
  final String singularNameShort;
  final int squadSelect;
  final int squadMinPlay;
  final int squadMaxPlay;

  const FplElementType({
    required this.id,
    required this.singularName,
    required this.singularNameShort,
    required this.squadSelect,
    required this.squadMinPlay,
    required this.squadMaxPlay,
  });

  factory FplElementType.fromJson(Map<String, dynamic> json) {
    return FplElementType(
      id: json['id'] as int,
      singularName: json['singular_name'] as String? ?? '',
      singularNameShort: json['singular_name_short'] as String? ?? '',
      squadSelect: json['squad_select'] as int? ?? 0,
      squadMinPlay: json['squad_min_play'] as int? ?? 0,
      squadMaxPlay: json['squad_max_play'] as int? ?? 0,
    );
  }
}

// ─── Équipe Premier League ────────────────────────────────

class FplTeam {
  final int id;
  final int code;
  final String name;
  final String shortName;
  final int strength;
  final int strengthAttackHome;
  final int strengthAttackAway;
  final int strengthDefenceHome;
  final int strengthDefenceAway;

  const FplTeam({
    required this.id,
    required this.code,
    required this.name,
    required this.shortName,
    required this.strength,
    required this.strengthAttackHome,
    required this.strengthAttackAway,
    required this.strengthDefenceHome,
    required this.strengthDefenceAway,
  });

  factory FplTeam.fromJson(Map<String, dynamic> json) {
    return FplTeam(
      id: json['id'] as int,
      code: json['code'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      shortName: json['short_name'] as String? ?? '',
      strength: json['strength'] as int? ?? 3,
      strengthAttackHome: json['strength_attack_home'] as int? ?? 1100,
      strengthAttackAway: json['strength_attack_away'] as int? ?? 1100,
      strengthDefenceHome: json['strength_defence_home'] as int? ?? 1100,
      strengthDefenceAway: json['strength_defence_away'] as int? ?? 1100,
    );
  }
}

// ─── Gameweek ─────────────────────────────────────────────

class FplEvent {
  final int id;
  final String name;
  final DateTime? deadlineTime;
  final bool finished;
  final bool isCurrent;
  final bool isNext;
  final bool isPrevious;
  final int? topElementPoints;
  final int averageEntryScore;
  final int? highestScoringEntry;

  const FplEvent({
    required this.id,
    required this.name,
    this.deadlineTime,
    required this.finished,
    required this.isCurrent,
    required this.isNext,
    required this.isPrevious,
    this.topElementPoints,
    required this.averageEntryScore,
    this.highestScoringEntry,
  });

  bool get isLive => isCurrent && !finished;

  Duration? get timeToDeadline {
    if (deadlineTime == null) return null;
    final diff = deadlineTime!.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  factory FplEvent.fromJson(Map<String, dynamic> json) {
    return FplEvent(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      deadlineTime: json['deadline_time'] != null
          ? DateTime.tryParse(json['deadline_time'] as String)
          : null,
      finished: json['finished'] as bool? ?? false,
      isCurrent: json['is_current'] as bool? ?? false,
      isNext: json['is_next'] as bool? ?? false,
      isPrevious: json['is_previous'] as bool? ?? false,
      topElementPoints: json['top_element_stats'] != null
          ? (json['top_element_stats'] as Map?)?.entries.firstOrNull?.value as int?
          : null,
      averageEntryScore: json['average_entry_score'] as int? ?? 0,
      highestScoringEntry: json['highest_scoring_entry'] as int?,
    );
  }
}

// ─── Live GW ──────────────────────────────────────────────

class FplLiveElement {
  final int id;
  final FplLiveStats stats;

  const FplLiveElement({required this.id, required this.stats});

  factory FplLiveElement.fromJson(Map<String, dynamic> json) {
    return FplLiveElement(
      id: json['id'] as int,
      stats: FplLiveStats.fromJson(json['stats'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class FplLiveStats {
  final int minutes;
  final int totalPoints;
  final int goals;
  final int assists;
  final int cleanSheets;
  final int goalsConceded;
  final int ownGoals;
  final int saves;
  final int yellowCards;
  final int redCards;
  final int bonus;
  final int bps;
  final bool inDreamteam;

  const FplLiveStats({
    required this.minutes,
    required this.totalPoints,
    required this.goals,
    required this.assists,
    required this.cleanSheets,
    required this.goalsConceded,
    required this.ownGoals,
    required this.saves,
    required this.yellowCards,
    required this.redCards,
    required this.bonus,
    required this.bps,
    required this.inDreamteam,
  });

  factory FplLiveStats.fromJson(Map<String, dynamic> json) {
    return FplLiveStats(
      minutes: json['minutes'] as int? ?? 0,
      totalPoints: json['total_points'] as int? ?? 0,
      goals: json['goals_scored'] as int? ?? 0,
      assists: json['assists'] as int? ?? 0,
      cleanSheets: json['clean_sheets'] as int? ?? 0,
      goalsConceded: json['goals_conceded'] as int? ?? 0,
      ownGoals: json['own_goals'] as int? ?? 0,
      saves: json['saves'] as int? ?? 0,
      yellowCards: json['yellow_cards'] as int? ?? 0,
      redCards: json['red_cards'] as int? ?? 0,
      bonus: json['bonus'] as int? ?? 0,
      bps: json['bps'] as int? ?? 0,
      inDreamteam: json['in_dreamteam'] as bool? ?? false,
    );
  }
}

// ─── Picks utilisateur ────────────────────────────────────

class FplPick {
  final int elementId;
  final int position;
  final int multiplier;
  final bool isCaptain;
  final bool isViceCaptain;

  const FplPick({
    required this.elementId,
    required this.position,
    required this.multiplier,
    required this.isCaptain,
    required this.isViceCaptain,
  });

  bool get isOnBench => position > 11;

  factory FplPick.fromJson(Map<String, dynamic> json) {
    return FplPick(
      elementId: json['element'] as int,
      position: json['position'] as int? ?? 0,
      multiplier: json['multiplier'] as int? ?? 1,
      isCaptain: json['is_captain'] as bool? ?? false,
      isViceCaptain: json['is_vice_captain'] as bool? ?? false,
    );
  }
}

// ─── Résumé entrée utilisateur ────────────────────────────

class FplEntry {
  final int id;
  final String playerFirstName;
  final String playerLastName;
  final String name;       // nom de l'équipe
  final int overallPoints;
  final int overallRank;
  final int summaryEventPoints;
  final int summaryEventRank;
  final int value;  // FPL unit × 10 = FCFA de l'app
  final int bank;   // FPL unit × 10 = FCFA disponibles

  const FplEntry({
    required this.id,
    required this.playerFirstName,
    required this.playerLastName,
    required this.name,
    required this.overallPoints,
    required this.overallRank,
    required this.summaryEventPoints,
    required this.summaryEventRank,
    required this.value,
    required this.bank,
  });

  /// Valeur totale de l'équipe en coins (× 10 par rapport au FPL)
  int get coinsValue => value * 10;
  /// Coins disponibles pour transferts
  int get coinsBank => bank * 10;

  factory FplEntry.fromJson(Map<String, dynamic> json) {
    return FplEntry(
      id: json['id'] as int,
      playerFirstName: json['player_first_name'] as String? ?? '',
      playerLastName: json['player_last_name'] as String? ?? '',
      name: json['name'] as String? ?? 'Mon Équipe',
      overallPoints: json['summary_overall_points'] as int? ?? 0,
      overallRank: json['summary_overall_rank'] as int? ?? 0,
      summaryEventPoints: json['summary_event_points'] as int? ?? 0,
      summaryEventRank: json['summary_event_rank'] as int? ?? 0,
      value: json['value'] as int? ?? 1000,
      bank: json['bank'] as int? ?? 0,
    );
  }
}

// ─── Résumé joueur (historique + fixtures) ────────────────

class FplElementSummary {
  final List<FplElementHistory> history;
  final List<FplFixture> fixtures;

  const FplElementSummary({required this.history, required this.fixtures});

  factory FplElementSummary.fromJson(Map<String, dynamic> json) {
    return FplElementSummary(
      history: (json['history'] as List? ?? [])
          .map((e) => FplElementHistory.fromJson(e as Map<String, dynamic>))
          .toList(),
      fixtures: (json['fixtures'] as List? ?? [])
          .map((e) => FplFixture.fromJson(e as Map<String, dynamic>))
          .take(5)
          .toList(),
    );
  }
}

class FplElementHistory {
  final int round;
  final int totalPoints;
  final int minutes;
  final int goals;
  final int assists;
  final String opponentShortTitle;
  final bool wasHome;

  const FplElementHistory({
    required this.round,
    required this.totalPoints,
    required this.minutes,
    required this.goals,
    required this.assists,
    required this.opponentShortTitle,
    required this.wasHome,
  });

  factory FplElementHistory.fromJson(Map<String, dynamic> json) {
    return FplElementHistory(
      round: json['round'] as int? ?? 0,
      totalPoints: json['total_points'] as int? ?? 0,
      minutes: json['minutes'] as int? ?? 0,
      goals: json['goals_scored'] as int? ?? 0,
      assists: json['assists'] as int? ?? 0,
      opponentShortTitle: json['opponent_team']?.toString() ?? '',
      wasHome: json['was_home'] as bool? ?? true,
    );
  }
}

class FplFixture {
  final int event;
  final int difficulty;
  final int teamH;
  final int teamA;
  final bool isHome;

  const FplFixture({
    required this.event,
    required this.difficulty,
    required this.teamH,
    required this.teamA,
    required this.isHome,
  });

  factory FplFixture.fromJson(Map<String, dynamic> json) {
    return FplFixture(
      event: json['event'] as int? ?? 0,
      difficulty: json['difficulty'] as int? ?? 3,
      teamH: json['team_h'] as int? ?? 0,
      teamA: json['team_a'] as int? ?? 0,
      isHome: json['is_home'] as bool? ?? true,
    );
  }
}

// ─── État équipe utilisateur (local) ─────────────────────

class FplMyTeam {
  final List<FplPick> picks;
  final int freeTransfers;
  final int chips;

  const FplMyTeam({
    required this.picks,
    required this.freeTransfers,
    required this.chips,
  });

  List<FplPick> get starters => picks.where((p) => !p.isOnBench).toList()
    ..sort((a, b) => a.position.compareTo(b.position));

  List<FplPick> get bench => picks.where((p) => p.isOnBench).toList()
    ..sort((a, b) => a.position.compareTo(b.position));

  FplPick? get captain => picks.where((p) => p.isCaptain).firstOrNull;
  FplPick? get viceCaptain => picks.where((p) => p.isViceCaptain).firstOrNull;

  factory FplMyTeam.fromJson(Map<String, dynamic> json) {
    return FplMyTeam(
      picks: (json['picks'] as List? ?? [])
          .map((e) => FplPick.fromJson(e as Map<String, dynamic>))
          .toList(),
      freeTransfers: json['helper']?['free_transfers'] as int? ??
          json['entry_history']?['event_transfers_cost'] as int? ?? 1,
      chips: 0,
    );
  }

  String toJson() => jsonEncode({
    'picks': picks.map((p) => {
      'element': p.elementId,
      'position': p.position,
      'multiplier': p.multiplier,
      'is_captain': p.isCaptain,
      'is_vice_captain': p.isViceCaptain,
    }).toList(),
    'free_transfers': freeTransfers,
  });

  static FplMyTeam? fromJsonString(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return FplMyTeam.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Penalty Natif — modèles + enums
// ============================================================

enum PenaltyDirection {
  left,
  center,
  right;

  String toJson() => name;

  static PenaltyDirection fromJson(String raw) =>
      PenaltyDirection.values.firstWhere(
        (d) => d.name == raw,
        orElse: () => PenaltyDirection.center,
      );
}

enum PenaltyRoundStatus {
  active,
  won,
  lost,
  abandoned;

  static PenaltyRoundStatus fromJson(String raw) =>
      PenaltyRoundStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => PenaltyRoundStatus.active,
      );

  bool get isFinished => this != PenaltyRoundStatus.active;
}

/// Snapshot d'un round (état serveur).
class PenaltyRound {
  final String id;
  final int betAmount;
  final int totalShots;
  final int goals;
  final int misses;
  final PenaltyRoundStatus status;

  const PenaltyRound({
    required this.id,
    required this.betAmount,
    required this.totalShots,
    required this.goals,
    required this.misses,
    required this.status,
  });

  int get shotsTaken => goals + misses;
  int get shotsRemaining => totalShots - shotsTaken;

  PenaltyRound copyWith({
    int? goals,
    int? misses,
    PenaltyRoundStatus? status,
  }) {
    return PenaltyRound(
      id: id,
      betAmount: betAmount,
      totalShots: totalShots,
      goals: goals ?? this.goals,
      misses: misses ?? this.misses,
      status: status ?? this.status,
    );
  }

  factory PenaltyRound.fromJson(Map<String, dynamic> json) => PenaltyRound(
        id: json['round_id'] as String,
        betAmount: (json['bet_amount'] as num).toInt(),
        totalShots: (json['total_shots'] as num).toInt(),
        goals: (json['goals'] as num?)?.toInt() ?? 0,
        misses: (json['misses'] as num?)?.toInt() ?? 0,
        status: PenaltyRoundStatus.fromJson(json['status'] as String),
      );
}

/// Résultat d'un tir (retour serveur).
class PenaltyShotResult {
  final int shotIndex;
  final PenaltyDirection serverDirection;
  final String outcome; // 'goal' | 'save'
  final int goalsSoFar;
  final int missesSoFar;
  final bool roundFinished;
  final PenaltyRoundStatus roundStatus;
  final int payout;
  final bool idempotent;

  const PenaltyShotResult({
    required this.shotIndex,
    required this.serverDirection,
    required this.outcome,
    required this.goalsSoFar,
    required this.missesSoFar,
    required this.roundFinished,
    required this.roundStatus,
    required this.payout,
    this.idempotent = false,
  });

  bool get isGoal => outcome == 'goal';

  factory PenaltyShotResult.fromJson(Map<String, dynamic> json) =>
      PenaltyShotResult(
        shotIndex: (json['shot_index'] as num).toInt(),
        serverDirection:
            PenaltyDirection.fromJson(json['server_direction'] as String),
        outcome: json['outcome'] as String,
        goalsSoFar: (json['goals_so_far'] as num?)?.toInt() ?? 0,
        missesSoFar: (json['misses_so_far'] as num?)?.toInt() ?? 0,
        roundFinished: (json['round_finished'] as bool?) ?? false,
        roundStatus: PenaltyRoundStatus.fromJson(
            (json['round_status'] as String?) ?? 'active'),
        payout: (json['payout'] as num?)?.toInt() ?? 0,
        idempotent: (json['idempotent'] as bool?) ?? false,
      );
}

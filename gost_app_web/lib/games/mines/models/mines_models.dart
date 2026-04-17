// ============================================================
// Mines — Models
// ============================================================

enum MinesStatus {
  active,
  lost,
  cashedOut;

  static MinesStatus fromString(String s) {
    switch (s) {
      case 'active': return active;
      case 'lost': return lost;
      case 'cashed_out': return cashedOut;
      default: return active;
    }
  }
}

/// Une case revelee par le joueur
class MinesRevealedCell {
  final int position;
  final bool isMine;

  const MinesRevealedCell({
    required this.position,
    required this.isMine,
  });

  factory MinesRevealedCell.fromJson(Map<String, dynamic> json) {
    return MinesRevealedCell(
      position: (json['pos'] as num).toInt(),
      isMine: json['is_mine'] as bool,
    );
  }
}

/// Etat complet d'une session Mines
class MinesSession {
  final String id;
  final String userId;
  final int betAmount;
  final MinesStatus status;
  final int minesCount;
  final int gridSize;
  final int safeRevealedCount;
  final double currentMultiplier;
  final int currentPotentialWin;
  final List<MinesRevealedCell> revealedCells;
  /// Positions des mines, connu seulement apres game over
  final List<int>? minePositions;
  final DateTime createdAt;

  const MinesSession({
    required this.id,
    required this.userId,
    required this.betAmount,
    required this.status,
    required this.minesCount,
    required this.gridSize,
    required this.safeRevealedCount,
    required this.currentMultiplier,
    required this.currentPotentialWin,
    required this.revealedCells,
    this.minePositions,
    required this.createdAt,
  });

  factory MinesSession.fromJson(Map<String, dynamic> json) {
    final revealed = (json['revealed_positions'] as List?)
            ?.map((e) => MinesRevealedCell.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final mines = (json['mine_positions'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList();

    return MinesSession(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      betAmount: (json['bet_amount'] as num).toInt(),
      status: MinesStatus.fromString(json['status'] as String),
      minesCount: (json['mines_count'] as num).toInt(),
      gridSize: (json['grid_size'] as num?)?.toInt() ?? 25,
      safeRevealedCount: (json['safe_revealed_count'] as num).toInt(),
      currentMultiplier: (json['current_multiplier'] as num).toDouble(),
      currentPotentialWin: (json['current_potential_win'] as num).toInt(),
      revealedCells: revealed,
      minePositions: mines,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  bool get isActive => status == MinesStatus.active;
  bool get isLost => status == MinesStatus.lost;
  bool get isCashedOut => status == MinesStatus.cashedOut;
  bool get canCashOut => isActive && safeRevealedCount >= 1;

  /// Multiplicateur suivant si on revele une case de plus
  /// Progression lineaire : 1.50, 2.50, 3.50, 4.50... (+1.00 par case)
  double nextMultiplier() {
    final totalSafe = gridSize - minesCount;
    if (safeRevealedCount >= totalSafe) return currentMultiplier;
    final n = safeRevealedCount + 1;
    return double.parse((0.50 + n * 1.00).toStringAsFixed(2));
  }
}

/// Preset de difficulte
class MinesPreset {
  final String label;
  final int minesCount;
  final String description;

  const MinesPreset({
    required this.label,
    required this.minesCount,
    required this.description,
  });

  static const List<MinesPreset> presets = [
    MinesPreset(label: 'Facile', minesCount: 3, description: '3 mines'),
    MinesPreset(label: 'Moyen', minesCount: 5, description: '5 mines'),
    MinesPreset(label: 'Difficile', minesCount: 10, description: '10 mines'),
    MinesPreset(label: 'Extreme', minesCount: 15, description: '15 mines'),
    MinesPreset(label: 'Suicide', minesCount: 20, description: '20 mines'),
  ];
}

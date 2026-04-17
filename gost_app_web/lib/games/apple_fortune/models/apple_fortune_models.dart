// ============================================================
// Apple of Fortune – Models
// ============================================================

/// Fixed game config: 5 columns, 1 safe (4 dangers), x1.3 per row
enum AppleFortuneDifficulty {
  extreme; // 5 columns, 1 safe, 4 bombs

  int get columns => 5;
  int get safeTiles => 1;
  int get totalRows => 8;
}

/// Status of a game session
enum AppleFortuneStatus {
  active,
  lost,
  cashedOut;

  static AppleFortuneStatus fromString(String s) {
    switch (s) {
      case 'active': return active;
      case 'lost': return lost;
      case 'cashed_out': return cashedOut;
      default: return active;
    }
  }

  String toValue() {
    switch (this) {
      case active: return 'active';
      case lost: return 'lost';
      case cashedOut: return 'cashed_out';
    }
  }
}

/// A single revealed row result
class AppleFortuneRevealedRow {
  final int row;
  final int chosenTile;
  final bool isWin;
  final List<int> safeTiles;

  const AppleFortuneRevealedRow({
    required this.row,
    required this.chosenTile,
    required this.isWin,
    required this.safeTiles,
  });

  factory AppleFortuneRevealedRow.fromJson(Map<String, dynamic> json) {
    return AppleFortuneRevealedRow(
      row: json['row'] as int,
      chosenTile: json['chosen_tile'] as int,
      isWin: json['is_win'] as bool,
      safeTiles: List<int>.from(json['safe_tiles'] as List),
    );
  }
}

/// Full session state from backend
class AppleFortuneSession {
  final String id;
  final String userId;
  final int betAmount;
  final AppleFortuneStatus status;
  final int currentRow;
  final double currentMultiplier;
  final int currentPotentialWin;
  final int columns;
  final int safeTilesPerRow;
  final int totalRows;
  final List<AppleFortuneRevealedRow> revealedRows;
  final DateTime createdAt;

  const AppleFortuneSession({
    required this.id,
    required this.userId,
    required this.betAmount,
    required this.status,
    required this.currentRow,
    required this.currentMultiplier,
    required this.currentPotentialWin,
    required this.columns,
    required this.safeTilesPerRow,
    required this.totalRows,
    required this.revealedRows,
    required this.createdAt,
  });

  factory AppleFortuneSession.fromJson(Map<String, dynamic> json) {
    final revealed = (json['revealed_rows'] as List?)
            ?.map((e) => AppleFortuneRevealedRow.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return AppleFortuneSession(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      betAmount: json['bet_amount'] as int,
      status: AppleFortuneStatus.fromString(json['status'] as String),
      currentRow: json['current_row'] as int,
      currentMultiplier: (json['current_multiplier'] as num).toDouble(),
      currentPotentialWin: json['current_potential_win'] as int,
      columns: json['columns'] as int,
      safeTilesPerRow: json['safe_tiles_per_row'] as int,
      totalRows: json['total_rows'] as int,
      revealedRows: revealed,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isActive => status == AppleFortuneStatus.active;
  bool get isLost => status == AppleFortuneStatus.lost;
  bool get isCashedOut => status == AppleFortuneStatus.cashedOut;
  bool get canCashOut => isActive && currentRow > 0;
  bool get isFinished => currentRow >= totalRows;
}

/// Multiplier table – fixed values, starts at x1.9
class AppleFortuneMultipliers {
  // Row 1=x1.9, Row 2=x3.8, Row 3=x7.6, Row 4=x15, Row 5=x30, Row 6=x60, Row 7=x120, Row 8=x500
  static const List<double> _table = [
    1.9, 3.8, 7.6, 15.0, 30.0, 60.0, 120.0, 500.0,
  ];

  static List<double> buildTable({
    required int totalRows,
    int? columns,
    int? safeTiles,
  }) {
    return _table.sublist(0, totalRows.clamp(0, _table.length));
  }

  /// Get multiplier for a given row (1-indexed: row 1 = first success)
  static double forRow(int row) {
    if (row < 1 || row > _table.length) return 1.0;
    return _table[row - 1];
  }
}

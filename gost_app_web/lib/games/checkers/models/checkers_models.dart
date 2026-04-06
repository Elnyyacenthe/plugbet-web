// ============================================================
// Checkers (Dames) – Modèles de données
// ============================================================

/// Couleur d'un pion
enum PieceColor { red, black }

/// Type de pion
enum PieceType { normal, king }

/// Un pion sur le plateau
class CheckerPiece {
  final PieceColor color;
  PieceType type;

  CheckerPiece({required this.color, this.type = PieceType.normal});

  CheckerPiece copyWith({PieceType? type}) =>
      CheckerPiece(color: color, type: type ?? this.type);

  bool get isKing => type == PieceType.king;

  Map<String, dynamic> toJson() => {
        'color': color.name,
        'type': type.name,
      };

  factory CheckerPiece.fromJson(Map<String, dynamic> j) => CheckerPiece(
        color: PieceColor.values.firstWhere((e) => e.name == j['color']),
        type: PieceType.values.firstWhere((e) => e.name == j['type']),
      );
}

/// Position sur le plateau (0-based)
class BoardPos {
  final int row, col;
  const BoardPos(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      other is BoardPos && other.row == row && other.col == col;
  @override
  int get hashCode => row * 8 + col;

  Map<String, dynamic> toJson() => {'row': row, 'col': col};
  factory BoardPos.fromJson(Map<String, dynamic> j) =>
      BoardPos(j['row'] as int, j['col'] as int);
}

/// Un mouvement possible (inclut les captures)
class CheckerMove {
  final BoardPos from;
  final BoardPos to;
  final List<BoardPos> captured; // positions des pions capturés

  const CheckerMove({
    required this.from,
    required this.to,
    this.captured = const [],
  });

  bool get isCapture => captured.isNotEmpty;
}

/// Statut d'une room Checkers
enum CheckersRoomStatus { waiting, playing, finished, cancelled }

/// Room multijoueur Checkers
class CheckersRoom {
  final String id;
  final String hostId;
  final String hostUsername;
  final int betAmount;
  final bool isPrivate;
  final String? privateCode;
  final CheckersRoomStatus status;
  final String? guestId;
  final String? guestUsername;
  final String? hostColor; // 'red' ou 'black'
  final String? guestColor; // 'red' ou 'black'
  final Map<String, dynamic>? gameStateJson; // état du jeu sérialisé

  CheckersRoom({
    required this.id,
    required this.hostId,
    required this.hostUsername,
    required this.betAmount,
    this.isPrivate = false,
    this.privateCode,
    this.status = CheckersRoomStatus.waiting,
    this.guestId,
    this.guestUsername,
    this.hostColor,
    this.guestColor,
    this.gameStateJson,
  });

  bool get isAI => guestId == 'AI';

  factory CheckersRoom.fromJson(Map<String, dynamic> j) => CheckersRoom(
        id: j['id'] as String,
        hostId: j['host_id'] as String,
        hostUsername: j['host_username'] as String? ?? 'Joueur',
        betAmount: j['bet_amount'] as int? ?? 200,
        isPrivate: j['is_private'] as bool? ?? false,
        privateCode: j['private_code'] as String?,
        status: CheckersRoomStatus.values.firstWhere(
          (e) => e.name == (j['status'] as String? ?? 'waiting'),
          orElse: () => CheckersRoomStatus.waiting,
        ),
        guestId: j['guest_id'] as String?,
        guestUsername: j['guest_username'] as String?,
        hostColor: j['host_color'] as String?,
        guestColor: j['guest_color'] as String?,
        gameStateJson: j['game_state'] is Map<String, dynamic>
            ? j['game_state'] as Map<String, dynamic>
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'host_id': hostId,
        'host_username': hostUsername,
        'bet_amount': betAmount,
        'is_private': isPrivate,
        'private_code': privateCode,
        'status': status.name,
        'guest_id': guestId,
        'guest_username': guestUsername,
        'host_color': hostColor,
        'guest_color': guestColor,
        'game_state': gameStateJson,
      };

  bool get isFull => guestId != null;

  /// Parse le game_state JSON en objet
  CheckersGameState? get gameState {
    if (gameStateJson == null) return null;
    try {
      return CheckersGameState.fromJson(gameStateJson!);
    } catch (_) {
      return null;
    }
  }
}

/// État global d'une partie Checkers (sérialisable pour Supabase)
class CheckersGameState {
  /// Plateau 8x8 : null = vide
  final List<List<CheckerPiece?>> board;
  final PieceColor currentTurn;
  final bool isGameOver;
  final PieceColor? winner;
  final String? winnerUserId;
  final int redCount;
  final int blackCount;

  CheckersGameState({
    required this.board,
    required this.currentTurn,
    this.isGameOver = false,
    this.winner,
    this.winnerUserId,
    required this.redCount,
    required this.blackCount,
  });

  /// Plateau initial standard Checkers
  factory CheckersGameState.initial() {
    final board = List.generate(
      8,
      (r) => List<CheckerPiece?>.generate(8, (c) {
        if ((r + c) % 2 == 1) {
          if (r < 3) return CheckerPiece(color: PieceColor.black);
          if (r > 4) return CheckerPiece(color: PieceColor.red);
        }
        return null;
      }),
    );
    return CheckersGameState(
      board: board,
      currentTurn: PieceColor.red,
      redCount: 12,
      blackCount: 12,
    );
  }

  Map<String, dynamic> toJson() => {
        'board': board
            .map((row) => row.map((p) => p?.toJson()).toList())
            .toList(),
        'currentTurn': currentTurn.name,
        'isGameOver': isGameOver,
        'winner': winner?.name,
        'winnerUserId': winnerUserId,
        'redCount': redCount,
        'blackCount': blackCount,
      };

  factory CheckersGameState.fromJson(Map<String, dynamic> j) {
    final rawBoard = j['board'] as List;
    final board = rawBoard.map((row) {
      return (row as List).map((cell) {
        if (cell == null) return null;
        return CheckerPiece.fromJson(cell as Map<String, dynamic>);
      }).toList();
    }).toList();

    return CheckersGameState(
      board: List<List<CheckerPiece?>>.from(
          board.map((r) => List<CheckerPiece?>.from(r))),
      currentTurn: PieceColor.values.firstWhere(
        (e) => e.name == (j['currentTurn'] as String),
      ),
      isGameOver: j['isGameOver'] as bool? ?? false,
      winner: j['winner'] == null
          ? null
          : PieceColor.values.firstWhere((e) => e.name == j['winner']),
      winnerUserId: j['winnerUserId'] as String?,
      redCount: j['redCount'] as int? ?? 12,
      blackCount: j['blackCount'] as int? ?? 12,
    );
  }
}

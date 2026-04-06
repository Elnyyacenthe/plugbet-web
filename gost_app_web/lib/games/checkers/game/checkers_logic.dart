// ============================================================
// Checkers – Logique de jeu pure (mouvements, IA minimax)
// ============================================================

import '../models/checkers_models.dart';

class CheckersLogic {
  // ============================================================
  // MOUVEMENTS LÉGAUX
  // ============================================================

  /// Tous les mouvements légaux pour `color` (captures prioritaires)
  static List<CheckerMove> getLegalMoves(
      List<List<CheckerPiece?>> board, PieceColor color) {
    final captures = <CheckerMove>[];
    final simples = <CheckerMove>[];

    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece == null || piece.color != color) continue;

        final pos = BoardPos(r, c);
        final caps = _getCaptures(board, pos, piece, []);
        final movs = _getSimpleMoves(board, pos, piece);

        captures.addAll(caps);
        simples.addAll(movs);
      }
    }

    // Si captures disponibles → obligatoire
    return captures.isNotEmpty ? captures : simples;
  }

  /// Mouvements simples (pas de capture) pour un pion
  static List<CheckerMove> _getSimpleMoves(
      List<List<CheckerPiece?>> board, BoardPos pos, CheckerPiece piece) {
    final moves = <CheckerMove>[];
    final dirs = _getDirs(piece);

    for (final d in dirs) {
      final nr = pos.row + d[0];
      final nc = pos.col + d[1];
      if (_inBounds(nr, nc) && board[nr][nc] == null) {
        moves.add(CheckerMove(from: pos, to: BoardPos(nr, nc)));
      }
    }
    return moves;
  }

  /// Captures récursives (sauts multiples)
  /// Les captures sont autorisées dans TOUTES les directions (même en arrière)
  static List<CheckerMove> _getCaptures(
    List<List<CheckerPiece?>> board,
    BoardPos pos,
    CheckerPiece piece,
    List<BoardPos> alreadyCaptured,
  ) {
    final moves = <CheckerMove>[];
    // Pour les captures : TOUJOURS 4 directions (arrière autorisé)
    final dirs = [[-1, -1], [-1, 1], [1, -1], [1, 1]];

    for (final d in dirs) {
      final mr = pos.row + d[0]; // case du milieu (pion adverse)
      final mc = pos.col + d[1];
      final lr = pos.row + d[0] * 2; // case d’atterrissage
      final lc = pos.col + d[1] * 2;

      if (!_inBounds(lr, lc)) continue;

      final middle = _inBounds(mr, mc) ? board[mr][mc] : null;
      if (middle == null ||
          middle.color == piece.color ||
          alreadyCaptured.contains(BoardPos(mr, mc))) { continue; }

      if (board[lr][lc] != null) continue;

      final captured = [...alreadyCaptured, BoardPos(mr, mc)];
      final landPos = BoardPos(lr, lc);

      // Vérifier s’il y a d’autres captures depuis la position d’atterrissage
      final newBoard = _applyPartialMove(board, pos, landPos, BoardPos(mr, mc));
      final isKing = piece.isKing || _shouldPromote(piece.color, lr);
      final newPiece = CheckerPiece(color: piece.color,
          type: isKing ? PieceType.king : piece.type);

      final continuations = _getCaptures(newBoard, landPos, newPiece, captured);

      if (continuations.isEmpty) {
        moves.add(CheckerMove(from: pos, to: landPos, captured: captured));
      } else {
        moves.addAll(continuations);
      }
    }

    return moves;
  }

  // ============================================================
  // APPLICATION D’UN MOUVEMENT
  // ============================================================

  /// Applique un mouvement et retourne le nouvel état
  static CheckersGameState applyMove(
      CheckersGameState state, CheckerMove move) {
    final board = _copyBoard(state.board);

    final piece = board[move.from.row][move.from.col]!;
    board[move.from.row][move.from.col] = null;

    // Supprimer les pions capturés
    for (final cap in move.captured) {
      board[cap.row][cap.col] = null;
    }

    // Placer le pion à la destination
    final promoted = _shouldPromote(piece.color, move.to.row);
    board[move.to.row][move.to.col] = CheckerPiece(
      color: piece.color,
      type: promoted ? PieceType.king : piece.type,
    );

    // Compter les pions
    int redCount = 0, blackCount = 0;
    for (final row in board) {
      for (final p in row) {
        if (p?.color == PieceColor.red) redCount++;
        if (p?.color == PieceColor.black) blackCount++;
      }
    }

    final nextTurn = state.currentTurn == PieceColor.red
        ? PieceColor.black
        : PieceColor.red;

    // Vérifier fin de partie
    final nextMoves = getLegalMoves(board, nextTurn);
    final bool gameOver = redCount == 0 || blackCount == 0 || nextMoves.isEmpty;

    PieceColor? winner;
    if (gameOver) {
      // Red n'a plus de pions OU c'est le tour de Red et il ne peut pas jouer → Black gagne
      if (redCount == 0 || (nextTurn == PieceColor.red && nextMoves.isEmpty)) {
        winner = PieceColor.black;
      } else {
        winner = PieceColor.red;
      }
    }

    return CheckersGameState(
      board: board,
      currentTurn: nextTurn,
      isGameOver: gameOver,
      winner: winner,
      redCount: redCount,
      blackCount: blackCount,
    );
  }

  // ============================================================
  // IA MINIMAX
  // ============================================================

  /// Meilleur coup pour l’IA (depth = difficulté)
  static CheckerMove? getBestMove(
      CheckersGameState state, PieceColor aiColor,
      {int depth = 4}) {
    final moves = getLegalMoves(state.board, aiColor);
    if (moves.isEmpty) return null;

    CheckerMove? best;
    int bestScore = -99999;

    for (final move in moves) {
      final newState = applyMove(state, move);
      final score = _minimax(newState, depth - 1, -99999, 99999, false, aiColor);
      if (score > bestScore) {
        bestScore = score;
        best = move;
      }
    }
    return best;
  }

  static int _minimax(CheckersGameState state, int depth, int alpha, int beta,
      bool isMaximizing, PieceColor aiColor) {
    if (state.isGameOver || depth == 0) {
      return _evaluate(state, aiColor);
    }

    final color = isMaximizing ? aiColor : _opponent(aiColor);
    final moves = getLegalMoves(state.board, color);

    if (isMaximizing) {
      int maxEval = -99999;
      for (final move in moves) {
        final child = applyMove(state, move);
        final eval = _minimax(child, depth - 1, alpha, beta, false, aiColor);
        maxEval = eval > maxEval ? eval : maxEval;
        alpha = alpha > eval ? alpha : eval;
        if (beta <= alpha) break;
      }
      return maxEval;
    } else {
      int minEval = 99999;
      for (final move in moves) {
        final child = applyMove(state, move);
        final eval = _minimax(child, depth - 1, alpha, beta, true, aiColor);
        minEval = eval < minEval ? eval : minEval;
        beta = beta < eval ? beta : eval;
        if (beta <= alpha) break;
      }
      return minEval;
    }
  }

  /// Évaluation heuristique du plateau
  static int _evaluate(CheckersGameState state, PieceColor aiColor) {
    if (state.isGameOver) {
      return state.winner == aiColor ? 1000 : -1000;
    }

    int score = 0;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = state.board[r][c];
        if (p == null) continue;
        final val = p.isKing ? 3 : 1;
        if (p.color == aiColor) {
          score += val;
        } else {
          score -= val;
        }
      }
    }
    return score;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  static List<List<int>> _getDirs(CheckerPiece piece) {
    if (piece.isKing) return [[-1, -1], [-1, 1], [1, -1], [1, 1]];
    if (piece.color == PieceColor.red) return [[-1, -1], [-1, 1]]; // vers le haut
    return [[1, -1], [1, 1]]; // vers le bas
  }

  static bool _inBounds(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

  static bool _shouldPromote(PieceColor color, int row) {
    return color == PieceColor.red ? row == 0 : row == 7;
  }

  static PieceColor _opponent(PieceColor c) =>
      c == PieceColor.red ? PieceColor.black : PieceColor.red;

  static List<List<CheckerPiece?>> _copyBoard(List<List<CheckerPiece?>> b) =>
      b.map((row) => [...row]).toList();

  static List<List<CheckerPiece?>> _applyPartialMove(
    List<List<CheckerPiece?>> board,
    BoardPos from,
    BoardPos to,
    BoardPos captured,
  ) {
    final b = _copyBoard(board);
    b[to.row][to.col] = b[from.row][from.col];
    b[from.row][from.col] = null;
    b[captured.row][captured.col] = null;
    return b;
  }
}

// ============================================================
// LUDO V2 — Board Widget (plateau + pions animés)
// ============================================================

import 'package:flutter/material.dart';
import '../engine/ludo_board.dart';
import '../engine/ludo_engine.dart';
import '../models/ludo_models.dart';
import '../painters/board_painter.dart';

class LudoV2BoardWidget extends StatelessWidget {
  final LudoV2Game game;
  final LudoV2Game? previousGame;
  final String myId;
  final List<PawnMove> playableMoves;
  final void Function(int pawnIndex)? onPawnTap;

  const LudoV2BoardWidget({
    super.key,
    required this.game,
    this.previousGame,
    required this.myId,
    this.playableMoves = const [],
    this.onPawnTap,
  });

  static const _pawnColors = [
    Color(0xFFE53935), // Red
    Color(0xFF43A047), // Green
    Color(0xFF1E88E5), // Blue
    Color(0xFFFDD835), // Yellow
  ];

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final boardSize = constraints.maxWidth;
          final cell = boardSize / 15;

          return Stack(
            children: [
              // Plateau de fond
              CustomPaint(
                size: Size(boardSize, boardSize),
                painter: LudoBoardPainter(),
              ),

              // Pions de tous les joueurs
              ...game.pawns.entries.expand((entry) {
                final uid = entry.key;
                final pawns = entry.value;
                final colorIdx = game.colorMap[uid] ?? 0;
                final isMe = uid == myId;
                return List.generate(4, (i) {
                  final step = pawns[i];
                  final gridPos = LudoBoard.stepToGrid(step, colorIdx, pawnIndex: i);
                  final isPlayable = isMe && playableMoves.any((m) => m.pawnIndex == i);

                  // Stacking : offset si plusieurs pions sur la même case
                  final sameCell = _countSameCell(pawns, step, colorIdx, i, game);
                  final stackOffset = _stackOffset(sameCell.index, sameCell.total, cell);

                  return _AnimatedPawn(
                    key: ValueKey('$uid-$i'),
                    row: gridPos[0],
                    col: gridPos[1],
                    cell: cell,
                    color: _pawnColors[colorIdx],
                    isPlayable: isPlayable,
                    isActive: game.isMyTurn(uid),
                    stackOffset: stackOffset,
                    onTap: isPlayable ? () => onPawnTap?.call(i) : null,
                  );
                });
              }),
            ],
          );
        },
      ),
    );
  }

  /// Compte combien de pions sont sur la même case visuelle
  _SameCellInfo _countSameCell(List<int> myPawns, int step, int myColor, int pawnIdx, LudoV2Game game) {
    if (step <= 0 || step >= 58) {
      // En base ou au centre, offset par index directement
      return _SameCellInfo(pawnIdx, 4);
    }

    // Compter tous les pions de tous les joueurs sur la même case absolue
    int myAbs = LudoBoard.toAbsolute(step, myColor);
    if (step >= 52) myAbs = -step; // Home stretch : unique par couleur

    int total = 0;
    int myIndex = 0;

    for (final entry in game.pawns.entries) {
      final uid = entry.key;
      final color = game.colorMap[uid] ?? 0;
      for (int i = 0; i < entry.value.length; i++) {
        final s = entry.value[i];
        int abs = s >= 52 ? -s : (s >= 1 ? LudoBoard.toAbsolute(s, color) : -100 - i);
        if (abs == myAbs) {
          if (uid == game.pawns.keys.toList()[game.colorMap.keys.toList().indexOf(game.colorMap.keys.firstWhere((k) => game.colorMap[k] == myColor))] && i == pawnIdx) {
            myIndex = total;
          }
          total++;
        }
      }
    }

    return _SameCellInfo(myIndex, total > 1 ? total : 1);
  }

  Offset _stackOffset(int index, int total, double cell) {
    if (total <= 1) return Offset.zero;
    // Disposer en grille 2x2 si 2-4 pions sur la même case
    const offsets = [
      Offset(-0.15, -0.15),
      Offset(0.15, -0.15),
      Offset(-0.15, 0.15),
      Offset(0.15, 0.15),
    ];
    return offsets[index.clamp(0, 3)] * cell;
  }
}

class _SameCellInfo {
  final int index;
  final int total;
  const _SameCellInfo(this.index, this.total);
}

/// Pion animé avec position, couleur, tap et highlight
class _AnimatedPawn extends StatelessWidget {
  final int row;
  final int col;
  final double cell;
  final Color color;
  final bool isPlayable;
  final bool isActive;
  final Offset stackOffset;
  final VoidCallback? onTap;

  const _AnimatedPawn({
    super.key,
    required this.row,
    required this.col,
    required this.cell,
    required this.color,
    required this.isPlayable,
    required this.isActive,
    required this.stackOffset,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final x = col * cell + stackOffset.dx;
    final y = row * cell + stackOffset.dy;
    final size = cell * 0.75;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      left: x + (cell - size) / 2,
      top: y + (cell - size) / 2,
      width: size,
      height: size,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: isPlayable ? Colors.white : color.withValues(alpha: 0.5),
              width: isPlayable ? 3 : 1.5,
            ),
            boxShadow: [
              if (isPlayable)
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2,
                offset: const Offset(1, 2),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: size * 0.4,
              height: size * 0.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

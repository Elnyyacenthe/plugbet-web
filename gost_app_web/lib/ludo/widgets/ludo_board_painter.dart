// ============================================================
// LUDO MODULE - Board Painter (CustomPainter fallback)
// Dessine le plateau Ludo 15x15 avec les pions — style 4 couleurs
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../models/ludo_models.dart';
import '../game/ludo_board_colors.dart';

class LudoBoardPainter extends CustomPainter {
  final LudoGameState gameState;
  final String player1Id;
  final String player2Id;
  final int? selectedPawn;
  final String? currentPlayerId;
  final int? diceValue;

  LudoBoardPainter({
    required this.gameState,
    required this.player1Id,
    required this.player2Id,
    this.selectedPawn,
    this.currentPlayerId,
    this.diceValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / 15;

    _drawBoard(canvas, cellSize);
    _drawHomeBases(canvas, cellSize);
    _drawHomeStretches(canvas, cellSize);
    _drawStartCells(canvas, cellSize);
    _drawSafeCells(canvas, cellSize);
    _drawStartArrows(canvas, cellSize);
    _drawCenter(canvas, cellSize);
    _drawBoardBorder(canvas, cellSize);
    _drawPawns(canvas, cellSize);
  }

  void _drawBoard(Canvas canvas, double cellSize) {
    final bgPaint = Paint()..color = LudoBoardColors.boardBg;
    final boardSize = cellSize * 15;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, boardSize, boardSize),
        const Radius.circular(8),
      ),
      bgPaint,
    );

    final trackPaint = Paint()..color = LudoBoardColors.trackCell;
    final borderPaint = Paint()
      ..color = LudoBoardColors.gridLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (final cell in LudoBoard.trackCells) {
      final rect = Rect.fromLTWH(
        cell[1] * cellSize, cell[0] * cellSize, cellSize, cellSize,
      );
      canvas.drawRect(rect, trackPaint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  void _drawHomeBases(Canvas canvas, double cellSize) {
    _drawHomeBase(canvas, cellSize, 9, 0, LudoBoardColors.red, LudoBoardColors.redLight);
    _drawHomeBase(canvas, cellSize, 0, 0, LudoBoardColors.green, LudoBoardColors.greenLight);
    _drawHomeBase(canvas, cellSize, 0, 9, LudoBoardColors.blue, LudoBoardColors.blueLight);
    _drawHomeBase(canvas, cellSize, 9, 9, LudoBoardColors.yellow, LudoBoardColors.yellowLight);
  }

  void _drawHomeBase(
    Canvas canvas, double cellSize,
    int startRow, int startCol,
    Color mainColor, Color lightColor,
  ) {
    final basePaint = Paint()..color = mainColor;
    final innerPaint = Paint()..color = Colors.white;
    final dotPaint = Paint()..color = lightColor;
    final dotBorderPaint = Paint()
      ..color = mainColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final baseRect = Rect.fromLTWH(
      startCol * cellSize, startRow * cellSize, 6 * cellSize, 6 * cellSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, const Radius.circular(6)),
      basePaint,
    );

    final innerRect = Rect.fromLTWH(
      (startCol + 1) * cellSize, (startRow + 1) * cellSize, 4 * cellSize, 4 * cellSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(6)),
      innerPaint,
    );

    final positions = [
      [startRow + 1.5, startCol + 1.5],
      [startRow + 1.5, startCol + 3.5],
      [startRow + 3.5, startCol + 1.5],
      [startRow + 3.5, startCol + 3.5],
    ];

    for (final pos in positions) {
      final center = Offset((pos[1] + 0.5) * cellSize, (pos[0] + 0.5) * cellSize);
      canvas.drawCircle(center, cellSize * 0.38, dotPaint);
      canvas.drawCircle(center, cellSize * 0.38, dotBorderPaint);
      canvas.drawCircle(center, cellSize * 0.15, Paint()..color = Colors.white);
    }
  }

  void _drawHomeStretches(Canvas canvas, double cellSize) {
    final borderPaint = Paint()
      ..color = LudoBoardColors.gridLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    _drawStretchCells(canvas, cellSize, LudoBoard.homeStretchRed, LudoBoardColors.red, borderPaint);
    _drawStretchCells(canvas, cellSize, LudoBoard.homeStretchBlue, LudoBoardColors.blue, borderPaint);
    _drawStretchCells(canvas, cellSize, LudoBoard.homeStretchGreen, LudoBoardColors.green, borderPaint);
    _drawStretchCells(canvas, cellSize, LudoBoard.homeStretchYellow, LudoBoardColors.yellow, borderPaint);
  }

  void _drawStretchCells(Canvas canvas, double cellSize, List<List<int>> cells, Color color, Paint borderPaint) {
    final paint = Paint()..color = color.withValues(alpha: 0.45);
    for (final cell in cells) {
      final rect = Rect.fromLTWH(
        cell[1] * cellSize, cell[0] * cellSize, cellSize, cellSize,
      );
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  void _drawStartCells(Canvas canvas, double cellSize) {
    _drawColoredCell(canvas, cellSize, LudoBoard.trackCells[0], LudoBoardColors.red);
    _drawColoredCell(canvas, cellSize, LudoBoard.trackCells[26], LudoBoardColors.blue);
    _drawColoredCell(canvas, cellSize, LudoBoard.trackCells[13], LudoBoardColors.green);
    _drawColoredCell(canvas, cellSize, LudoBoard.trackCells[39], LudoBoardColors.yellow);
  }

  void _drawColoredCell(Canvas canvas, double cellSize, List<int> cell, Color color) {
    final rect = Rect.fromLTWH(
      cell[1] * cellSize, cell[0] * cellSize, cellSize, cellSize,
    );
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.3));
  }

  void _drawSafeCells(Canvas canvas, double cellSize) {
    const safeIndices = [0, 8, 13, 21, 26, 34, 39, 47];
    final starPaint = Paint()..color = const Color(0xFFFFB300).withValues(alpha: 0.7);
    final starBorderPaint = Paint()
      ..color = const Color(0xFFFF8F00).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final idx in safeIndices) {
      final cell = LudoBoard.trackCells[idx];
      final center = Offset(
        cell[1] * cellSize + cellSize / 2,
        cell[0] * cellSize + cellSize / 2,
      );
      _drawStar(canvas, center, cellSize * 0.35, starPaint);
      _drawStar(canvas, center, cellSize * 0.35, starBorderPaint);
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    const points = 5;
    final innerRadius = radius * 0.4;
    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : innerRadius;
      final angle = (i * pi / points) - pi / 2;
      final x = center.dx + r * cos(angle);
      final y = center.dy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawStartArrows(Canvas canvas, double cellSize) {
    final redStart = LudoBoard.trackCells[0];
    _drawArrowMarker(canvas, cellSize, redStart[0], redStart[1], LudoBoardColors.red);
    final blueStart = LudoBoard.trackCells[26];
    _drawArrowMarker(canvas, cellSize, blueStart[0], blueStart[1], LudoBoardColors.blue);
  }

  void _drawArrowMarker(Canvas canvas, double cellSize, int row, int col, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(col * cellSize + cellSize / 2, row * cellSize + cellSize / 2);
    canvas.drawCircle(center, cellSize * 0.4, paint);
  }

  void _drawCenter(Canvas canvas, double cellSize) {
    final centerPaint = Paint()..color = LudoBoardColors.centerBg;
    final rect = Rect.fromLTWH(6 * cellSize, 6 * cellSize, 3 * cellSize, 3 * cellSize);
    canvas.drawRect(rect, centerPaint);

    // 4 triangles colores
    _drawTriangle(canvas, LudoBoardColors.red,
      Offset(6 * cellSize, 9 * cellSize), Offset(9 * cellSize, 9 * cellSize), Offset(7.5 * cellSize, 7.5 * cellSize));
    _drawTriangle(canvas, LudoBoardColors.blue,
      Offset(6 * cellSize, 6 * cellSize), Offset(9 * cellSize, 6 * cellSize), Offset(7.5 * cellSize, 7.5 * cellSize));
    _drawTriangle(canvas, LudoBoardColors.green,
      Offset(6 * cellSize, 6 * cellSize), Offset(6 * cellSize, 9 * cellSize), Offset(7.5 * cellSize, 7.5 * cellSize));
    _drawTriangle(canvas, LudoBoardColors.yellow,
      Offset(9 * cellSize, 6 * cellSize), Offset(9 * cellSize, 9 * cellSize), Offset(7.5 * cellSize, 7.5 * cellSize));
  }

  void _drawTriangle(Canvas canvas, Color color, Offset p1, Offset p2, Offset p3) {
    final paint = Paint()..color = color;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()..moveTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..lineTo(p3.dx, p3.dy)..close();
    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  void _drawBoardBorder(Canvas canvas, double cellSize) {
    final boardSize = cellSize * 15;
    final borderPaint = Paint()
      ..color = LudoBoardColors.boardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, boardSize, boardSize), const Radius.circular(8)),
      borderPaint,
    );
  }

  void _drawPawns(Canvas canvas, double cellSize) {
    final p1Pawns = gameState.playerPawns(player1Id);
    final p2Pawns = gameState.playerPawns(player2Id);

    for (int i = 0; i < 4; i++) {
      final pos = LudoBoard.getPawnPosition(p1Pawns[i], true, pawnIndex: i);
      _drawPawnPin(canvas, cellSize, pos[0], pos[1], LudoBoardColors.red,
        isSelected: currentPlayerId == player1Id && selectedPawn == i,
        isHighlighted: currentPlayerId == player1Id &&
            selectedPawn == null && diceValue != null &&
            gameState.canMovePawn(player1Id, i, diceValue!),
      );
    }

    for (int i = 0; i < 4; i++) {
      final pos = LudoBoard.getPawnPosition(p2Pawns[i], false, pawnIndex: i);
      _drawPawnPin(canvas, cellSize, pos[0], pos[1], LudoBoardColors.blue,
        isSelected: currentPlayerId == player2Id && selectedPawn == i,
        isHighlighted: currentPlayerId == player2Id &&
            selectedPawn == null && diceValue != null &&
            gameState.canMovePawn(player2Id, i, diceValue!),
      );
    }
  }

  void _drawPawnPin(
    Canvas canvas, double cellSize, int row, int col, Color color,
    {bool isSelected = false, bool isHighlighted = false}
  ) {
    final centerX = col * cellSize + cellSize / 2;
    final circleCenter = Offset(centerX, row * cellSize + cellSize * 0.35);
    final pinTip = Offset(centerX, row * cellSize + cellSize * 0.78);
    final radius = cellSize * 0.30;

    if (isSelected || isHighlighted) {
      final haloColor = isSelected ? Colors.white : Colors.yellow;
      final haloPaint = Paint()
        ..color = haloColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3 : 2;
      canvas.drawCircle(circleCenter, radius + 4, haloPaint);
    }

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    _drawPinShape(canvas, circleCenter + const Offset(1, 2), pinTip + const Offset(1, 2), radius, shadowPaint);

    // Body
    final bodyPaint = Paint()..color = color;
    _drawPinShape(canvas, circleCenter, pinTip, radius, bodyPaint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _drawPinShape(canvas, circleCenter, pinTip, radius, borderPaint);

    // Inner white dot
    canvas.drawCircle(circleCenter, radius * 0.4, Paint()..color = Colors.white);
  }

  void _drawPinShape(Canvas canvas, Offset circleCenter, Offset tip, double radius, Paint paint) {
    final path = Path();
    const tangentAngle = 0.45;
    path.addArc(
      Rect.fromCircle(center: circleCenter, radius: radius),
      pi * 0.5 + tangentAngle,
      pi * 2 - tangentAngle * 2,
    );
    path.lineTo(tip.dx, tip.dy);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) {
    return oldDelegate.gameState != gameState ||
        oldDelegate.selectedPawn != selectedPawn ||
        oldDelegate.currentPlayerId != currentPlayerId ||
        oldDelegate.diceValue != diceValue;
  }
}

/// Widget qui encapsule le CustomPainter et gere les taps sur les pions
class LudoBoardWidget extends StatelessWidget {
  final LudoGameState gameState;
  final String player1Id;
  final String player2Id;
  final String? currentPlayerId;
  final int? selectedPawn;
  final int? diceValue;
  final void Function(int pawnIndex)? onPawnTap;

  const LudoBoardWidget({
    super.key,
    required this.gameState,
    required this.player1Id,
    required this.player2Id,
    this.currentPlayerId,
    this.selectedPawn,
    this.diceValue,
    this.onPawnTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight);
        final cellSize = size / 15;

        return GestureDetector(
          onTapDown: (details) {
            if (onPawnTap == null || currentPlayerId == null) return;

            final tapRow = (details.localPosition.dy / cellSize).floor();
            final tapCol = (details.localPosition.dx / cellSize).floor();

            final isPlayer1 = currentPlayerId == player1Id;
            final pawns = gameState.playerPawns(currentPlayerId!);

            for (int i = 0; i < 4; i++) {
              final pos = LudoBoard.getPawnPosition(pawns[i], isPlayer1, pawnIndex: i);
              if (pos[0] == tapRow && pos[1] == tapCol) {
                onPawnTap!(i);
                return;
              }
            }
          },
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: LudoBoardPainter(
                gameState: gameState,
                player1Id: player1Id,
                player2Id: player2Id,
                selectedPawn: selectedPawn,
                currentPlayerId: currentPlayerId,
                diceValue: diceValue,
              ),
            ),
          ),
        );
      },
    );
  }
}

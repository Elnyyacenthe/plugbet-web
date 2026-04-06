import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../models/ludo_models.dart';
import '../ludo_board_colors.dart';

class BoardComponent extends PositionComponent {
  final double cellSize;

  BoardComponent({required this.cellSize})
      : super(size: Vector2.all(cellSize * 15));

  @override
  void render(Canvas canvas) {
    _drawBoardBackground(canvas);
    _drawTrackCells(canvas);
    _drawHomeBases(canvas);
    _drawHomeStretches(canvas);
    _drawStartCells(canvas);
    _drawSafeCells(canvas);
    _drawStartArrows(canvas);
    _drawCenter(canvas);
    _drawBoardBorder(canvas);
  }

  void _drawBoardBackground(Canvas canvas) {
    final bgPaint = Paint()..color = LudoBoardColors.boardBg;
    final boardSize = cellSize * 15;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, boardSize, boardSize),
        const Radius.circular(8),
      ),
      bgPaint,
    );
  }

  void _drawTrackCells(Canvas canvas) {
    final trackPaint = Paint()..color = LudoBoardColors.trackCell;
    final borderPaint = Paint()
      ..color = LudoBoardColors.gridLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (final cell in LudoBoard.trackCells) {
      final rect = Rect.fromLTWH(
        cell[1] * cellSize,
        cell[0] * cellSize,
        cellSize,
        cellSize,
      );
      canvas.drawRect(rect, trackPaint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  void _drawHomeBases(Canvas canvas) {
    // 4 bases colorees — style classique
    _drawHomeBase(canvas, 9, 0, LudoBoardColors.red, LudoBoardColors.redLight);
    _drawHomeBase(canvas, 0, 0, LudoBoardColors.green, LudoBoardColors.greenLight);
    _drawHomeBase(canvas, 0, 9, LudoBoardColors.blue, LudoBoardColors.blueLight);
    _drawHomeBase(canvas, 9, 9, LudoBoardColors.yellow, LudoBoardColors.yellowLight);
  }

  void _drawHomeBase(
    Canvas canvas,
    int startRow,
    int startCol,
    Color mainColor,
    Color lightColor,
  ) {
    final basePaint = Paint()..color = mainColor;
    final innerPaint = Paint()..color = Colors.white;
    final dotPaint = Paint()..color = lightColor;
    final dotBorderPaint = Paint()
      ..color = mainColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Fond colore de la base
    final baseRect = Rect.fromLTWH(
      startCol * cellSize,
      startRow * cellSize,
      6 * cellSize,
      6 * cellSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, const Radius.circular(6)),
      basePaint,
    );

    // Carre blanc interieur
    final innerRect = Rect.fromLTWH(
      (startCol + 1) * cellSize,
      (startRow + 1) * cellSize,
      4 * cellSize,
      4 * cellSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, const Radius.circular(6)),
      innerPaint,
    );

    // 4 cercles de pions dans la base
    final positions = [
      [startRow + 1.5, startCol + 1.5],
      [startRow + 1.5, startCol + 3.5],
      [startRow + 3.5, startCol + 1.5],
      [startRow + 3.5, startCol + 3.5],
    ];

    for (final pos in positions) {
      final center = Offset(
        (pos[1] + 0.5) * cellSize,
        (pos[0] + 0.5) * cellSize,
      );
      // Cercle colore
      canvas.drawCircle(center, cellSize * 0.38, dotPaint);
      // Bordure du cercle
      canvas.drawCircle(center, cellSize * 0.38, dotBorderPaint);
      // Petit cercle blanc au centre (style classique)
      canvas.drawCircle(
        center,
        cellSize * 0.15,
        Paint()..color = Colors.white,
      );
    }
  }

  void _drawHomeStretches(Canvas canvas) {
    final borderPaint = Paint()
      ..color = LudoBoardColors.gridLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Rouge — couloir du bas vers le centre
    _drawStretchCells(canvas, LudoBoard.homeStretchRed, LudoBoardColors.red, borderPaint);
    // Bleu — couloir du haut vers le centre (joueur actif)
    _drawStretchCells(canvas, LudoBoard.homeStretchBlue, LudoBoardColors.blue, borderPaint);
    // Vert — couloir de gauche (decoratif, meme colonne que bleu)
    _drawStretchCells(canvas, LudoBoard.homeStretchGreen, LudoBoardColors.green, borderPaint);
    // Jaune — couloir de droite (decoratif, meme colonne que rouge)
    _drawStretchCells(canvas, LudoBoard.homeStretchYellow, LudoBoardColors.yellow, borderPaint);
  }

  void _drawStretchCells(Canvas canvas, List<List<int>> cells, Color color, Paint borderPaint) {
    final paint = Paint()..color = color.withValues(alpha: 0.65);
    for (final cell in cells) {
      final rect = Rect.fromLTWH(
        cell[1] * cellSize, cell[0] * cellSize, cellSize, cellSize,
      );
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  /// Colorer les cases de depart de chaque joueur
  void _drawStartCells(Canvas canvas) {
    // Case de depart Rouge (index 0)
    _drawColoredCell(canvas, LudoBoard.trackCells[0], LudoBoardColors.red);
    // Case de depart Bleu (index 26)
    _drawColoredCell(canvas, LudoBoard.trackCells[26], LudoBoardColors.blue);
    // Cases decoratives pour Vert (index 13) et Jaune (index 39)
    _drawColoredCell(canvas, LudoBoard.trackCells[13], LudoBoardColors.green);
    _drawColoredCell(canvas, LudoBoard.trackCells[39], LudoBoardColors.yellow);
  }

  void _drawColoredCell(Canvas canvas, List<int> cell, Color color) {
    final rect = Rect.fromLTWH(
      cell[1] * cellSize,
      cell[0] * cellSize,
      cellSize,
      cellSize,
    );
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.3));
  }

  void _drawSafeCells(Canvas canvas) {
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

  void _drawStartArrows(Canvas canvas) {
    final redStart = LudoBoard.trackCells[0];
    _drawArrowMarker(canvas, redStart[0], redStart[1], LudoBoardColors.red);

    final blueStart = LudoBoard.trackCells[26];
    _drawArrowMarker(canvas, blueStart[0], blueStart[1], LudoBoardColors.blue);
  }

  void _drawArrowMarker(Canvas canvas, int row, int col, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final center = Offset(
      col * cellSize + cellSize / 2,
      row * cellSize + cellSize / 2,
    );
    canvas.drawCircle(center, cellSize * 0.4, paint);
  }

  void _drawCenter(Canvas canvas) {
    final centerPaint = Paint()..color = LudoBoardColors.centerBg;
    final rect = Rect.fromLTWH(6 * cellSize, 6 * cellSize, 3 * cellSize, 3 * cellSize);
    canvas.drawRect(rect, centerPaint);

    // 4 triangles colores — style classique
    // Bas (Rouge)
    _drawTriangle(
      canvas, LudoBoardColors.red,
      Offset(6 * cellSize, 9 * cellSize),
      Offset(9 * cellSize, 9 * cellSize),
      Offset(7.5 * cellSize, 7.5 * cellSize),
    );
    // Haut (Bleu)  — note: dans l'image ref, bleu est en haut
    _drawTriangle(
      canvas, LudoBoardColors.blue,
      Offset(6 * cellSize, 6 * cellSize),
      Offset(9 * cellSize, 6 * cellSize),
      Offset(7.5 * cellSize, 7.5 * cellSize),
    );
    // Gauche (Vert)
    _drawTriangle(
      canvas, LudoBoardColors.green,
      Offset(6 * cellSize, 6 * cellSize),
      Offset(6 * cellSize, 9 * cellSize),
      Offset(7.5 * cellSize, 7.5 * cellSize),
    );
    // Droite (Jaune)
    _drawTriangle(
      canvas, LudoBoardColors.yellow,
      Offset(9 * cellSize, 6 * cellSize),
      Offset(9 * cellSize, 9 * cellSize),
      Offset(7.5 * cellSize, 7.5 * cellSize),
    );
  }

  void _drawTriangle(Canvas canvas, Color color, Offset p1, Offset p2, Offset p3) {
    final paint = Paint()..color = color;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  void _drawBoardBorder(Canvas canvas) {
    final boardSize = cellSize * 15;
    final borderPaint = Paint()
      ..color = LudoBoardColors.boardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = (cellSize * 0.12).clamp(1.5, 4.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, boardSize, boardSize),
        const Radius.circular(8),
      ),
      borderPaint,
    );
  }
}

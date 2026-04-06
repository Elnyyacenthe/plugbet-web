// ============================================================
// LUDO V2 — Board Painter (CustomPainter, Ludo King style)
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../engine/ludo_board.dart';

class LudoBoardPainter extends CustomPainter {
  LudoBoardPainter();

  static const _red = Color(0xFFE53935);
  static const _green = Color(0xFF43A047);
  static const _blue = Color(0xFF1E88E5);
  static const _yellow = Color(0xFFFDD835);
  static const _white = Color(0xFFFFFFFF);
  static const _bg = Color(0xFFF5F0E1);
  static const _border = Color(0xFF37474F);

  static const _playerColors = [_red, _green, _blue, _yellow];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final paint = Paint();

    // Fond
    paint.color = _bg;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // ── Home bases (grands carrés colorés) ─────────────
    // Aligné sur homeBases + homeStretches :
    // Red    → haut-gauche,  stretch row 7 cols 1→6
    // Green  → bas-gauche,   stretch col 7 rows 13→8
    // Blue   → bas-droite,   stretch row 7 cols 13→8
    // Yellow → haut-droite,  stretch col 7 rows 1→6
    _drawHomeBase(canvas, cell, 0, 0, _red);        // Red haut-gauche
    _drawHomeBase(canvas, cell, 9, 0, _green);      // Green bas-gauche
    _drawHomeBase(canvas, cell, 9, 9, _blue);       // Blue bas-droite
    _drawHomeBase(canvas, cell, 0, 9, _yellow);     // Yellow haut-droite

    // ── Track cells ────────────────────────────────────
    _drawTrackCells(canvas, cell);

    // ── Home stretches (couloirs colorés) ──────────────
    for (int color = 0; color < 4; color++) {
      for (final pos in LudoBoard.homeStretches[color]) {
        _drawCell(canvas, cell, pos[0], pos[1], _playerColors[color].withValues(alpha: 0.4));
        _drawCellBorder(canvas, cell, pos[0], pos[1]);
      }
    }

    // ── Centre (triangle coloré) ───────────────────────
    _drawCenter(canvas, cell);

    // ── Safe spots (étoile) ────────────────────────────
    _drawSafeSpots(canvas, cell);

    // ── Grille bordure ─────────────────────────────────
    _drawGridBorders(canvas, cell);
  }

  void _drawHomeBase(Canvas canvas, double cell, int startRow, int startCol, Color color) {
    final paint = Paint()..color = color;
    final rect = Rect.fromLTWH(startCol * cell, startRow * cell, 6 * cell, 6 * cell);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);

    // Carré blanc intérieur avec cercles de pions
    final innerPaint = Paint()..color = _white;
    final inner = Rect.fromLTWH(
      (startCol + 0.7) * cell, (startRow + 0.7) * cell,
      4.6 * cell, 4.6 * cell,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(inner, const Radius.circular(8)), innerPaint);

    // 4 cercles pour les pions
    final circlePaint = Paint()..color = color;
    final positions = [
      [startRow + 1.5, startCol + 1.5],
      [startRow + 1.5, startCol + 4.5],
      [startRow + 4.5, startCol + 1.5],
      [startRow + 4.5, startCol + 4.5],
    ];
    for (final pos in positions) {
      canvas.drawCircle(
        Offset((pos[1] + 0.5) * cell, (pos[0] + 0.5) * cell),
        cell * 0.45,
        circlePaint,
      );
      // Contour blanc
      canvas.drawCircle(
        Offset((pos[1] + 0.5) * cell, (pos[0] + 0.5) * cell),
        cell * 0.45,
        Paint()..color = _white..style = PaintingStyle.stroke..strokeWidth = 2,
      );
    }
  }

  void _drawTrackCells(Canvas canvas, double cell) {
    for (int i = 0; i < LudoBoard.track.length; i++) {
      final pos = LudoBoard.track[i];
      // Colorer les cases de départ
      Color? cellColor;
      if (i == 0) cellColor = _red.withValues(alpha: 0.3);
      if (i == 13) cellColor = _green.withValues(alpha: 0.3);
      if (i == 26) cellColor = _blue.withValues(alpha: 0.3);
      if (i == 39) cellColor = _yellow.withValues(alpha: 0.3);

      _drawCell(canvas, cell, pos[0], pos[1], cellColor ?? _white);
      _drawCellBorder(canvas, cell, pos[0], pos[1]);
    }
  }

  void _drawCell(Canvas canvas, double cell, int row, int col, Color color) {
    canvas.drawRect(
      Rect.fromLTWH(col * cell, row * cell, cell, cell),
      Paint()..color = color,
    );
  }

  void _drawCellBorder(Canvas canvas, double cell, int row, int col) {
    canvas.drawRect(
      Rect.fromLTWH(col * cell, row * cell, cell, cell),
      Paint()..color = _border.withValues(alpha: 0.15)..style = PaintingStyle.stroke..strokeWidth = 0.5,
    );
  }

  void _drawCenter(Canvas canvas, double cell) {
    final cx = 7.5 * cell;
    final cy = 7.5 * cell;
    final size = cell * 1.5;

    // 4 triangles colorés
    final colors = [_red, _blue, _yellow, _green];
    final angles = [0.0, pi / 2, pi, 3 * pi / 2];

    for (int i = 0; i < 4; i++) {
      final path = Path();
      path.moveTo(cx, cy);
      path.lineTo(cx + size * cos(angles[i] - pi / 4), cy + size * sin(angles[i] - pi / 4));
      path.lineTo(cx + size * cos(angles[i] + pi / 4), cy + size * sin(angles[i] + pi / 4));
      path.close();
      canvas.drawPath(path, Paint()..color = colors[i]);
    }

    // Bordure du centre
    canvas.drawCircle(Offset(cx, cy), size * 0.3, Paint()..color = _white);
  }

  void _drawSafeSpots(Canvas canvas, double cell) {
    // Dessiner une étoile sur les cases sûres (sauf les cases de départ)
    const safeIndices = [8, 21, 34, 47]; // Étoiles uniquement
    for (final idx in safeIndices) {
      final pos = LudoBoard.track[idx];
      _drawStar(canvas, cell, pos[0], pos[1]);
    }
    // Cases de départ colorées (track index → couleur)
    // Track: Red=0, Yellow=13, Blue=26, Green=39
    const startData = [
      [0, 0],   // track index 0  → Red (_playerColors[0])
      [13, 3],  // track index 13 → Yellow (_playerColors[3])
      [26, 2],  // track index 26 → Blue (_playerColors[2])
      [39, 1],  // track index 39 → Green (_playerColors[1])
    ];
    for (final data in startData) {
      final pos = LudoBoard.track[data[0]];
      _drawStar(canvas, cell, pos[0], pos[1], color: _playerColors[data[1]]);
    }
  }

  void _drawStar(Canvas canvas, double cell, int row, int col, {Color? color}) {
    final cx = (col + 0.5) * cell;
    final cy = (row + 0.5) * cell;
    final r = cell * 0.25;

    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = (i * 72 - 90) * pi / 180;
      final innerAngle = ((i * 72) + 36 - 90) * pi / 180;
      if (i == 0) {
        path.moveTo(cx + r * cos(outerAngle), cy + r * sin(outerAngle));
      } else {
        path.lineTo(cx + r * cos(outerAngle), cy + r * sin(outerAngle));
      }
      path.lineTo(cx + r * 0.4 * cos(innerAngle), cy + r * 0.4 * sin(innerAngle));
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color ?? const Color(0xFF795548));
  }

  void _drawGridBorders(Canvas canvas, double cell) {
    final borderPaint = Paint()
      ..color = _border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Bordure extérieure
    canvas.drawRect(Rect.fromLTWH(0, 0, 15 * cell, 15 * cell), borderPaint);

    // Bordures des home bases
    canvas.drawRect(Rect.fromLTWH(0, 0, 6 * cell, 6 * cell), borderPaint);
    canvas.drawRect(Rect.fromLTWH(9 * cell, 0, 6 * cell, 6 * cell), borderPaint);
    canvas.drawRect(Rect.fromLTWH(0, 9 * cell, 6 * cell, 6 * cell), borderPaint);
    canvas.drawRect(Rect.fromLTWH(9 * cell, 9 * cell, 6 * cell, 6 * cell), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

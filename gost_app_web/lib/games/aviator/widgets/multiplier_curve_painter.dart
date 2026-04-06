// ============================================================
// AVIATOR – CustomPainter courbe multiplicateur
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';

class MultiplierCurvePainter extends CustomPainter {
  final double progress;   // 0.0 → 1.0 (fraction temps du round)
  final double multiplier; // multiplicateur courant
  final bool crashed;
  final bool waiting;

  const MultiplierCurvePainter({
    required this.progress,
    required this.multiplier,
    required this.crashed,
    required this.waiting,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waiting || progress <= 0) return;

    // Normaliser en Y : log(1 + mult) / log(51)
    // mult=0.00 → 0.0 (bas)
    // mult=1.00 → 0.14 (break-even)
    // mult=5.00 → 0.41
    // mult=50.0 → 1.0 (haut)
    final yRatio = (log(1.0 + multiplier.clamp(0.0, 9999)) / log(51)).clamp(0.0, 1.0);
    final xEnd = size.width * progress.clamp(0.0, 1.0);
    final yEnd = size.height * (1.0 - yRatio);

    // Courbe de Bezier quadratique
    // Point de contrôle : reste bas au début → crée la forme exponentielle
    final cpX = xEnd * 0.35;
    final cpY = size.height * 0.95;

    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(cpX, cpY, xEnd, yEnd);

    final color = crashed
        ? const Color(0xFFEF4444) // rouge crash
        : const Color(0xFFF97316); // orange néon vol

    // ── Lueur (glow) ──────────────────────────────────
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 12
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // ── Ligne principale ──────────────────────────────
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── Remplissage sous la courbe ────────────────────
    final fillPath = Path.from(path)
      ..lineTo(xEnd, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.14),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // ── Point d'extrémité (position avion) ───────────
    if (!crashed && xEnd > 5) {
      // Halo
      canvas.drawCircle(
        Offset(xEnd, yEnd),
        9,
        Paint()..color = color.withValues(alpha: 0.25),
      );
      // Point solide
      canvas.drawCircle(
        Offset(xEnd, yEnd),
        5,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(MultiplierCurvePainter old) =>
      old.progress != progress ||
      old.multiplier != multiplier ||
      old.crashed != crashed ||
      old.waiting != waiting;

  /// Retourne la position de l'extrémité de la courbe
  static Offset planePosition(Size size, double progress, double multiplier) {
    final yRatio =
        (log(1.0 + multiplier.clamp(0.0, 9999)) / log(51)).clamp(0.0, 1.0);
    final xEnd = size.width * progress.clamp(0.0, 1.0);
    final yEnd = size.height * (1.0 - yRatio);
    return Offset(xEnd, yEnd);
  }
}

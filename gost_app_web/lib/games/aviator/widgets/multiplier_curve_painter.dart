// ============================================================
// AVIATOR – CustomPainter courbe multiplicateur (premium redesign)
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

    // Palette premium : dégradé chaud orange → jaune en vol, rouge profond au crash.
    final List<Color> strokeColors = crashed
        ? const [Color(0xFFFF6B6B), Color(0xFFEF4444), Color(0xFFB91C1C)]
        : const [Color(0xFFFFC078), Color(0xFFF97316), Color(0xFFEA580C)];
    final Color color = crashed ? const Color(0xFFEF4444) : const Color(0xFFF97316);

    final strokeShader = LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: strokeColors,
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // ── Lueur externe large (glow diffus) ─────────────
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..strokeWidth = 18
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // ── Lueur intermédiaire (glow serré) ──────────────
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // ── Ligne principale en dégradé ───────────────────
    canvas.drawPath(
      path,
      Paint()
        ..shader = strokeShader
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── Fin cœur lumineux blanc (noyau) ───────────────
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── Remplissage sous la courbe (dégradé profond) ──
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
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.05),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // ── Point d'extrémité (position avion) ───────────
    if (!crashed && xEnd > 5) {
      // Halo large
      canvas.drawCircle(
        Offset(xEnd, yEnd),
        14,
        Paint()
          ..color = color.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      // Halo moyen
      canvas.drawCircle(
        Offset(xEnd, yEnd),
        9,
        Paint()..color = color.withValues(alpha: 0.3),
      );
      // Point solide avec cœur blanc
      canvas.drawCircle(
        Offset(xEnd, yEnd),
        5,
        Paint()..color = color,
      );
      canvas.drawCircle(
        Offset(xEnd, yEnd),
        2,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
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

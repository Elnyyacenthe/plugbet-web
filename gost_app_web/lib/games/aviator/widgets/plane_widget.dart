// ============================================================
// PlaneWidget + StarField — Elements visuels du jeu Aviator
// ============================================================
import 'dart:math';
import 'package:flutter/material.dart';
import 'multiplier_curve_painter.dart';

/// Avion anime qui suit la courbe de multiplicateur.
class PlaneWidget extends StatelessWidget {
  final double progress;
  final double multiplier;
  final bool crashed;

  const PlaneWidget({
    super.key,
    required this.progress,
    required this.multiplier,
    required this.crashed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pos =
            MultiplierCurvePainter.planePosition(size, progress, multiplier);

        // -45° au depart (x0), tend vers -10° en altitude
        final yRatio =
            (log(1.0 + multiplier.clamp(0.0, 9999)) / log(51)).clamp(0.0, 1.0);
        final angle = crashed
            ? pi / 4 // tombe → tourne vers le bas
            : -pi / 4 + yRatio * pi / 6;

        return Stack(
          children: [
            Positioned(
              left: pos.dx - 20,
              top: pos.dy - 20,
              child: Transform.rotate(
                angle: angle,
                child: Text(
                  crashed ? '💥' : '✈',
                  style: TextStyle(
                    fontSize: crashed ? 28 : 24,
                    shadows: [
                      Shadow(
                        color: crashed
                            ? const Color(0xFFEF4444)
                            : const Color(0xFFF97316),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fond etoile (60 points aleatoires stables).
class StarField extends StatelessWidget {
  const StarField({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StarPainter(),
      child: Container(),
    );
  }
}

class _StarPainter extends CustomPainter {
  static final _stars = List.generate(60, (i) {
    final r = Random(i * 31 + 7);
    return Offset(r.nextDouble(), r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.25);
    for (final s in _stars) {
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        0.8,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}

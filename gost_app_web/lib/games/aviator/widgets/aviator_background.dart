// ============================================================
// AVIATOR - Background dramatic : rays radiaux noirs + fond
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';

class AviatorBackground extends StatelessWidget {
  const AviatorBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [
            Color(0xFF1A1A1E),
            Color(0xFF0A0A0E),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _RadialRaysPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RadialRaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.75);
    final maxRadius =
        sqrt(size.width * size.width + size.height * size.height);

    // 24 rayons alternés noir/gris sombre depuis le centre-bas
    const nRays = 24;
    final paintDark = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    final paintLight = Paint()
      ..color = const Color(0xFF1E1E22).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final anglePerRay = (pi * 2) / nRays;
    for (int i = 0; i < nRays; i++) {
      final a1 = i * anglePerRay - pi / 2;
      final a2 = (i + 1) * anglePerRay - pi / 2;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + cos(a1) * maxRadius,
            center.dy + sin(a1) * maxRadius)
        ..lineTo(center.dx + cos(a2) * maxRadius,
            center.dy + sin(a2) * maxRadius)
        ..close();
      canvas.drawPath(path, i.isEven ? paintDark : paintLight);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

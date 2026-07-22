// ============================================================
// Plugbet – GoldOutlineText Widget
// Typographie grasse dorée avec contour noir (style jackpot / BIG WIN 777)
// ============================================================

import 'package:flutter/material.dart';

class GoldOutlineText extends StatelessWidget {
  final String text;
  final double fontSize;
  final TextAlign textAlign;
  final double outlineWidth;
  final Color outlineColor;

  const GoldOutlineText({
    super.key,
    required this.text,
    this.fontSize = 24.0,
    this.textAlign = TextAlign.center,
    this.outlineWidth = 4.0,
    this.outlineColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    const goldGradient = LinearGradient(
      colors: [
        Color(0xFFFFDF00), // Or brillant
        Color(0xFFFFB300), // Or moyen
        Color(0xFFD4AF37), // Or métallique
        Color(0xFF8C6200), // Or sombre / relief
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      stops: [0.0, 0.35, 0.75, 1.0],
    );

    return Stack(
      children: [
        // 1. Le contour (Stroke) posé en dessous
        Text(
          text,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = outlineWidth
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = outlineColor,
          ),
        ),
        // 2. Le remplissage doré (Gradient) posé au-dessus
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => goldGradient.createShader(
            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
          ),
          child: Text(
            text,
            textAlign: textAlign,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: Colors.white, // Nécessaire pour recevoir le ShaderMask
            ),
          ),
        ),
      ],
    );
  }
}

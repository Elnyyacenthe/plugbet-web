import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';
import '../../services/audio_service.dart';

class PawnComponent extends PositionComponent {
  final Color color;
  final int playerIndex;
  final int pawnIndex;
  final void Function(int)? onTap;
  final double cellSize;

  bool isHighlighted = false;
  bool isSelected = false;
  bool isAnimating = false;

  double _glowPhase = 0;

  PawnComponent({
    required this.color,
    required this.playerIndex,
    required this.pawnIndex,
    required this.cellSize,
    this.onTap,
    required Vector2 position,
  }) : super(
          position: position,
          size: Vector2.all(cellSize),
          anchor: Anchor.topLeft,
        );

  Vector2 get centerPos => position + size / 2;

  @override
  void update(double dt) {
    super.update(dt);
    if (isHighlighted || isSelected) {
      _glowPhase += dt * 4;
    }
  }

  @override
  void render(Canvas canvas) {
    final centerX = size.x / 2;
    final pinRadius = cellSize * 0.30;
    // Le centre du cercle est place plus haut pour laisser place a la pointe
    final circleCenter = Offset(centerX, size.y * 0.35);
    final pinTip = Offset(centerX, size.y * 0.78);

    // Halo pulse pour pion selectionnable/selectionne
    if (isSelected || isHighlighted) {
      final pulseAlpha = 0.3 + 0.2 * sin(_glowPhase);
      final haloColor = isSelected ? Colors.white : Colors.yellow;
      final haloPaint = Paint()
        ..color = haloColor.withValues(alpha: pulseAlpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3 : 2;
      canvas.drawCircle(circleCenter, pinRadius + 5, haloPaint);
    }

    // Ombre portee
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    _drawPinShape(canvas, circleCenter + const Offset(1.5, 2.5),
        pinTip + const Offset(1.5, 2.5), pinRadius, shadowPaint);

    // Corps du pin — gradient
    final gradient = RadialGradient(
      center: const Alignment(-0.3, -0.4),
      colors: [
        Color.lerp(color, Colors.white, 0.35)!,
        color,
        Color.lerp(color, Colors.black, 0.25)!,
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    final bodyPaint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: circleCenter, radius: pinRadius),
      );
    _drawPinShape(canvas, circleCenter, pinTip, pinRadius, bodyPaint);

    // Bordure blanche
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _drawPinShape(canvas, circleCenter, pinTip, pinRadius, borderPaint);

    // Petit cercle blanc a l'interieur (style de l'image reference)
    final innerCirclePaint = Paint()..color = Colors.white;
    canvas.drawCircle(circleCenter, pinRadius * 0.4, innerCirclePaint);
  }

  /// Dessine la forme de marqueur de localisation (pin/teardrop)
  void _drawPinShape(
    Canvas canvas,
    Offset circleCenter,
    Offset tip,
    double radius,
    Paint paint,
  ) {
    final path = Path();

    // Angle ou le cercle rencontre les lignes tangentes vers la pointe
    const tangentAngle = 0.45; // ~25 degres

    // Arc du cercle (partie superieure)
    path.addArc(
      Rect.fromCircle(center: circleCenter, radius: radius),
      pi * 0.5 + tangentAngle,
      pi * 2 - tangentAngle * 2,
    );

    // Lignes vers la pointe
    path.lineTo(tip.dx, tip.dy);
    path.close();

    canvas.drawPath(path, paint);
  }

  /// Anime le pion le long d'un chemin de waypoints
  Future<void> animateAlongPath(List<Vector2> waypoints) async {
    if (waypoints.isEmpty) return;
    isAnimating = true;

    for (final wp in waypoints) {
      final moveEffect = MoveEffect.to(
        wp,
        EffectController(duration: 0.12, curve: Curves.easeInOut),
      );
      add(moveEffect);

      // Attendre que le mouvement finisse
      await Future.delayed(const Duration(milliseconds: 130));
      AudioService.instance.playPawnMove();
    }

    isAnimating = false;
  }

  /// Teleporte le pion sans animation (pour sync initiale)
  void teleportTo(Vector2 pos) {
    position = pos;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    final center = size / 2;
    final radius = cellSize * 0.35;
    return point.distanceTo(center) <= radius + 6;
  }
}

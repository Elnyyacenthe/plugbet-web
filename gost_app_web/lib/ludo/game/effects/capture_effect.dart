import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

class CaptureEffect extends Component {
  final Vector2 effectPosition;
  final Color color;

  CaptureEffect({required this.effectPosition, required this.color});

  @override
  Future<void> onLoad() async {
    final rng = Random();

    // Explosion de particules
    final particle = Particle.generate(
      count: 24,
      lifespan: 0.6,
      generator: (i) {
        final angle = rng.nextDouble() * 2 * pi;
        final speed = 60 + rng.nextDouble() * 120;
        final velocity = Vector2(cos(angle), sin(angle)) * speed;
        final particleColor = Color.lerp(color, Colors.yellow, rng.nextDouble() * 0.5)!;

        return AcceleratedParticle(
          speed: velocity,
          acceleration: Vector2(0, 80),
          child: CircleParticle(
            radius: 2 + rng.nextDouble() * 3,
            paint: Paint()..color = particleColor.withValues(alpha: 0.8),
          ),
        );
      },
    );

    add(ParticleSystemComponent(
      particle: particle,
      position: effectPosition,
    ));

    // Flash circulaire qui s'expand
    add(_FlashCircle(position: effectPosition, color: color));

    // Auto-remove apres la duree
    add(TimerComponent(
      period: 1.0,
      removeOnFinish: true,
      onTick: () => removeFromParent(),
    ));
  }
}

class _FlashCircle extends PositionComponent {
  final Color color;
  double _elapsed = 0;
  static const double _duration = 0.4;

  _FlashCircle({required Vector2 position, required this.color})
      : super(position: position, anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final progress = _elapsed / _duration;
    final radius = 10 + progress * 40;
    final alpha = (1.0 - progress).clamp(0.0, 1.0);

    final paint = Paint()
      ..color = color.withValues(alpha: alpha * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * (1 - progress);

    canvas.drawCircle(Offset.zero, radius, paint);
  }
}

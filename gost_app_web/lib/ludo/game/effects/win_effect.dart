import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

class WinEffect extends Component {
  final Vector2 boardSize;

  WinEffect({required this.boardSize});

  @override
  Future<void> onLoad() async {
    final rng = Random();
    const colors = [
      Color(0xFF00E676),
      Color(0xFFFFD600),
      Color(0xFF448AFF),
      Color(0xFFFF1744),
      Colors.white,
    ];

    // 3 bursts de confettis espaces
    for (int burst = 0; burst < 3; burst++) {
      await Future.delayed(Duration(milliseconds: burst * 400));

      if (!isMounted) return;

      final particle = Particle.generate(
        count: 30,
        lifespan: 1.5,
        generator: (i) {
          final color = colors[rng.nextInt(colors.length)];
          final angle = -pi / 2 + (rng.nextDouble() - 0.5) * pi;
          final speed = 100 + rng.nextDouble() * 200;
          final velocity = Vector2(cos(angle), sin(angle)) * speed;

          return AcceleratedParticle(
            speed: velocity,
            acceleration: Vector2(0, 150),
            child: CircleParticle(
              radius: 2 + rng.nextDouble() * 4,
              paint: Paint()..color = color.withValues(alpha: 0.9),
            ),
          );
        },
      );

      add(ParticleSystemComponent(
        particle: particle,
        position: Vector2(boardSize.x / 2, boardSize.y * 0.7),
      ));
    }

    add(TimerComponent(
      period: 3.0,
      removeOnFinish: true,
      onTick: () => removeFromParent(),
    ));
  }
}

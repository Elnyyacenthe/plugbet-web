// ============================================================
// WinOverlay — Overlay "BIG WIN" / "JACKPOT" + pluie de pieces
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/slot_models.dart';

class WinOverlay extends StatefulWidget {
  final SpinResult result;
  final VoidCallback onDismiss;

  const WinOverlay({super.key, required this.result, required this.onDismiss});

  @override
  State<WinOverlay> createState() => _WinOverlayState();
}

class _WinOverlayState extends State<WinOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final List<_Coin> _coins;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
    _scale = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.3, curve: Curves.elasticOut)),
    );
    final n = widget.result.isJackpot ? 40 : 20;
    _coins = List.generate(n, (_) => _Coin.random(_rng));
    // Auto dismiss apres 3s
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final label = r.winLabel ?? 'WIN';
    final isJackpot = r.isJackpot;
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Stack(children: [
          // Pluie de pieces
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final size = MediaQuery.of(context).size;
              return Stack(
                children: _coins.map((c) {
                  final t = _ctrl.value;
                  final y = (c.startY + t * (size.height + 100)) % (size.height + 100);
                  return Positioned(
                    left: c.x * size.width,
                    top: y - 50,
                    child: Transform.rotate(
                      angle: t * c.rot,
                      child: Text(
                        '🪙',
                        style: TextStyle(fontSize: c.size),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          // Texte central
          Center(
            child: ScaleTransition(
              scale: _scale,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isJackpot ? AppColors.neonRed : AppColors.neonYellow,
                    fontSize: isJackpot ? 56 : 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    shadows: [
                      Shadow(
                        color: (isJackpot
                                ? AppColors.neonRed
                                : AppColors.neonYellow)
                            .withValues(alpha: 0.8),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.neonGreen,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonGreen.withValues(alpha: 0.5),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Text(
                    '+${r.payout} FCFA',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '×${r.multiplier}',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Coin {
  final double x;       // 0..1
  final double startY;  // px depart
  final double size;
  final double rot;
  _Coin(this.x, this.startY, this.size, this.rot);

  factory _Coin.random(Random rng) => _Coin(
        rng.nextDouble(),
        -100 - rng.nextDouble() * 400,
        18 + rng.nextDouble() * 18,
        (rng.nextDouble() - 0.5) * 8,
      );
}

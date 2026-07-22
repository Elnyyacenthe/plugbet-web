// ============================================================
// LUDO V2 — Dice Widget (animated, premium redesign)
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class LudoV2DiceWidget extends StatefulWidget {
  final int? value;
  final bool enabled;
  final bool rolling;
  final VoidCallback? onTap;

  const LudoV2DiceWidget({
    super.key,
    this.value,
    this.enabled = false,
    this.rolling = false,
    this.onTap,
  });

  @override
  State<LudoV2DiceWidget> createState() => _LudoV2DiceWidgetState();
}

class _LudoV2DiceWidgetState extends State<LudoV2DiceWidget>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;
  late AnimationController _pulseCtrl;
  int _displayValue = 1;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _ctrl.addListener(() {
      if (_ctrl.isAnimating) {
        setState(() => _displayValue = _rng.nextInt(6) + 1);
      }
    });
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.value != null) {
        setState(() => _displayValue = widget.value!);
      }
    });

    // Pulsation douce du halo néon quand le dé est jouable.
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.enabled) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(LudoV2DiceWidget old) {
    super.didUpdateWidget(old);
    if (widget.rolling && !old.rolling) {
      _ctrl.forward(from: 0);
    }
    if (widget.value != null && widget.value != old.value && !_ctrl.isAnimating) {
      setState(() => _displayValue = widget.value!);
    }
    if (widget.enabled != old.enabled) {
      if (widget.enabled) {
        _pulseCtrl.repeat(reverse: true);
      } else {
        _pulseCtrl.stop();
        _pulseCtrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 56.0;

    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ctrl, _pulseCtrl]),
        builder: (_, __) {
          final pulse = widget.enabled ? _pulseCtrl.value : 0.0;
          final glowStrength = 0.35 + (pulse * 0.35);
          final glowRadius = 12.0 + (pulse * 8.0);

          return Transform.rotate(
            angle: _ctrl.isAnimating ? _ctrl.value * pi * 4 : 0,
            child: Transform.scale(
              scale: widget.enabled ? 1.0 + (pulse * 0.04) : 1.0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  gradient: widget.enabled
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white,
                            AppColors.neonGreen.withValues(alpha: 0.10),
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.bgCard,
                            AppColors.bgDark,
                          ],
                        ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.enabled
                        ? AppColors.neonGreen.withValues(alpha: 0.9)
                        : AppColors.divider,
                    width: widget.enabled ? 1.5 : 1,
                  ),
                  boxShadow: [
                    if (widget.enabled)
                      BoxShadow(
                        color: AppColors.neonGreen.withValues(alpha: glowStrength),
                        blurRadius: glowRadius,
                        spreadRadius: 1.5,
                      ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Reflet glossy en haut du dé pour un rendu premium.
                    Positioned(
                      top: 3,
                      left: 6,
                      right: 6,
                      child: Container(
                        height: size * 0.28,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: widget.enabled ? 0.35 : 0.08),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    CustomPaint(
                      size: Size(size, size),
                      painter: _DiceFacePainter(_displayValue),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DiceFacePainter extends CustomPainter {
  final int value;
  _DiceFacePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.085;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final offset = size.width * 0.25;

    final positions = <Offset>[];

    switch (value) {
      case 1:
        positions.add(Offset(cx, cy));
        break;
      case 2:
        positions.addAll([Offset(cx - offset, cy - offset), Offset(cx + offset, cy + offset)]);
        break;
      case 3:
        positions.addAll([Offset(cx - offset, cy - offset), Offset(cx, cy), Offset(cx + offset, cy + offset)]);
        break;
      case 4:
        positions.addAll([
          Offset(cx - offset, cy - offset), Offset(cx + offset, cy - offset),
          Offset(cx - offset, cy + offset), Offset(cx + offset, cy + offset),
        ]);
        break;
      case 5:
        positions.addAll([
          Offset(cx - offset, cy - offset), Offset(cx + offset, cy - offset),
          Offset(cx, cy),
          Offset(cx - offset, cy + offset), Offset(cx + offset, cy + offset),
        ]);
        break;
      case 6:
        positions.addAll([
          Offset(cx - offset, cy - offset), Offset(cx + offset, cy - offset),
          Offset(cx - offset, cy), Offset(cx + offset, cy),
          Offset(cx - offset, cy + offset), Offset(cx + offset, cy + offset),
        ]);
        break;
    }

    for (final p in positions) {
      // Ombre douce sous chaque point pour donner du relief.
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      canvas.drawCircle(p.translate(0.6, 0.8), r, shadowPaint);

      // Point avec un léger dégradé radial pour un effet premium "bille".
      final dotPaint = Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xFF33334D), Color(0xFF14141F)],
          center: const Alignment(-0.3, -0.3),
        ).createShader(Rect.fromCircle(center: p, radius: r * 1.4));
      canvas.drawCircle(p, r, dotPaint);

      // Micro-reflet pour la brillance.
      final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
      canvas.drawCircle(p.translate(-r * 0.28, -r * 0.28), r * 0.28, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(_DiceFacePainter old) => old.value != value;
}

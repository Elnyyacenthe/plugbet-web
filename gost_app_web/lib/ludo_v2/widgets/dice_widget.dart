// ============================================================
// LUDO V2 — Dice Widget (animated)
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';

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
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
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
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = 56.0;

    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.rotate(
          angle: _ctrl.isAnimating ? _ctrl.value * pi * 4 : 0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: widget.enabled ? Colors.white : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.enabled ? const Color(0xFF00E676) : Colors.grey,
                width: widget.enabled ? 3 : 1,
              ),
              boxShadow: [
                if (widget.enabled)
                  BoxShadow(
                    color: const Color(0xFF00E676).withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CustomPaint(
              painter: _DiceFacePainter(_displayValue),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiceFacePainter extends CustomPainter {
  final int value;
  _DiceFacePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = const Color(0xFF1A1A2E);
    final r = size.width * 0.08;
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
      canvas.drawCircle(p, r, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_DiceFacePainter old) => old.value != value;
}

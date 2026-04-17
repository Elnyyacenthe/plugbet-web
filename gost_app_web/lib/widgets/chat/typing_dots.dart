// ============================================================
// TypingDots — Animation "en train d'ecrire" (3 points sautants)
// ============================================================
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final offset = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
          final opacity = (1 - (offset - 0.5).abs() * 2).clamp(0.3, 1.0);
          return Container(
            width: 5,
            height: 5,
            margin: EdgeInsets.only(right: i < 2 ? 3 : 0),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

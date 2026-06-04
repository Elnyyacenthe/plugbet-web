// ============================================================
// ChipSelector — Selecteur de jeton (25, 100, 500, 5k, 10k, 40k)
// ============================================================

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/wheel_models.dart';

class ChipSelector extends StatelessWidget {
  final int selected;
  final bool disabled;
  final ValueChanged<int> onPick;

  const ChipSelector({
    super.key,
    required this.selected,
    required this.onPick,
    this.disabled = false,
  });

  // Couleurs canoniques des jetons casino
  Color _color(int chip) {
    switch (chip) {
      case 25:    return const Color(0xFF1976D2);
      case 100:   return const Color(0xFF388E3C);
      case 500:   return const Color(0xFFD32F2F);
      case 5000:  return const Color(0xFF7B1FA2);
      case 10000: return const Color(0xFFFFA000);
      case 40000: return const Color(0xFFFFD600);
      default:    return AppColors.bgElevated;
    }
  }

  String _label(int chip) {
    if (chip >= 1000) return '${chip ~/ 1000}k';
    return '$chip';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: kChipDenominations.length,
        itemBuilder: (_, i) {
          final chip = kChipDenominations[i];
          final isSelected = chip == selected;
          final c = _color(chip);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: GestureDetector(
              onTap: disabled ? null : () => onPick(chip),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c,
                      c.withValues(alpha: 0.7),
                    ],
                  ),
                  border: Border.all(
                    color: isSelected ? Colors.white : c.withValues(alpha: 0.4),
                    width: isSelected ? 3 : 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: c.withValues(alpha: 0.6),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  _label(chip),
                  style: TextStyle(
                    color: chip == 40000 ? Colors.black : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    shadows: const [
                      Shadow(color: Colors.black45, blurRadius: 1),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

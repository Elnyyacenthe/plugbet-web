// ============================================================
// BetSelector — Boutons de mise (10/50/100/500/1000 FCFA)
// ============================================================

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/slot_models.dart';

class BetSelector extends StatelessWidget {
  final int current;
  final bool disabled;
  final ValueChanged<int> onChanged;

  const BetSelector({
    super.key,
    required this.current,
    required this.onChanged,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: kBetLevels.map((b) {
          final selected = b == current;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: disabled ? null : () => onChanged(b),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.neonGreen
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.neonGreen
                        : Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.neonGreen.withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: Text('$b FCFA',
                    style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

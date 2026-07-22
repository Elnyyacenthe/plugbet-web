// ============================================================
// Apple of Fortune – Multiplier column (left side)
// ============================================================
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class MultiplierColumn extends StatelessWidget {
  final List<double> multipliers;
  final int currentRow; // -1 = not started, 0..n = active row
  final bool isLost;

  const MultiplierColumn({
    super.key,
    required this.multipliers,
    required this.currentRow,
    this.isLost = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(multipliers.length, (i) {
        // Rows are displayed top=highest, bottom=lowest
        final rowIndex = multipliers.length - 1 - i;
        final mult = multipliers[rowIndex];
        final isReached = rowIndex < currentRow;
        final isActive = rowIndex == currentRow;
        final isLostRow = isLost && isActive;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: isLostRow
                  ? LinearGradient(colors: [
                      AppColors.neonRed.withValues(alpha: 0.28),
                      AppColors.neonRed.withValues(alpha: 0.10),
                    ])
                  : isActive
                      ? LinearGradient(colors: [
                          AppColors.neonGreen.withValues(alpha: 0.24),
                          AppColors.neonGreen.withValues(alpha: 0.08),
                        ])
                      : isReached
                          ? LinearGradient(colors: [
                              AppColors.neonGreen.withValues(alpha: 0.12),
                              AppColors.neonGreen.withValues(alpha: 0.04),
                            ])
                          : null,
              color: (isLostRow || isActive || isReached)
                  ? null
                  : AppColors.bgCard.withValues(alpha: 0.4),
              border: Border.all(
                color: isLostRow
                    ? AppColors.neonRed.withValues(alpha: 0.55)
                    : isActive
                        ? AppColors.neonGreen.withValues(alpha: 0.55)
                        : isReached
                            ? AppColors.neonGreen.withValues(alpha: 0.22)
                            : AppColors.divider.withValues(alpha: 0.3),
                width: isActive ? 1.5 : 1.0,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppColors.neonGreen.withValues(alpha: 0.35),
                        blurRadius: 10,
                      ),
                    ]
                  : isLostRow
                      ? [
                          BoxShadow(
                            color: AppColors.neonRed.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
            ),
            child: Text(
              'x${mult.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: isLostRow
                    ? AppColors.neonRed
                    : isActive
                        ? AppColors.neonGreen
                        : isReached
                            ? AppColors.neonGreen.withValues(alpha: 0.7)
                            : AppColors.textMuted,
              ),
            ),
          ),
        );
      }),
    );
  }
}

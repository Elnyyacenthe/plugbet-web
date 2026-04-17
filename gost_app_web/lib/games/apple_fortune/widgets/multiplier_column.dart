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
              borderRadius: BorderRadius.circular(8),
              color: isLostRow
                  ? const Color(0xFFFF1744).withValues(alpha: 0.2)
                  : isActive
                      ? const Color(0xFF00E676).withValues(alpha: 0.15)
                      : isReached
                          ? const Color(0xFF00E676).withValues(alpha: 0.08)
                          : Colors.transparent,
              border: Border.all(
                color: isLostRow
                    ? const Color(0xFFFF1744).withValues(alpha: 0.5)
                    : isActive
                        ? const Color(0xFF00E676).withValues(alpha: 0.5)
                        : isReached
                            ? const Color(0xFF00E676).withValues(alpha: 0.2)
                            : const Color(0xFF2A3F5F).withValues(alpha: 0.3),
                width: isActive ? 1.5 : 1.0,
              ),
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

// ============================================================
// Plugbet – Barre de statistique animée
// Barre horizontale proportionnelle (domicile vs extérieur)
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatBar extends StatelessWidget {
  final String label;
  final num homeValue;
  final num awayValue;
  final String? suffix;

  const StatBar({
    super.key,
    required this.label,
    required this.homeValue,
    required this.awayValue,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final total = (homeValue + awayValue).toDouble();
    final homeRatio = total > 0 ? homeValue / total : 0.5;
    final awayRatio = total > 0 ? awayValue / total : 0.5;

    final homeText = suffix != null ? '$homeValue$suffix' : '$homeValue';
    final awayText = suffix != null ? '$awayValue$suffix' : '$awayValue';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // Label + valeurs
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                homeText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: homeValue > awayValue
                      ? AppColors.neonGreen
                      : AppColors.textPrimary,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                awayText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: awayValue > homeValue
                      ? AppColors.neonGreen
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),

          // Barre de progression double
          Row(
            children: [
              // Barre domicile (droite → gauche)
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: homeRatio.toDouble(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      height: 4,
                      decoration: BoxDecoration(
                        color: homeValue >= awayValue
                            ? AppColors.neonGreen
                            : AppColors.textMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 4),
              // Barre extérieur (gauche → droite)
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: awayRatio.toDouble(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      height: 4,
                      decoration: BoxDecoration(
                        color: awayValue >= homeValue
                            ? AppColors.neonGreen
                            : AppColors.textMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BetTile — Tuile de mise (1, 2, 5, 10, 20, 40)
// ============================================================
// Tap = depose un jeton (selectionne). Long press = retire tout.
// Affiche le stack de jetons en haut + le montant total mise dessous.
// ============================================================

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/wheel_models.dart';

class BetTile extends StatelessWidget {
  final WheelTile tile;
  final int chips;          // somme misee sur cette tuile (FCFA)
  final bool isWinning;     // highlight si tuile gagnante du dernier spin
  final bool disabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const BetTile({
    super.key,
    required this.tile,
    required this.chips,
    this.isWinning = false,
    this.disabled = false,
    this.onTap,
    this.onLongPress,
  });

  Color get _color {
    switch (tile.value) {
      case 40: return const Color(0xFFFFD600); // or
      case 20: return const Color(0xFFB0BEC5); // argent
      case 10: return const Color(0xFFFFA000);
      case 5:  return const Color(0xFF7B1FA2);
      case 2:  return const Color(0xFFD32F2F);
      case 1:  return const Color(0xFF1976D2);
      default: return AppColors.bgElevated;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasChips = chips > 0;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      onLongPress: disabled ? null : onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [
              _color.withValues(alpha: 0.95),
              _color.withValues(alpha: 0.65),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isWinning
                ? AppColors.neonYellow
                : hasChips
                    ? Colors.white
                    : _color.withValues(alpha: 0.4),
            width: isWinning ? 3 : (hasChips ? 1.5 : 1),
          ),
          boxShadow: [
            if (isWinning)
              BoxShadow(
                color: AppColors.neonYellow.withValues(alpha: 0.7),
                blurRadius: 14,
              ),
            if (hasChips && !isWinning)
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.18),
                blurRadius: 6,
              ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Numero
            Text(
              '${tile.value}',
              style: TextStyle(
                color: tile.value == 40 ? Colors.black : Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                shadows: const [
                  Shadow(color: Colors.black45, blurRadius: 2),
                ],
              ),
            ),
            const SizedBox(height: 2),
            // Multiplicateur reference (×(N+1) total)
            Text(
              '×${tile.value + 1}',
              style: TextStyle(
                color: (tile.value == 40 ? Colors.black : Colors.white)
                    .withValues(alpha: 0.75),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            // Stack de jetons
            if (hasChips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$chips',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CategoryFilter — ligne horizontale de puces filtre
// ============================================================

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/game_category.dart';

class CategoryFilter extends StatelessWidget {
  final Set<GameCategory> available;
  final GameCategory? selected;
  final ValueChanged<GameCategory?> onChanged;
  const CategoryFilter({
    super.key,
    required this.available,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cats = available.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip(label: 'Tous', icon: Icons.apps_rounded, active: selected == null,
              onTap: () => onChanged(null)),
          const SizedBox(width: 8),
          for (final c in cats) ...[
            _chip(label: c.label, icon: c.icon, active: selected == c,
                onTap: () => onChanged(c)),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label, required IconData icon,
    required bool active, required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.neonGreen.withValues(alpha: 0.18)
              : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (active ? AppColors.neonGreen : AppColors.divider)
                .withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14,
                color: active ? AppColors.neonGreen : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  color: active ? AppColors.neonGreen : AppColors.textPrimary,
                  fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

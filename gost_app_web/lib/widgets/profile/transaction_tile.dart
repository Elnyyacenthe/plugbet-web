// ============================================================
// TransactionTile — Item d'historique de transaction wallet
// Extrait de profile_screen.dart
// ============================================================
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class TransactionTile extends StatelessWidget {
  final String label;
  final int amount;
  final DateTime date;
  final String type; // 'game' | 'bet' | 'refund' | 'deposit' | 'withdrawal' | 'pending' | 'failed'

  const TransactionTile({
    super.key,
    required this.label,
    required this.amount,
    required this.date,
    required this.type,
  });

  IconData get _icon {
    switch (type) {
      case 'game':
        return Icons.emoji_events;
      case 'bet':
        return Icons.casino;
      case 'refund':
        return Icons.replay;
      case 'deposit':
        return Icons.add_circle_outline;
      case 'withdrawal':
        return Icons.remove_circle_outline;
      case 'pending':
        return Icons.access_time;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.swap_horiz;
    }
  }

  Color _color() {
    // Couleurs spécifiques pour certains types
    switch (type) {
      case 'pending':
        return AppColors.neonYellow;
      case 'failed':
        return AppColors.neonRed;
      case 'deposit':
        return AppColors.neonGreen;
      case 'withdrawal':
        return AppColors.neonOrange;
      default:
        // Par défaut : vert si positif, rouge si négatif, gris si zéro
        if (amount > 0) return AppColors.neonGreen;
        if (amount < 0) return AppColors.neonRed;
        return AppColors.textMuted;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final isPositive = amount > 0;
    final color = _color();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(date),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
          Text(
            amount == 0 ? '—' : '${isPositive ? '+' : ''}$amount',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (amount != 0)
            Icon(Icons.monetization_on,
                color: AppColors.neonYellow, size: 14),
        ],
      ),
    );
  }
}

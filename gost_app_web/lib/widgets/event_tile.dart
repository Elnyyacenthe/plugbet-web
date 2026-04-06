// ============================================================
// Plugbet – Tile d'événement (timeline)
// Heure à gauche, icône animée au centre, description à droite
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/football_models.dart';

class EventTile extends StatelessWidget {
  final MatchEvent event;
  final int index;

  const EventTile({
    super.key,
    required this.event,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Minute (à gauche) ---
            SizedBox(
              width: 44,
              child: Text(
                "${event.minute}'",
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _minuteColor,
                ),
              ),
            ),
            SizedBox(width: 12),

            // --- Icône animée (centre) ---
            _eventIcon(),
            SizedBox(width: 12),

            // --- Description (droite) ---
            Expanded(
              child: Column(
                crossAxisAlignment: event.isHomeTeam
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(
                    event.playerName ?? 'Inconnu',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (event.assistPlayerName != null)
                    Text(
                      'Passe de ${event.assistPlayerName}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  if (event.detail != null && event.detail!.isNotEmpty)
                    Text(
                      _eventDetailLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: _detailColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Color get _minuteColor {
    switch (event.eventType) {
      case EventType.goal:
      case EventType.penalty:
        return AppColors.neonGreen;
      case EventType.ownGoal:
        return AppColors.neonRed;
      case EventType.yellowCard:
        return AppColors.neonYellow;
      case EventType.redCard:
        return AppColors.neonRed;
      case EventType.substitution:
        return AppColors.neonPurple;
      case EventType.varDecision:
        return AppColors.neonOrange;
      default:
        return AppColors.textSecondary;
    }
  }

  Color get _detailColor => _minuteColor;

  String get _eventDetailLabel {
    switch (event.eventType) {
      case EventType.goal:
        return 'But !';
      case EventType.penalty:
        return 'Penalty';
      case EventType.ownGoal:
        return 'But contre son camp';
      case EventType.yellowCard:
        return 'Carton jaune';
      case EventType.redCard:
        return 'Carton rouge';
      case EventType.substitution:
        return 'Remplacement';
      case EventType.varDecision:
        return 'Décision VAR';
      default:
        return event.detail ?? '';
    }
  }

  Widget _eventIcon() {
    IconData icon;
    Color color;
    Color bgColor;

    switch (event.eventType) {
      case EventType.goal:
      case EventType.penalty:
        icon = Icons.sports_soccer;
        color = AppColors.neonGreen;
        bgColor = AppColors.neonGreen.withValues(alpha: 0.15);
        break;
      case EventType.ownGoal:
        icon = Icons.sports_soccer;
        color = AppColors.neonRed;
        bgColor = AppColors.neonRed.withValues(alpha: 0.15);
        break;
      case EventType.yellowCard:
        icon = Icons.rectangle;
        color = AppColors.neonYellow;
        bgColor = AppColors.neonYellow.withValues(alpha: 0.15);
        break;
      case EventType.redCard:
        icon = Icons.rectangle;
        color = AppColors.neonRed;
        bgColor = AppColors.neonRed.withValues(alpha: 0.15);
        break;
      case EventType.substitution:
        icon = Icons.swap_horiz;
        color = AppColors.neonPurple;
        bgColor = AppColors.neonPurple.withValues(alpha: 0.15);
        break;
      case EventType.varDecision:
        icon = Icons.tv;
        color = AppColors.neonOrange;
        bgColor = AppColors.neonOrange.withValues(alpha: 0.15);
        break;
      default:
        icon = Icons.info_outline;
        color = AppColors.textMuted;
        bgColor = AppColors.bgCardLight;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

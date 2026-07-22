// ============================================================
// FANTASY MODULE – Player Card Widget
// Card compact pour liste transferts / top performers
// ============================================================

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../models/fpl_models.dart';

class FplPlayerCard extends StatelessWidget {
  final FplElement player;
  final FplTeam? team;
  final int? livePoints;
  final bool showPrice;
  final bool showForm;
  final bool showOwnership;
  final VoidCallback? onTap;
  final Widget? actionWidget;

  const FplPlayerCard({
    super.key,
    required this.player,
    this.team,
    this.livePoints,
    this.showPrice = true,
    this.showForm = true,
    this.showOwnership = false,
    this.onTap,
    this.actionWidget,
  });

  @override
  Widget build(BuildContext context) {
    final posColor = _posColor(player.elementType);
    final hasInjury = player.chanceOfPlayingNextRound < 75;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(color: posColor, width: 3),
            top: BorderSide(color: AppColors.divider.withValues(alpha: 0.4)),
            right: BorderSide(color: AppColors.divider.withValues(alpha: 0.4)),
            bottom: BorderSide(color: AppColors.divider.withValues(alpha: 0.4)),
          ),
          boxShadow: [
            BoxShadow(color: posColor.withValues(alpha: 0.10), blurRadius: 10),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 7,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            // Médaillon position 3D (dôme + reflet + glow)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  colors: [
                    Color.lerp(posColor, Colors.white, 0.45)!,
                    posColor,
                    Color.lerp(posColor, Colors.black, 0.35)!,
                  ],
                  stops: const [0, 0.55, 1],
                ),
                boxShadow: [
                  const BoxShadow(
                      color: Colors.black45,
                      blurRadius: 3,
                      offset: Offset(0, 2)),
                  BoxShadow(
                      color: posColor.withValues(alpha: 0.35), blurRadius: 7),
                ],
              ),
              child: Center(
                child: Text(
                  player.positionLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                          color: Colors.black87,
                          blurRadius: 2,
                          offset: Offset(0, 1))
                    ],
                  ),
                ),
              ),
            ),

            SizedBox(width: 10),

            // Infos joueur
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        player.webName,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      if (hasInjury) ...[
                        SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.neonRed.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${player.chanceOfPlayingNextRound}%',
                            style: TextStyle(
                              color: AppColors.neonRed,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 2),
                  Text(
                    team?.shortName ?? '',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            // Stats droite
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showPrice)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monetization_on,
                          color: AppColors.neonGreen, size: 13),
                      SizedBox(width: 3),
                      Text(
                        '${player.coinsValue}',
                        style: TextStyle(
                          color: AppColors.neonGreen,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                if (livePoints != null) ...[
                  SizedBox(height: 2),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (livePoints! > 0 ? AppColors.neonGreen : AppColors.neonRed)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$livePoints pts',
                      style: TextStyle(
                        color: livePoints! > 0
                            ? AppColors.neonGreen
                            : AppColors.neonRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (showForm && livePoints == null) ...[
                  SizedBox(height: 2),
                  Text(
                    'Forme: ${player.form}',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
                if (showOwnership) ...[
                  SizedBox(height: 2),
                  Text(
                    '${player.selectedByPercent}% sel.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
            if (actionWidget != null) ...[
              SizedBox(width: 8),
              actionWidget!,
            ],
          ],
        ),
      ),
    );
  }

  Color _posColor(int type) {
    switch (type) {
      case 1: return AppColors.neonYellow;
      case 2: return AppColors.neonBlue;
      case 3: return AppColors.neonGreen;
      case 4: return AppColors.neonOrange;
      default: return AppColors.textSecondary;
    }
  }
}

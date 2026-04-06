// ============================================================
// Plugbet – Card de match (liste verticale)
// 100% responsive : aucun overflow possible
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/football_models.dart';
import 'team_crest.dart';
import 'score_display.dart';

class MatchCard extends StatelessWidget {
  final FootballMatch match;
  final VoidCallback? onTap;
  final int animationIndex;

  const MatchCard({
    super.key,
    required this.match,
    this.onTap,
    this.animationIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = match.status.isLive;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 360;
    final crestSize = isSmall ? 28.0 : 34.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 10 : 14,
          vertical: isSmall ? 10 : 12,
        ),
        decoration: BoxDecoration(
          gradient: isLive ? AppColors.liveGradient : AppColors.cardGradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLive
                ? AppColors.neonRed.withValues(alpha: 0.35)
                : AppColors.divider.withValues(alpha: 0.6),
            width: isLive ? 0.8 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isLive
                  ? AppColors.neonRed.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Equipe domicile
            Expanded(
              flex: 3,
              child: _teamColumn(match.homeTeam, crestSize, isSmall),
            ),

            // Score central + badge statut
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (match.status.isUpcoming)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${match.dateTime.hour.toString().padLeft(2, '0')}:${match.dateTime.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: isSmall ? 16 : 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ScoreDisplay(match: match),
                    ),
                  SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: MatchStatusBadge(match: match),
                  ),
                ],
              ),
            ),

            // Equipe exterieure
            Expanded(
              flex: 3,
              child: _teamColumn(match.awayTeam, crestSize, isSmall),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamColumn(Team team, double crestSize, bool isSmall) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Écusson
        TeamCrest(team: team, size: crestSize),
        SizedBox(height: 4),
        Text(
          team.tla ?? team.shortName,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isSmall ? 10 : 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

}

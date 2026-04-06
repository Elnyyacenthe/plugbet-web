// ============================================================
// Plugbet – Card grand format pour le carousel
// Full-width, score énorme, logos, badge minute néon
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/football_models.dart';
import 'team_crest.dart';
import 'score_display.dart';

class CarouselCard extends StatelessWidget {
  final FootballMatch match;
  final VoidCallback? onTap;

  const CarouselCard({
    super.key,
    required this.match,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = match.status.isLive;
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.78).clamp(240.0, 400.0);
    final isSmallScreen = screenWidth < 360;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        margin: EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          gradient: isLive ? AppColors.liveGradient : AppColors.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLive
                ? AppColors.neonRed.withValues(alpha: 0.4)
                : AppColors.divider.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isLive
                  ? AppColors.neonRed.withValues(alpha: 0.12)
                  : Colors.black38,
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Cercles décoratifs en arrière-plan
            Positioned(
              top: -30,
              left: -30,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isLive ? AppColors.neonRed : AppColors.neonBlue)
                      .withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -20,
              right: -20,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neonGreen.withValues(alpha: 0.04),
                ),
              ),
            ),

            // Contenu principal
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 12 : 16,
                vertical: isSmallScreen ? 10 : 14,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nom de la compétition
                  Text(
                    match.competition.name,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 9 : 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isSmallScreen ? 4 : 6),

                  // Équipes + Score
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Équipe domicile
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TeamCrest(
                              team: match.homeTeam,
                              size: isSmallScreen ? 28 : 36,
                            ),
                            SizedBox(height: 4),
                            Text(
                              match.homeTeam.tla ?? match.homeTeam.shortName,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Score ou heure
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 2 : 6),
                          child: match.status.isUpcoming
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        '${match.dateTime.hour.toString().padLeft(2, '0')}:${match.dateTime.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 20 : 26,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: MatchStatusBadge(match: match),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: ScoreDisplay(
                                        match: match,
                                        isLarge: !isSmallScreen,
                                        animated: isLive,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: MatchStatusBadge(
                                        match: match,
                                        showMinute: true,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      // Équipe extérieure
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TeamCrest(
                              team: match.awayTeam,
                              size: isSmallScreen ? 28 : 36,
                            ),
                            SizedBox(height: 4),
                            Text(
                              match.awayTeam.tla ?? match.awayTeam.shortName,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 10 : 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Matchday info
                  if (match.matchday != null)
                    Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'J${match.matchday}',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LeagueRow — Ligne horizontale d'une competition avec ses matchs
// Extrait de home_screen.dart pour reduire sa taille.
// ============================================================
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/football_models.dart';
import '../../theme/app_theme.dart';
import '../score_display.dart';
import '../team_crest.dart';

class LeagueRow extends StatelessWidget {
  final Competition competition;
  final List<FootballMatch> matches;
  final void Function(int matchId) onMatchTap;

  const LeagueRow({
    super.key,
    required this.competition,
    required this.matches,
    required this.onMatchTap,
  });

  bool get _hasLive => matches.any((m) => m.status.isLive);

  @override
  Widget build(BuildContext context) {
    final logoUrl = competition.emblemUrl;
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header de la ligue
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              if (hasLogo)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: logoUrl,
                    width: 22,
                    height: 22,
                    fit: BoxFit.contain,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    memCacheWidth: 66,
                    memCacheHeight: 66,
                    filterQuality: FilterQuality.low,
                    errorWidget: (_, __, ___) => _defaultLeagueIcon(),
                  ),
                )
              else
                _defaultLeagueIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      competition.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (competition.areaName != null)
                      Text(
                        competition.areaName!,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (_hasLive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.neonRed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppColors.neonRed.withValues(alpha: 0.4),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.neonRed,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neonRed,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.neonBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${matches.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.neonBlue,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Scroll horizontal des matchs
        SizedBox(
          height: 112,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              return _MiniMatchCard(
                match: matches[index],
                onTap: () => onMatchTap(matches[index].id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _defaultLeagueIcon() {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: AppColors.neonBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.emoji_events, size: 13, color: AppColors.neonBlue),
    );
  }
}

// ============================================================
// Mini card de match pour le scroll horizontal par ligue
// ============================================================
class _MiniMatchCard extends StatelessWidget {
  final FootballMatch match;
  final VoidCallback onTap;

  const _MiniMatchCard({
    required this.match,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = match.status.isLive;
    final isUpcoming = match.status.isUpcoming;
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.38).clamp(125.0, 180.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(right: 10, top: 4, bottom: 8),
        padding: EdgeInsets.symmetric(
            horizontal: screenWidth < 360 ? 8 : 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: isLive ? AppColors.liveGradient : AppColors.cardGradient,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLive
                ? AppColors.neonRed.withValues(alpha: 0.4)
                : AppColors.divider.withValues(alpha: 0.6),
            width: isLive ? 0.8 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isLive
                  ? AppColors.neonRed.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUpcoming)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${match.dateTime.hour.toString().padLeft(2, '0')}:${match.dateTime.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              )
            else
              FittedBox(
                fit: BoxFit.scaleDown,
                child: MatchStatusBadge(match: match, showMinute: true),
              ),
            const SizedBox(height: 6),
            _teamRow(match.homeTeam, match.score.homeFullTime, isUpcoming,
                screenWidth < 360),
            const SizedBox(height: 4),
            _teamRow(match.awayTeam, match.score.awayFullTime, isUpcoming,
                screenWidth < 360),
          ],
        ),
      ),
    );
  }

  Widget _teamRow(Team team, int? score, bool isUpcoming, bool isSmall) {
    return Row(
      children: [
        TeamCrest(team: team, size: isSmall ? 16 : 18),
        SizedBox(width: isSmall ? 4 : 6),
        Expanded(
          child: Text(
            team.tla ?? team.shortName,
            style: TextStyle(
              fontSize: isSmall ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!isUpcoming)
          Text(
            '${score ?? 0}',
            style: TextStyle(
              fontSize: isSmall ? 14 : 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
      ],
    );
  }
}

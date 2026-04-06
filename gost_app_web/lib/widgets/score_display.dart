// ============================================================
// Plugbet – Affichage du score animé
// Score géant avec effets néon et bounce sur changement
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/football_models.dart';

class ScoreDisplay extends StatelessWidget {
  final FootballMatch match;
  final bool isLarge; // true = carousel / détail, false = liste
  final bool animated;

  const ScoreDisplay({
    super.key,
    required this.match,
    this.isLarge = false,
    this.animated = true,
  });

  @override
  Widget build(BuildContext context) {
    final homeScore = match.score.homeFullTime ?? 0;
    final awayScore = match.score.awayFullTime ?? 0;
    final isLive = match.status.isLive;
    final fontSize = isLarge ? 36.0 : 24.0;
    final separatorSize = isLarge ? 16.0 : 14.0;

    final hasHtScore = match.score.homeHalfTime != null &&
        match.score.awayHalfTime != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Score domicile
            Text(
              '$homeScore',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -1,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isLarge ? 12 : 6),
              child: Text(
                '-',
                style: TextStyle(
                  fontSize: separatorSize,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            // Score extérieur
            Text(
              '$awayScore',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        // Score mi-temps pour les matchs termines ou en 2eme mi-temps
        if (hasHtScore && !isLive && match.status == MatchStatus.finished)
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              '(MT: ${match.score.homeHalfTime}-${match.score.awayHalfTime})',
              style: TextStyle(
                fontSize: isLarge ? 12 : 10,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

/// Badge du statut du match (LIVE clignotant, mi-temps, terminé, etc.)
class MatchStatusBadge extends StatefulWidget {
  final FootballMatch match;
  final bool showMinute;

  const MatchStatusBadge({
    super.key,
    required this.match,
    this.showMinute = true,
  });

  @override
  State<MatchStatusBadge> createState() => _MatchStatusBadgeState();
}

class _MatchStatusBadgeState extends State<MatchStatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.match.status.isLive) {
      _blinkController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(MatchStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.match.status.isLive && !_blinkController.isAnimating) {
      _blinkController.repeat(reverse: true);
    } else if (!widget.match.status.isLive && _blinkController.isAnimating) {
      _blinkController.stop();
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.match.status;
    final minute = widget.match.displayMinute;

    Color badgeColor;
    String text;

    switch (status) {
      case MatchStatus.inPlay:
        badgeColor = AppColors.neonRed;
        if (widget.showMinute && minute != null) {
          // Distinguer 1ere/2eme mi-temps et prolongations
          if (minute > 90) {
            text = "$minute' +";
          } else if (minute > 45 && minute <= 90) {
            text = "$minute'";
          } else {
            text = "$minute'";
          }
        } else {
          text = 'LIVE';
        }
        break;
      case MatchStatus.paused:
        badgeColor = AppColors.neonOrange;
        text = 'MI-TEMPS';
        break;
      case MatchStatus.finished:
        badgeColor = AppColors.textMuted;
        text = 'TERMINE';
        break;
      case MatchStatus.scheduled:
      case MatchStatus.timed:
        badgeColor = AppColors.neonBlue;
        final time = widget.match.dateTime;
        text = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        break;
      case MatchStatus.postponed:
        badgeColor = AppColors.neonOrange;
        text = 'REPORTE';
        break;
      case MatchStatus.suspended:
        badgeColor = AppColors.neonOrange;
        text = 'SUSPENDU';
        break;
      default:
        badgeColor = AppColors.textMuted;
        text = status.label;
    }

    Widget badge = Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: badgeColor,
          letterSpacing: 0.5,
        ),
      ),
    );

    // Clignotement pour les matchs live
    if (status.isLive) {
      badge = AnimatedBuilder(
        animation: _blinkController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.4 + (_blinkController.value * 0.6),
            child: child,
          );
        },
        child: badge,
      );
    }

    return badge;
  }
}

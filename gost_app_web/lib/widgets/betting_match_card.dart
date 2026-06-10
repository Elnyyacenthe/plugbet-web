// ============================================================
// BettingMatchCard — Card de match style live-score
// ============================================================
// Layout horizontal :
//   ⭐ ⚽ Turkish Cup            🔴 LIVE 38'
//   [👕] Alanyaspor    1 — 0    Fatih Karag. [👕]
//                   1ère mi-temps
//   1X2  [1 1.62]   [X 3.90]   [2 4.60]   →
//
// Interactions :
// - Tap sur le corps de la carte (hors cotes/etoile) -> ecran detail
// - Tap simple sur une cote                          -> pari simple
// - Long press sur une cote                          -> combine (haptic)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart';
import 'bet_team_crest.dart';

class BettingMatchCard extends StatelessWidget {
  final BettingMatch match;
  final VoidCallback? onTapCard;                // -> detail screen
  final void Function(String market)? onTapOdds; // pari simple
  final void Function(String market)? onLongPressOdds; // combine
  final VoidCallback? onToggleFavorite;
  final bool isFavorite;
  final String? selectedMarket;
  /// Si true, l'utilisateur peut voir le bouton "voir plus de marches".
  final bool showMoreHint;
  /// True quand le prefetch des cotes est en cours pour cette ligue.
  /// Affiche un skeleton au lieu de "Cotes indisponibles".
  final bool oddsLoading;

  const BettingMatchCard({
    super.key,
    required this.match,
    this.onTapCard,
    this.onTapOdds,
    this.onLongPressOdds,
    this.onToggleFavorite,
    this.isFavorite = false,
    this.selectedMarket,
    this.showMoreHint = true,
    this.oddsLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = match.isLive;
    final w = MediaQuery.of(context).size.width;
    final isSmall = w < 360;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLive
              ? AppColors.neonRed.withValues(alpha: 0.35)
              : AppColors.divider.withValues(alpha: 0.5),
          width: isLive ? 1 : 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isLive
                ? AppColors.neonRed.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 5, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTapCard,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                isSmall ? 12 : 14, 12, isSmall ? 12 : 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(isLive, isSmall),
                const SizedBox(height: 12),
                _buildScoreRow(isSmall),
                if (isLive) ...[
                  const SizedBox(height: 4),
                  _buildStatusLine(),
                ],
                const SizedBox(height: 12),
                _buildOddsRow(isSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isLive, bool isSmall) {
    return Row(children: [
      InkWell(
        onTap: onToggleFavorite,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            size: 18,
            color: isFavorite ? AppColors.neonYellow : AppColors.textMuted,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Icon(_sportIcon(), size: 13, color: AppColors.textMuted),
      const SizedBox(width: 6),
      Expanded(
        child: Text(match.league,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: isSmall ? 11 : 12,
              fontWeight: FontWeight.w700,
            )),
      ),
      const SizedBox(width: 6),
      if (isLive)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.neonRed,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.fiber_manual_record, size: 6, color: Colors.white),
            const SizedBox(width: 3),
            Text("LIVE ${match.minute ?? 0}'",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                )),
          ]),
        )
      else
        Text(_formatTime(match.startTime),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: isSmall ? 10 : 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            )),
    ]);
  }

  IconData _sportIcon() {
    switch (match.sport) {
      case Sport.basketball: return Icons.sports_basketball;
      case Sport.soccer:     return Icons.sports_soccer;
    }
  }

  /// True quand le match est termine (scores presents, plus live).
  bool get _isFinished =>
      !match.isLive &&
      match.homeScore != null &&
      match.awayScore != null;

  int get _winner {
    if (!_isFinished) return 0;
    final h = match.homeScore!, a = match.awayScore!;
    if (h > a) return 1;
    if (a > h) return 2;
    return 0; // nul
  }

  Widget _buildScoreRow(bool isSmall) {
    final size = isSmall ? 30.0 : 34.0;
    final winner = _winner;
    final isFinished = _isFinished;

    Color teamColor(bool isHome) {
      if (!isFinished) return AppColors.textPrimary;
      final w = winner;
      if (w == 0) return AppColors.textPrimary;
      if ((w == 1 && isHome) || (w == 2 && !isHome)) {
        return AppColors.neonGreen;
      }
      return AppColors.textMuted;
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      BetTeamCrest(
        name: match.homeName, logoUrl: match.homeLogo,
        sport: match.sport, size: size),
      const SizedBox(width: 10),
      Expanded(
        child: Row(children: [
          if (isFinished && winner == 1)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle_rounded,
                  size: 14, color: AppColors.neonGreen),
            ),
          Flexible(
            child: Text(match.homeName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: teamColor(true),
                  fontSize: isSmall ? 13 : 14,
                  fontWeight: FontWeight.w800,
                )),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      _scoreOrTime(isSmall),
      const SizedBox(width: 8),
      Expanded(
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Flexible(
            child: Text(match.awayName,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: teamColor(false),
                  fontSize: isSmall ? 13 : 14,
                  fontWeight: FontWeight.w800,
                )),
          ),
          if (isFinished && winner == 2)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.check_circle_rounded,
                  size: 14, color: AppColors.neonGreen),
            ),
        ]),
      ),
      const SizedBox(width: 10),
      BetTeamCrest(
        name: match.awayName, logoUrl: match.awayLogo,
        sport: match.sport, size: size),
    ]);
  }

  Widget _scoreOrTime(bool isSmall) {
    // Affiche le score si dispo (live OU termine). Sinon "VS".
    if (match.homeScore != null && match.awayScore != null) {
      final isFinished = _isFinished;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('${match.homeScore} — ${match.awayScore}',
            style: TextStyle(
              color: isFinished
                  ? AppColors.textPrimary
                  : AppColors.neonYellow,
              fontSize: isSmall ? 16 : 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            )),
      );
    }
    return Text('VS',
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: isSmall ? 11 : 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ));
  }

  Widget _buildStatusLine() {
    final m = match.minute ?? 0;
    final label = match.sport == Sport.basketball
        ? _statusBasketball(m)
        : _statusSoccer(m);
    return Center(
      child: Text(label,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          )),
    );
  }

  String _statusSoccer(int m) {
    if (m <= 0) return 'Coup d\'envoi';
    if (m <= 45) return '1ère mi-temps';
    if (m <= 60) return 'Mi-temps';
    if (m <= 90) return '2e mi-temps';
    return 'Prolongations';
  }

  String _statusBasketball(int m) {
    if (m <= 0) return 'Début';
    if (m <= 12) return '1er quart-temps';
    if (m <= 24) return '2e quart-temps';
    if (m <= 36) return '3e quart-temps';
    if (m <= 48) return '4e quart-temps';
    return 'Prolongations';
  }

  Widget _buildOddsRow(bool isSmall) {
    final o = match.odds;
    final unavail = o == null;
    final hasDraw = match.hasDrawMarket;

    if (unavail && oddsLoading) {
      return _buildOddsSkeleton(hasDraw, isSmall);
    }

    if (unavail) {
      return Row(children: [
        Text(hasDraw ? '1X2' : 'Moneyline',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            )),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Cotes indisponibles',
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
        ),
        if (showMoreHint)
          Icon(Icons.chevron_right_rounded,
              size: 18, color: AppColors.textMuted),
      ]);
    }

    return Row(children: [
      Expanded(child: _oddsTile('1', o.home, 'home', isSmall)),
      const SizedBox(width: 6),
      if (hasDraw) ...[
        Expanded(child: _oddsTile('X', o.draw, 'draw', isSmall)),
        const SizedBox(width: 6),
      ],
      Expanded(child: _oddsTile('2', o.away, 'away', isSmall)),
      if (showMoreHint) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Icon(Icons.chevron_right_rounded,
              size: 16, color: AppColors.textMuted),
        ),
      ],
    ]);
  }

  /// Skeleton 3 (ou 2) tiles avec un spinner subtil pendant le prefetch.
  Widget _buildOddsSkeleton(bool hasDraw, bool isSmall) {
    Widget tile() => Container(
          padding: EdgeInsets.symmetric(
              vertical: isSmall ? 8 : 10, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.bgElevated.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          alignment: Alignment.center,
          child: SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.4, color: AppColors.textMuted),
          ),
        );
    return Row(children: [
      Expanded(child: tile()),
      const SizedBox(width: 6),
      if (hasDraw) ...[
        Expanded(child: tile()),
        const SizedBox(width: 6),
      ],
      Expanded(child: tile()),
    ]);
  }

  Widget _oddsTile(String label, double? value, String marketCode, bool isSmall) {
    final disabled = value == null;
    final selected = selectedMarket == marketCode;
    return GestureDetector(
      onTap: disabled ? null : () => onTapOdds?.call(marketCode),
      onLongPress: disabled ? null : () {
        HapticFeedback.mediumImpact();
        onLongPressOdds?.call(marketCode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          vertical: isSmall ? 8 : 10,
          horizontal: 6,
        ),
        decoration: BoxDecoration(
          color: disabled
              ? AppColors.bgElevated.withValues(alpha: 0.4)
              : selected
                  ? AppColors.neonGreen.withValues(alpha: 0.18)
                  : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: disabled
                ? AppColors.divider.withValues(alpha: 0.3)
                : selected
                    ? AppColors.neonGreen
                    : AppColors.divider.withValues(alpha: 0.4),
            width: selected ? 1.4 : 0.6,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: TextStyle(
                  color: selected
                      ? AppColors.neonGreen
                      : AppColors.textMuted,
                  fontSize: isSmall ? 11 : 12,
                  fontWeight: FontWeight.w800,
                )),
            const SizedBox(width: 6),
            Text(
              disabled ? '-' : value.toStringAsFixed(2),
              style: TextStyle(
                color: disabled
                    ? AppColors.textMuted
                    : selected
                        ? AppColors.neonGreen
                        : AppColors.textPrimary,
                fontSize: isSmall ? 12 : 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

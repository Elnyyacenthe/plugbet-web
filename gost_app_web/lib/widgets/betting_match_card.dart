// ============================================================
// BettingMatchCard — Card de match style live-score
// ============================================================
// Layout horizontal :
//   [étoile] [ballon] Turkish Cup          [LIVE 38']
//   [écusson] Alanyaspor   1 — 0   Fatih Karag. [écusson]
//                   1ère mi-temps
//   [ 1  1.62 ] [ X  3.90 ] [ 2  4.60 ]  →
//
// Habillage : cadre biseauté (ReliefCard) au liseré de marque, ou vert
// quand le match est en direct. Le score est encastré dans la carte, les
// cotes sont des touches bombées qui s'enfoncent au doigt et s'allument
// en vert plein une fois sélectionnées.
//
// Interactions (inchangées) :
// - Tap sur le corps de la carte (hors cotes/etoile) -> ecran detail
// - Tap simple sur une cote                          -> pari simple
// - Long press sur une cote                          -> combine (haptic)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_icons.dart';
import '../theme/app_reliefs.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart';
import 'bet_team_crest.dart';

class BettingMatchCard extends StatelessWidget {
  final BettingMatch match;
  final VoidCallback? onTapCard; // -> detail screen
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

    return ReliefCard(
      // Le direct s'annonce par la couleur du cadre lui-même.
      accent: isLive ? AppColors.primary : AppColors.primaryInk,
      elevation: isLive ? 1.2 : 0.9,
      margin: const EdgeInsets.only(bottom: 12),
      // L'horizontal doit dépasser la morsure de l'encoche
      // (notchRadius - notchCenterInset = 12 px), sinon le creux rogne
      // les écussons.
      padding:
          EdgeInsets.fromLTRB(isSmall ? 16 : 18, 12, isSmall ? 16 : 18, 12),
      onTap: onTapCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(isLive, isSmall),
          const SizedBox(height: 12),
          _buildScoreRow(isSmall),
          if (isLive) ...[
            const SizedBox(height: 5),
            _buildStatusLine(),
          ],
          const SizedBox(height: 12),
          _buildOddsRow(isSmall),
        ],
      ),
    );
  }

  // Eligible 2Up : pre-match avec au moins une cote 1 ou 2 (home/away).
  bool get _is2UpEligible =>
      !match.isLive &&
      match.sport != Sport.tennis &&
      match.odds != null &&
      (match.odds!.home != null || match.odds!.away != null);

  Widget _buildHeader(bool isLive, bool isSmall) {
    return Row(children: [
      // GestureDetector et non InkWell : ReliefCard ne fournit pas
      // d'ancêtre Material, et l'encre n'apporte rien sur une étoile.
      GestureDetector(
        onTap: onToggleFavorite,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            isFavorite ? AppIcons.starFilled : AppIcons.star,
            size: 18,
            color: isFavorite ? AppColors.neonYellow : AppColors.textMuted,
            shadows: isFavorite
                ? [
                    Shadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.6),
                      blurRadius: 9,
                    ),
                  ]
                : null,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Icon(_sportIcon(), size: 14, color: AppColors.textMuted),
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
      // Badge 2Up : matchs pre-match eligibles au paiement anticipe (1X2 home/away).
      if (_is2UpEligible) ...[
        ReliefPill(
          label: '2UP',
          color: AppColors.primary,
          solid: true,
          fontSize: 9,
        ),
        const SizedBox(width: 6),
      ],
      if (isLive)
        ReliefPill(
          label: "LIVE ${match.minute ?? 0}'",
          icon: AppIcons.dot,
          color: AppColors.primary,
          solid: true,
          fontSize: 9,
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
      case Sport.soccer:
        return AppIcons.football;
      case Sport.basketball:
        return AppIcons.basketball;
      case Sport.americanFootball:
        return Icons.sports_football_rounded;
      case Sport.baseball:
        return Icons.sports_baseball_rounded;
      case Sport.tennis:
        return AppIcons.tennis;
      case Sport.iceHockey:
        return Icons.sports_hockey_rounded;
      case Sport.rugby:
        return Icons.sports_rugby_rounded;
      case Sport.handball:
        return Icons.sports_handball_rounded;
    }
  }

  /// True quand le match est termine (scores presents, plus live).
  bool get _isFinished =>
      !match.isLive && match.homeScore != null && match.awayScore != null;

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
        return AppColors.primaryInk;
      }
      return AppColors.textMuted;
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      BetTeamCrest(
          name: match.homeName,
          logoUrl: match.homeLogo,
          sport: match.sport,
          size: size),
      const SizedBox(width: 10),
      Expanded(
        child: Row(children: [
          if (isFinished && winner == 1)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(AppIcons.checkCircleFilled,
                  size: 14, color: AppColors.primaryInk),
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
              child: Icon(AppIcons.checkCircleFilled,
                  size: 14, color: AppColors.primaryInk),
            ),
        ]),
      ),
      const SizedBox(width: 10),
      BetTeamCrest(
          name: match.awayName,
          logoUrl: match.awayLogo,
          sport: match.sport,
          size: size),
    ]);
  }

  Widget _scoreOrTime(bool isSmall) {
    // Affiche le score si dispo (live OU termine). Sinon "VS".
    if (match.homeScore != null && match.awayScore != null) {
      final isFinished = _isFinished;
      // Le score est gravé dans la carte : puits sombre, chiffres dessus.
      return InsetPanel(
        radius: AppRadius.xs,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        baseColor: AppColors.bgDark,
        child: Text('${match.homeScore} — ${match.awayScore}',
            style: TextStyle(
              color: isFinished ? AppColors.textPrimary : AppColors.neonYellow,
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
    final label = _statusLabel(m);
    return Center(
      child: Text(label,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          )),
    );
  }

  String _statusLabel(int m) {
    switch (match.sport) {
      case Sport.soccer:
        return _statusSoccer(m);
      case Sport.basketball:
        return _statusBasketball(m);
      case Sport.americanFootball:
      case Sport.baseball:
      case Sport.tennis:
      case Sport.iceHockey:
      case Sport.rugby:
      case Sport.handball:
        return m <= 0 ? 'En cours' : 'Temps de jeu';
    }
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
          Icon(AppIcons.chevronRight, size: 16, color: AppColors.textMuted),
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
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child:
              Icon(AppIcons.chevronRight, size: 16, color: AppColors.textMuted),
        ),
      ],
    ]);
  }

  /// Skeleton 3 (ou 2) tiles avec un spinner subtil pendant le prefetch.
  Widget _buildOddsSkeleton(bool hasDraw, bool isSmall) {
    Widget tile() => InsetPanel(
          radius: AppRadius.xs,
          depth: 0.7,
          padding:
              EdgeInsets.symmetric(vertical: isSmall ? 10 : 12, horizontal: 6),
          child: Center(
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.4, color: AppColors.textMuted),
            ),
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

  Widget _oddsTile(
      String label, double? value, String marketCode, bool isSmall) {
    return _OddsTile(
      label: label,
      value: value,
      isSmall: isSmall,
      selected: selectedMarket == marketCode,
      onTap: () => onTapOdds?.call(marketCode),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onLongPressOdds?.call(marketCode);
      },
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Touche de cote ────────────────────────────────────────────
// Trois états : bombée (par défaut), enfoncée (sous le doigt), et
// allumée en vert plein (sélectionnée). Indisponible : gravée en creux.

class _OddsTile extends StatefulWidget {
  final String label;
  final double? value;
  final bool isSmall;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _OddsTile({
    required this.label,
    required this.value,
    required this.isSmall,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_OddsTile> createState() => _OddsTileState();
}

class _OddsTileState extends State<_OddsTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.value == null;
    final selected = widget.selected;
    final vPad = widget.isSmall ? 8.0 : 10.0;

    if (disabled) {
      return InsetPanel(
        radius: AppRadius.xs,
        depth: 0.7,
        padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 6),
        child:
            Center(child: _content(AppColors.textMuted, AppColors.textMuted)),
      );
    }

    final fill = selected ? AppColors.primary : AppColors.bgElevated;
    final labelColor =
        selected ? AppSurfaces.inkOn(AppColors.primary) : AppColors.textMuted;
    final valueColor =
        selected ? AppSurfaces.inkOn(AppColors.primary) : AppColors.textPrimary;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 6),
        transform: Matrix4.translationValues(0, _pressed ? 1.5 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: AppRadius.brXs,
          gradient: AppSurfaces.raisedGradient(fill),
          border: Border.all(
            color: selected ? AppColors.primaryInk : AppSurfaces.hairline,
            width: selected ? 1.2 : 0.8,
          ),
          boxShadow: _pressed
              ? AppSurfaces.pressed(glow: selected ? AppColors.primary : null)
              : AppSurfaces.raised(
                  glow: selected ? AppColors.primary : null,
                  elevation: 0.5,
                ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.brXs,
                    gradient: AppSurfaces.bevelOverlay,
                  ),
                ),
              ),
            ),
            _content(labelColor, valueColor),
          ],
        ),
      ),
    );
  }

  Widget _content(Color labelColor, Color valueColor) {
    final disabled = widget.value == null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(widget.label,
            style: TextStyle(
              color: labelColor,
              fontSize: widget.isSmall ? 11 : 12,
              fontWeight: FontWeight.w800,
            )),
        const SizedBox(width: 6),
        Text(
          disabled ? '-' : widget.value!.toStringAsFixed(2),
          style: TextStyle(
            color: valueColor,
            fontSize: widget.isSmall ? 12 : 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

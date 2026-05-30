// ============================================================
// BettingMatchCard — Card de match pour l'onglet Paris
// ============================================================
// Reutilise le style visuel de MatchCard (gradient, neon, radius 14)
// + ajoute des "tuiles cotes" 1X2 / OU 2.5 / BTTS + bouton Parier.
// 100% responsive, aucun overflow.
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart';

class BettingMatchCard extends StatelessWidget {
  final BettingMatch match;
  final VoidCallback? onBet;

  const BettingMatchCard({super.key, required this.match, this.onBet});

  @override
  Widget build(BuildContext context) {
    final isLive = match.isLive;
    final w = MediaQuery.of(context).size.width;
    final isSmall = w < 360;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 10 : 14, vertical: 12),
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
                ? AppColors.neonRed.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 6, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _buildHeader(isLive, isSmall),
        const SizedBox(height: 10),
        _buildTeamsRow(isSmall),
        const SizedBox(height: 12),
        _buildOdds(isSmall),
        const SizedBox(height: 10),
        _buildCta(),
      ]),
    );
  }

  Widget _buildHeader(bool isLive, bool isSmall) {
    return Row(children: [
      Expanded(
        child: Text(match.league,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: isSmall ? 10 : 11,
              fontWeight: FontWeight.w600,
            )),
      ),
      if (isLive)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.neonRed,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text("LIVE ${match.minute ?? 0}'",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          ]),
        )
      else
        Text(_formatTime(match.startTime),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: isSmall ? 10 : 11,
              fontWeight: FontWeight.w700,
            )),
    ]);
  }

  Widget _buildTeamsRow(bool isSmall) {
    final crest = isSmall ? 28.0 : 34.0;
    return Row(children: [
      _crest(match.homeLogo, crest),
      const SizedBox(width: 10),
      Expanded(
        child: Text(match.homeName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: isSmall ? 13 : 14,
              fontWeight: FontWeight.w800,
            )),
      ),
      const SizedBox(width: 8),
      _score(isSmall),
      const SizedBox(width: 8),
      Expanded(
        child: Text(match.awayName,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: isSmall ? 13 : 14,
              fontWeight: FontWeight.w800,
            )),
      ),
      const SizedBox(width: 10),
      _crest(match.awayLogo, crest),
    ]);
  }

  Widget _crest(String? url, double size) {
    if (url != null && url.isNotEmpty) {
      return SizedBox(
        width: size, height: size,
        child: ClipOval(
          child: Image.network(url, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholderCrest(size)),
        ),
      );
    }
    return _placeholderCrest(size);
  }

  Widget _placeholderCrest(double size) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Icon(Icons.sports_soccer,
            size: size * 0.55, color: AppColors.textMuted),
      );

  Widget _score(bool isSmall) {
    if (match.isLive && match.homeScore != null) {
      return Text('${match.homeScore} - ${match.awayScore}',
          style: TextStyle(
            color: AppColors.neonYellow,
            fontSize: isSmall ? 16 : 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ));
    }
    return Text('VS',
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: isSmall ? 11 : 12,
          fontWeight: FontWeight.w800,
        ));
  }

  Widget _buildOdds(bool isSmall) {
    final o = match.odds;
    if (o == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 1X2
      _marketLabel('Vainqueur'),
      Row(children: [
        Expanded(child: _oddsTile('1', o.home, isSmall)),
        const SizedBox(width: 6),
        Expanded(child: _oddsTile('X', o.draw, isSmall)),
        const SizedBox(width: 6),
        Expanded(child: _oddsTile('2', o.away, isSmall)),
      ]),
      const SizedBox(height: 8),
      // OU 2.5 + BTTS sur 2 lignes pour eviter overflow sur petits ecrans
      Row(children: [
        Expanded(child: _oddsTile('+2.5', o.over25, isSmall, secondary: true)),
        const SizedBox(width: 6),
        Expanded(child: _oddsTile('-2.5', o.under25, isSmall, secondary: true)),
        const SizedBox(width: 6),
        Expanded(child: _oddsTile('BTTS Oui', o.bttsYes, isSmall, secondary: true)),
        const SizedBox(width: 6),
        Expanded(child: _oddsTile('BTTS Non', o.bttsNo, isSmall, secondary: true)),
      ]),
    ]);
  }

  Widget _marketLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            )),
      );

  Widget _oddsTile(String label, double? value, bool isSmall,
      {bool secondary = false}) {
    final disabled = value == null;
    return Container(
      padding: EdgeInsets.symmetric(vertical: isSmall ? 6 : 8, horizontal: 4),
      decoration: BoxDecoration(
        color: disabled
            ? AppColors.bgElevated.withValues(alpha: 0.4)
            : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: secondary ? 9 : 10,
              fontWeight: FontWeight.w700,
            )),
        const SizedBox(height: 2),
        Text(disabled ? '-' : value.toStringAsFixed(2),
            style: TextStyle(
              color: disabled ? AppColors.textMuted : AppColors.neonGreen,
              fontSize: secondary ? 11 : 13,
              fontWeight: FontWeight.w900,
            )),
      ]),
    );
  }

  Widget _buildCta() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onBet,
        icon: const Icon(Icons.bolt, size: 16),
        label: const Text('Parier',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neonGreen,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
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

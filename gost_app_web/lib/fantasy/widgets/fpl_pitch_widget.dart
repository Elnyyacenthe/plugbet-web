// ============================================================
// FANTASY MODULE – Pitch View Widget
// Terrain vert foncé avec joueurs positionnés par ligne
// ============================================================

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../models/fpl_models.dart';
import '../providers/fpl_provider.dart';

class FplPitchWidget extends StatelessWidget {
  final FplProvider provider;
  final void Function(FplElement)? onPlayerTap;
  final bool compact;

  const FplPitchWidget({
    super.key,
    required this.provider,
    this.onPlayerTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final lines = provider.startersByLine;
    final bench = provider.benchElements;

    return Column(
      children: [
        // Terrain
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1B4332), Color(0xFF2D6A4F), Color(0xFF1B4332)],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.neonGreen.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: _PitchLinesPainter(),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // GK
                    _buildLine(lines[1] ?? [], 1),
                    // DEF
                    _buildLine(lines[2] ?? [], 2),
                    // MID
                    _buildLine(lines[3] ?? [], 3),
                    // FWD
                    _buildLine(lines[4] ?? [], 4),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bench
        if (bench.isNotEmpty) ...[
          SizedBox(height: 6),
          _buildBench(bench),
        ],
      ],
    );
  }

  Widget _buildLine(List<FplElement> players, int posType) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: players
            .map((p) => _PlayerToken(
                  player: p,
                  pick: provider.pickFor(p.id),
                  livePoints: provider.livePointsFor(p.id),
                  compact: compact,
                  onTap: onPlayerTap != null ? () => onPlayerTap!(p) : null,
                ))
            .toList(),
      ),
    );
  }

  Widget _buildBench(List<FplElement> bench) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.divider.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Text(
            'REMPLAÇANTS',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: bench
                .map((p) => _PlayerToken(
                      player: p,
                      pick: provider.pickFor(p.id),
                      livePoints: provider.livePointsFor(p.id),
                      compact: true,
                      isBench: true,
                      onTap: onPlayerTap != null ? () => onPlayerTap!(p) : null,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Token joueur ─────────────────────────────────────────

class _PlayerToken extends StatelessWidget {
  final FplElement player;
  final FplPick? pick;
  final int livePoints;
  final bool compact;
  final bool isBench;
  final VoidCallback? onTap;

  const _PlayerToken({
    required this.player,
    required this.pick,
    required this.livePoints,
    this.compact = false,
    this.isBench = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCaptain = pick?.isCaptain ?? false;
    final isVC = pick?.isViceCaptain ?? false;
    final posColor = _posColor(player.elementType);
    final double tokenWidth = compact ? 52 : 58;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: tokenWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar + badge
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: compact ? 36 : 42,
                  height: compact ? 36 : 42,
                  decoration: BoxDecoration(
                    color: isBench
                        ? AppColors.bgCard
                        : posColor.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isBench ? AppColors.divider : posColor,
                      width: isBench ? 1 : 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      player.positionLabel,
                      style: TextStyle(
                        color: isBench ? AppColors.textMuted : posColor,
                        fontSize: compact ? 9 : 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                // Captain / VC badge
                if (isCaptain || isVC)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: isCaptain
                            ? AppColors.neonYellow
                            : AppColors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          isCaptain ? 'C' : 'V',
                          style: TextStyle(
                            color: AppColors.bgDark,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            SizedBox(height: 3),

            // Nom
            Text(
              _shortName(player.webName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isBench ? AppColors.textSecondary : Colors.white,
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w700,
              ),
            ),

            // Points live
            Container(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: livePoints > 0
                    ? AppColors.neonGreen.withValues(alpha: 0.2)
                    : AppColors.bgCard.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$livePoints pts',
                style: TextStyle(
                  color: livePoints > 0
                      ? AppColors.neonGreen
                      : AppColors.textMuted,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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

  String _shortName(String name) {
    final parts = name.split(' ');
    if (parts.length == 1) return name.length > 8 ? name.substring(0, 7) : name;
    return parts.last.length > 8 ? '${parts.last.substring(0, 7)}.' : parts.last;
  }
}

// ─── Lignes de terrain (CustomPainter) ────────────────────

class _PitchLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Ligne médiane
    canvas.drawLine(
      Offset(size.width * 0.1, size.height / 2),
      Offset(size.width * 0.9, size.height / 2),
      paint,
    );

    // Cercle central
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.12,
      paint,
    );

    // Surface de réparation haute
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.08),
        width: size.width * 0.4,
        height: size.height * 0.1,
      ),
      paint,
    );

    // Surface de réparation basse
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.92),
        width: size.width * 0.4,
        height: size.height * 0.1,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PitchLinesPainter old) => false;
}

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
                Builder(builder: (_) {
                  final base = isBench ? AppColors.bgElevated : posColor;
                  final d = compact ? 36.0 : 42.0;
                  return Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.35, -0.4),
                        colors: [
                          Color.lerp(base, Colors.white, 0.5)!,
                          base,
                          Color.lerp(base, Colors.black, 0.38)!,
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                      border: Border.all(
                        color: isBench ? AppColors.divider : posColor,
                        width: isBench ? 1 : 2,
                      ),
                      boxShadow: [
                        const BoxShadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(0, 3)),
                        if (!isBench)
                          BoxShadow(
                              color: base.withValues(alpha: 0.4),
                              blurRadius: 8),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      player.positionLabel,
                      style: TextStyle(
                        color: isBench ? AppColors.textMuted : Colors.white,
                        fontSize: compact ? 9 : 10,
                        fontWeight: FontWeight.w900,
                        shadows: isBench
                            ? null
                            : const [
                                Shadow(
                                    color: Colors.black87,
                                    blurRadius: 2,
                                    offset: Offset(0, 1))
                              ],
                      ),
                    ),
                  );
                }),
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
    final w = size.width, h = size.height;

    // Bandes de tonte (mown stripes)
    const bands = 7;
    final bandH = h / bands;
    for (int i = 0; i < bands; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * bandH, w, bandH),
        Paint()
          ..color = (i.isEven ? Colors.white : Colors.black)
              .withValues(alpha: 0.05),
      );
    }
    // Vignette
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.22)],
          stops: const [0.65, 1.0],
        ).createShader(Offset.zero & size),
    );

    // Lignes
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    const m = 5.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(m, m, w - 2 * m, h - 2 * m), const Radius.circular(4)),
      line,
    );
    canvas.drawLine(Offset(m, h / 2), Offset(w - m, h / 2), line);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.14, line);
    canvas.drawCircle(Offset(w / 2, h / 2), 2,
        Paint()..color = Colors.white.withValues(alpha: 0.6));

    void box(double cy, double dir) {
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(w / 2, cy + dir * h * 0.075),
            width: w * 0.46,
            height: h * 0.15),
        line,
      );
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(w / 2, cy + dir * h * 0.035),
            width: w * 0.24,
            height: h * 0.07),
        line,
      );
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(w / 2, cy - dir * 1.5), width: w * 0.14, height: 3),
        line,
      );
      canvas.drawCircle(Offset(w / 2, cy + dir * h * 0.115), 1.8,
          Paint()..color = Colors.white.withValues(alpha: 0.6));
    }

    box(m, 1);
    box(h - m, -1);
  }

  @override
  bool shouldRepaint(_PitchLinesPainter old) => false;
}

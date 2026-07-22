// ============================================================
// FANTASY MODULE – Terrain In-App (picks Supabase)
// Affiche TOUS les 11 titulaires sur le terrain selon la formation
// Un joueur peut être placé n'importe où (hors-position = indicateur)
// ============================================================

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../models/fpl_models.dart';

class FantasyInAppPitch extends StatelessWidget {
  final List<Map<String, dynamic>> picks;
  final FplBootstrap bootstrap;
  final void Function(FplElement, Map<String, dynamic>)? onPlayerTap;
  final bool compact;
  final String formation;

  const FantasyInAppPitch({
    super.key,
    required this.picks,
    required this.bootstrap,
    this.onPlayerTap,
    this.compact = false,
    this.formation = '4-4-2',
  });

  /// Position naturelle attendue par ligne de formation :
  /// Ligne 0 = GK (type 1), Lignes 1..N-1 = DEF→MID→FWD (types 2,3,4)
  static int expectedPosType(int lineIndex, int totalLines) {
    if (lineIndex == 0) return 1; // GK
    if (lineIndex == totalLines - 1) return 4; // FWD (dernière ligne)
    if (lineIndex == 1) return 2; // DEF (première ligne de champ)
    return 3; // MID (toutes les lignes du milieu)
  }

  @override
  Widget build(BuildContext context) {
    // Séparer starters et bench
    final starters = <_PickData>[];
    final benchData = <_PickData>[];

    for (final p in picks) {
      final el = bootstrap.elementById(p['element_id'] as int);
      if (el == null) continue;
      final isStarter = p['is_starter'] as bool? ??
          ((p['position'] as int? ?? 0) <= 11);
      if (isStarter) {
        starters.add(_PickData(el: el, pick: p));
      } else {
        benchData.add(_PickData(el: el, pick: p));
      }
    }

    // Parse formation : '4-4-2' → [4,4,2], '4-2-3-1' → [4,2,3,1]
    final parts = formation
        .split('-')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    // Lignes : [1 GK, parts[0] DEF, ...milieux..., parts[last] FWD]
    final lineSizes = [1, ...parts];
    final totalLines = lineSizes.length;

    // ── Répartition intelligente ──
    // 1. Grouper starters par position naturelle
    final byNatural = <int, List<_PickData>>{1: [], 2: [], 3: [], 4: []};
    for (final s in starters) {
      byNatural[s.el.elementType]?.add(s);
    }

    // 2. Mapper chaque ligne à sa position attendue
    final lineExpected = <int>[];
    for (int i = 0; i < totalLines; i++) {
      lineExpected.add(expectedPosType(i, totalLines));
    }

    // 3. Phase 1 : placer les joueurs à leur position naturelle (priorité)
    final pitchLines = List.generate(totalLines, (_) => <_PickData>[]);
    final placed = <_PickData>{};

    for (int i = 0; i < totalLines; i++) {
      final expected = lineExpected[i];
      final capacity = lineSizes[i];
      final candidates = byNatural[expected] ?? [];
      for (final c in candidates) {
        if (pitchLines[i].length >= capacity) break;
        if (placed.contains(c)) continue;
        pitchLines[i].add(c);
        placed.add(c);
      }
    }

    // 4. Phase 2 : redistribuer les excédents vers les lignes voisines
    final unplaced = starters.where((s) => !placed.contains(s)).toList();
    // Trier les non-placés : d'abord ceux proches des lignes à remplir
    for (final u in unplaced) {
      // Trouver la ligne la plus proche avec de la place
      int bestLine = -1;
      int bestDist = 999;
      for (int i = 0; i < totalLines; i++) {
        if (pitchLines[i].length < lineSizes[i]) {
          // Distance : écart entre position naturelle et ligne attendue
          final dist = (u.el.elementType - lineExpected[i]).abs();
          if (dist < bestDist) {
            bestDist = dist;
            bestLine = i;
          }
        }
      }
      if (bestLine >= 0) {
        pitchLines[bestLine].add(u);
      } else {
        // Plus de place nulle part → ajouter à la dernière ligne
        pitchLines.last.add(u);
      }
    }

    return Column(
      children: [
        // ── Terrain ──
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1B4332),
                Color(0xFF2D6A4F),
                Color(0xFF1B4332),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.neonGreen.withValues(alpha: 0.2),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              painter: _PitchPainter(),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (int i = 0; i < pitchLines.length; i++)
                      _buildLine(
                        pitchLines[i],
                        expectedPosType(i, totalLines),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Banc ──
        if (benchData.isNotEmpty) ...[
          SizedBox(height: 6),
          _buildBench(benchData),
        ],
      ],
    );
  }

  Widget _buildLine(List<_PickData> data, int expectedType) {
    if (data.isEmpty) return SizedBox(height: 8);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: data
            .map((d) => _InAppToken(
                  data: d,
                  compact: compact,
                  outOfPosition: d.el.elementType != expectedType,
                  onTap: onPlayerTap != null
                      ? () => onPlayerTap!(d.el, d.pick)
                      : null,
                ))
            .toList(),
      ),
    );
  }

  Widget _buildBench(List<_PickData> data) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text('REMPLAÇANTS',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2)),
          SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: data
                .map((d) => _InAppToken(
                      data: d,
                      compact: true,
                      isBench: true,
                      onTap: onPlayerTap != null
                          ? () => onPlayerTap!(d.el, d.pick)
                          : null,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Data ─────────────────────────────────────────────────

class _PickData {
  final FplElement el;
  final Map<String, dynamic> pick;
  const _PickData({required this.el, required this.pick});
}

// ─── Token joueur ─────────────────────────────────────────

class _InAppToken extends StatelessWidget {
  final _PickData data;
  final bool compact;
  final bool isBench;
  final bool outOfPosition;
  final VoidCallback? onTap;

  const _InAppToken({
    required this.data,
    this.compact = false,
    this.isBench = false,
    this.outOfPosition = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final el = data.el;
    final pick = data.pick;
    final isCap = pick['is_captain'] == true;
    final isVC = pick['is_vice_captain'] == true;
    final posColor = _posColor(el.elementType);
    final double w = compact ? 52 : 58;

    // Bordure hors-position
    final borderColor = outOfPosition && !isBench
        ? AppColors.neonOrange
        : isBench
            ? AppColors.divider
            : posColor;
    final borderWidth = outOfPosition && !isBench ? 2.5 : (isBench ? 1.0 : 2.0);

    // Statut disponibilité
    final chance = el.chanceOfPlayingNextRound;
    final statusColor = chance >= 100
        ? null
        : chance >= 75
            ? AppColors.neonYellow
            : chance >= 50
                ? AppColors.neonOrange
                : AppColors.neonRed;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Builder(builder: (_) {
                  // Jeton-maillot bombé : dôme dégradé + reflet + ombre
                  final base = isBench
                      ? AppColors.bgElevated
                      : outOfPosition
                          ? AppColors.neonOrange
                          : posColor;
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
                      border:
                          Border.all(color: borderColor, width: borderWidth),
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
                      el.positionLabel,
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
                // Badge C / VC
                if (isCap || isVC)
                  Positioned(
                    top: -4, right: -4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: isCap
                            ? AppColors.neonYellow
                            : AppColors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          isCap ? 'C' : 'V',
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                // Indicateur hors-position (flèche warning)
                if (outOfPosition && !isBench)
                  Positioned(
                    top: -4, left: -4,
                    child: Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.neonOrange,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('!',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                // Indicateur blessure
                if (statusColor != null)
                  Positioned(
                    bottom: -2, right: -2,
                    child: Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bgDark, width: 1),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 3),
            Text(
              _short(el.webName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isBench
                    ? AppColors.textSecondary
                    : outOfPosition
                        ? AppColors.neonOrange
                        : Colors.white,
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.bgCard.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${el.coinsValue}c',
                style: TextStyle(
                    color: AppColors.neonGreen,
                    fontSize: 8,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _posColor(int t) {
    switch (t) {
      case 1: return AppColors.neonYellow;
      case 2: return AppColors.neonBlue;
      case 3: return AppColors.neonGreen;
      case 4: return AppColors.neonOrange;
      default: return AppColors.textSecondary;
    }
  }

  String _short(String name) {
    final parts = name.split(' ');
    if (parts.length == 1) {
      return name.length > 8 ? '${name.substring(0, 7)}.' : name;
    }
    return parts.last.length > 8 ? '${parts.last.substring(0, 7)}.' : parts.last;
  }
}

// ─── Painter terrain ──────────────────────────────────────

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // ── Bandes de tonte (mown stripes) ──
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
    // Vignette douce (assombrit les bords)
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, 0),
          radius: 0.9,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.22),
          ],
          stops: const [0.65, 1.0],
        ).createShader(Offset.zero & size),
    );

    // ── Lignes du terrain ──
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    const m = 5.0; // marge
    // Boundary
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(m, m, w - 2 * m, h - 2 * m), const Radius.circular(4)),
      line,
    );
    // Ligne médiane
    canvas.drawLine(Offset(m, h / 2), Offset(w - m, h / 2), line);
    // Rond central + point
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.14, line);
    canvas.drawCircle(
        Offset(w / 2, h / 2), 2, Paint()..color = Colors.white.withValues(alpha: 0.6));

    // ── Surfaces (haut et bas) ──
    void box(double cy, double dir) {
      // Grande surface
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(w / 2, cy + dir * h * 0.075),
            width: w * 0.46,
            height: h * 0.15),
        line,
      );
      // Petite surface (6 yards)
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(w / 2, cy + dir * h * 0.035),
            width: w * 0.24,
            height: h * 0.07),
        line,
      );
      // But
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(w / 2, cy - dir * 1.5),
            width: w * 0.14,
            height: 3),
        line,
      );
      // Point de penalty
      canvas.drawCircle(Offset(w / 2, cy + dir * h * 0.115), 1.8,
          Paint()..color = Colors.white.withValues(alpha: 0.6));
    }

    box(m, 1); // haut
    box(h - m, -1); // bas
  }

  @override
  bool shouldRepaint(_PitchPainter o) => false;
}

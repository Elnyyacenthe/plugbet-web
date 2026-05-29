// ============================================================
// PenaltyPlayScreen — mini-stade 100% Flutter natif (Phase 3d)
// ============================================================
// Aucun asset PNG/MP3 externe : tout est dessiné avec CustomPaint +
// shapes (cage, filet, foule, gardien, joueur) et ballon = Material
// Icon. Sons via AudioService existant du projet (zero plugin natif
// supplementaire -> compatible Shorebird).
//
// Animation par tir :
//   * t=0     : ballon au pied du joueur
//   * t=0..1  : ballon en parabole vers la zone choisie + gardien
//               slide vers la direction serveur (RNG crypto cote DB)
//   * t=1     : si meme direction -> ARRÊT, sinon BUT
//   * banner BUT/ARRÊT pendant 1.3s, puis reset pour prochain tir
// ============================================================

import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../../../widgets/network_lost_overlay.dart';
import '../audio/penalty_audio.dart';
import '../models/penalty_models.dart';
import '../providers/penalty_provider.dart';
import 'penalty_bet_screen.dart';

class PenaltyPlayScreen extends StatefulWidget {
  const PenaltyPlayScreen({super.key});
  @override
  State<PenaltyPlayScreen> createState() => _PenaltyPlayScreenState();
}

class _PenaltyPlayScreenState extends State<PenaltyPlayScreen>
    with TickerProviderStateMixin {
  PenaltyShotResult? _lastShot;
  bool _showBanner = false;
  bool _animating = false;
  Timer? _bannerTimer;

  late final AnimationController _shotCtrl;
  PenaltyDirection? _aimDir;       // direction choisie par le joueur
  PenaltyDirection? _keeperDir;    // direction serveur du gardien

  @override
  void initState() {
    super.initState();
    _shotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    // Ambiance foule en boucle pendant tout le round (bg_music.mp3 via
    // FlameAudio.bgm = loop automatique).
    PenaltyAudio.startAmbient();
  }

  @override
  void dispose() {
    _shotCtrl.dispose();
    _bannerTimer?.cancel();
    PenaltyAudio.stopAmbient();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    return Consumer<PenaltyProvider>(
      builder: (_, prov, __) {
        final round = prov.round;
        if (round == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }

        final showResult =
            round.status != PenaltyRoundStatus.active && !_showBanner;
        final shotDisplayed = round.status == PenaltyRoundStatus.active
            ? round.shotsTaken + 1
            : round.totalShots;

        return PopScope(
          canPop: !prov.hasActiveRound,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final leave = await _confirmAbandon(context);
            if (leave == true && context.mounted) {
              await prov.abandonRound();
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.bgDark,
            appBar: AppBar(
              backgroundColor: AppColors.bgBlueNight,
              title: Text(
                showResult
                    ? 'Résultat'
                    : 'Tir $shotDisplayed / ${round.totalShots}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            body: SafeArea(
              child: showResult
                  ? _buildResult(prov, round)
                  : _buildActiveRound(prov, round),
            ),
          ),
        );
      },
    );
  }

  // ═══ ROUND ACTIF ═══════════════════════════════════════════
  Widget _buildActiveRound(PenaltyProvider prov, PenaltyRound round) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: _scoreRow(round),
        ),
        Expanded(child: _buildPitch(prov, round)),
      ],
    );
  }

  Widget _scoreRow(PenaltyRound round) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _scorePill('BUTS', round.goals,
            AppColors.neonGreen, Icons.sports_soccer_rounded),
        _scorePill('RATÉS', round.misses,
            AppColors.neonRed, Icons.close_rounded),
        _scorePill('MISE', round.betAmount,
            AppColors.neonYellow, Icons.monetization_on_rounded),
      ],
    );
  }

  Widget _scorePill(String label, int value, Color c, IconData icon) {
    return Column(children: [
      Icon(icon, color: c, size: 16),
      const SizedBox(height: 2),
      Text('$value',
          style: TextStyle(
              color: c, fontSize: 18, fontWeight: FontWeight.w900)),
      Text(label,
          style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700)),
    ]);
  }

  // ── Le stade (CustomPaint + shapes + animation) ────────────
  Widget _buildPitch(PenaltyProvider prov, PenaltyRound round) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      // Géométrie de la cage (proportions stade)
      final goalW = w * 0.84;
      final goalH = h * 0.40;
      final goalLeft = (w - goalW) / 2;
      final goalTop = h * 0.14;
      final goalRight = goalLeft + goalW;
      final goalBottom = goalTop + goalH;

      // Y du sol (ligne de gazon) sous la cage
      final groundY = goalBottom + h * 0.02;

      // Positions de base ballon/joueur
      final ballHomeX = w / 2;
      final ballHomeY = h * 0.86;
      final ballSize = w * 0.07;

      // Position cible ballon selon direction choisie
      final aimZoneX = _aimDir == null
          ? ballHomeX
          : _zoneCenterX(goalLeft, goalW, _aimDir!);
      final aimY = goalTop + goalH * 0.55;

      // Position gardien : départ au centre, cible selon RNG serveur
      final keeperW = goalW * 0.26;
      final keeperH = goalH * 0.78;
      final keeperHomeX = goalLeft + (goalW - keeperW) / 2;
      final keeperY = goalTop + goalH * 0.22;
      final keeperTargetX = _keeperDir == null
          ? keeperHomeX
          : _zoneCenterX(goalLeft, goalW, _keeperDir!) - keeperW / 2;

      return AnimatedBuilder(
        animation: _shotCtrl,
        builder: (_, __) {
          final t = _shotCtrl.value;
          final tBall = Curves.easeOutCubic.transform(t);
          final tKeeper = Curves.easeOutQuart.transform(t);

          // Ballon : interpolation + parabole verticale
          final ballX = lerpDouble(ballHomeX, aimZoneX, tBall)!;
          // Y linéaire vers cible + lift parabolique (-4t(t-1) max au milieu)
          final liftAmount = h * 0.08;
          final ballYLinear = lerpDouble(ballHomeY, aimY, tBall)!;
          final ballY = ballYLinear - (-4 * tBall * (tBall - 1)) * liftAmount;

          // Gardien : interpolation X (plonge latéralement),
          // + petit saut (Y rise au pic puis retour)
          final keeperX = lerpDouble(keeperHomeX, keeperTargetX, tKeeper)!;
          final keeperLift = -4 * tKeeper * (tKeeper - 1) * (goalH * 0.18);
          final keeperYAnim = keeperY - keeperLift;

          return Stack(
            children: [
              // 1) Fond ciel + foule en haut
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF1B3A5A),
                        const Color(0xFF1B3A5A),
                        const Color(0xFF276A33),
                        const Color(0xFF1E5F2A),
                      ],
                      stops: const [0.0, 0.18, 0.22, 1.0],
                    ),
                  ),
                ),
              ),
              // 2) Foule (bandeau de pixels colorés)
              Positioned(
                top: 0, left: 0, right: 0,
                height: h * 0.18,
                child: CustomPaint(painter: _CrowdPainter()),
              ),
              // 3) Sol : lignes de pelouse + ligne de surface
              Positioned(
                left: 0, right: 0, top: groundY,
                bottom: 0,
                child: CustomPaint(painter: _PitchPainter()),
              ),
              // 4) Cage (poteaux + filet)
              Positioned(
                left: goalLeft, top: goalTop,
                width: goalW, height: goalH,
                child: CustomPaint(
                  painter: _GoalPainter(),
                ),
              ),
              // 5) Gardien (animé)
              Positioned(
                left: keeperX, top: keeperYAnim,
                width: keeperW, height: keeperH,
                child: _KeeperFigure(diving: _keeperDir != null && t > 0.1),
              ),
              // 6) Joueur (statique en attente, jambe levée pendant le tir)
              Positioned(
                left: ballHomeX - w * 0.10,
                top: ballHomeY - h * 0.24,
                width: w * 0.20, height: h * 0.26,
                child: _PlayerFigure(kicking: _animating),
              ),
              // 7) Ombre du ballon au sol (suit X, reste à Y home)
              Positioned(
                left: ballX - ballSize * 0.6,
                top: ballHomeY + ballSize * 0.05,
                width: ballSize * 1.2,
                height: ballSize * 0.35,
                child: Opacity(
                  opacity: (1 - tBall * 0.7).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              // 8) Ballon (animé)
              Positioned(
                left: ballX - ballSize / 2,
                top: ballY - ballSize / 2,
                width: ballSize, height: ballSize,
                child: Transform.rotate(
                  angle: tBall * 6.28 * 2,
                  child: Icon(Icons.sports_soccer_rounded,
                      color: Colors.white, size: ballSize),
                ),
              ),
              // 8) Zones tactiles invisibles sur la cage
              ..._buildTapZones(
                  goalLeft, goalTop, goalW, goalH, goalRight, goalBottom),
              // 9) Banner résultat tir (au-dessus du stade)
              if (_showBanner && _lastShot != null)
                Positioned(
                  top: h * 0.02, left: 16, right: 16,
                  child: _shotResultBanner(_lastShot!),
                ),
              // 10) Hint quand pas d'animation
              if (!_animating && !_showBanner)
                Positioned(
                  bottom: 8, left: 0, right: 0,
                  child: Center(
                    child: Text('Tape une zone du but pour tirer',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          );
        },
      );
    });
  }

  double _zoneCenterX(double goalLeft, double goalW, PenaltyDirection d) {
    final zoneW = goalW / 3;
    switch (d) {
      case PenaltyDirection.left:   return goalLeft + zoneW * 0.5;
      case PenaltyDirection.center: return goalLeft + zoneW * 1.5;
      case PenaltyDirection.right:  return goalLeft + zoneW * 2.5;
    }
  }

  List<Widget> _buildTapZones(
    double goalLeft, double goalTop, double goalW, double goalH,
    double goalRight, double goalBottom,
  ) {
    final zoneW = goalW / 3;
    return [
      for (int i = 0; i < 3; i++)
        Positioned(
          left: goalLeft + i * zoneW,
          top: goalTop,
          width: zoneW,
          height: goalH,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _animating
                  ? null
                  : () => _onTakeShot([
                        PenaltyDirection.left,
                        PenaltyDirection.center,
                        PenaltyDirection.right
                      ][i]),
            ),
          ),
        ),
    ];
  }

  Widget _shotResultBanner(PenaltyShotResult res) {
    final isGoal = res.isGoal;
    final color = isGoal ? AppColors.neonGreen : AppColors.neonRed;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isGoal ? Icons.sports_soccer_rounded : Icons.shield_rounded,
              color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(isGoal ? 'BUT !' : 'ARRÊT !',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5)),
        ],
      ),
    );
  }

  Future<void> _onTakeShot(PenaltyDirection dir) async {
    if (_animating) return;
    final prov = context.read<PenaltyProvider>();
    final wallet = context.read<WalletProvider>();

    setState(() {
      _aimDir = dir;
      _animating = true;
      _showBanner = false;
    });

    // Son de frappe : playDiceRoll (volume full 80% + son distinct des
    // sons de but/arrêt) au lieu de playPawnMove (qui joue à 48%, presque
    // inaudible sur téléphone).
    PenaltyAudio.playKick();

    final res = await prov.takeShot(dir);
    if (!mounted || res == null) {
      setState(() {
        _animating = false;
        _aimDir = null;
      });
      return;
    }

    setState(() {
      _lastShot = res;
      _keeperDir = res.serverDirection;
    });

    await _shotCtrl.forward(from: 0);
    if (!mounted) return;

    // Son de résultat
    try {
      if (res.isGoal) {
        PenaltyAudio.playGoal();
      } else {
        PenaltyAudio.playSave();
      }
    } catch (_) {}

    setState(() => _showBanner = true);

    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      setState(() {
        _showBanner = false;
        _animating = false;
        _aimDir = null;
        _keeperDir = null;
      });
      _shotCtrl.reset();
    });

    if (res.roundFinished) {
      try { await wallet.refresh(); } catch (_) {}
    }
  }

  // ═══ ÉCRAN RÉSULTAT (identique 3c) ══════════════════════════
  Widget _buildResult(PenaltyProvider prov, PenaltyRound round) {
    final isWin = round.status == PenaltyRoundStatus.won;
    final isLost = round.status == PenaltyRoundStatus.lost;
    final isAbandoned = round.status == PenaltyRoundStatus.abandoned;
    final payout = isWin ? round.betAmount * 2 : 0;

    return Container(
      decoration: BoxDecoration(gradient: AppColors.bgGradient),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      child: Column(
        children: [
          const Spacer(),
          Icon(
            isWin
                ? Icons.emoji_events_rounded
                : (isAbandoned
                    ? Icons.exit_to_app_rounded
                    : Icons.sentiment_dissatisfied_rounded),
            size: 96,
            color: isWin
                ? AppColors.neonYellow
                : (isAbandoned
                    ? AppColors.textMuted
                    : AppColors.neonRed),
          ),
          const SizedBox(height: 18),
          Text(
            isWin
                ? 'VICTOIRE !'
                : (isAbandoned ? 'Round abandonné' : 'DÉFAITE'),
            style: TextStyle(
              color: isWin
                  ? AppColors.neonYellow
                  : (isAbandoned
                      ? AppColors.textSecondary
                      : AppColors.neonRed),
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text('${round.goals} buts • ${round.misses} ratés',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          if (isWin)
            _bilanPill('+$payout coins', AppColors.neonGreen)
          else if (isLost)
            _bilanPill('-${round.betAmount} coins', AppColors.neonRed)
          else
            _bilanPill('-${round.betAmount} coins (mise perdue)',
                AppColors.neonRed),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                prov.reset();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                      builder: (_) => const PenaltyBetScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Rejouer',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              prov.reset();
              Navigator.of(context).pop();
            },
            child: Text('Retour aux jeux',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _bilanPill(String text, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.55)),
      ),
      child: Text(text,
          style: TextStyle(
              color: c, fontSize: 22, fontWeight: FontWeight.w900)),
    );
  }

  Future<bool?> _confirmAbandon(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Quitter le round ?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
            'Le round est en cours. Si tu quittes, ta mise est perdue (pas de remboursement).',
            style: TextStyle(
                color: AppColors.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Continuer à jouer',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Quitter (mise perdue)',
                style: TextStyle(
                    color: AppColors.neonRed,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// PAINTERS — cage, filet, foule, pelouse
// ════════════════════════════════════════════════════════════════

class _GoalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1) Fond légèrement assombri à l'intérieur de la cage
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
        Paint()..color = Colors.black.withValues(alpha: 0.15));

    // 2) Filet : double cross-hatching diagonal (effet maille)
    final netPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..strokeWidth = 1;
    const step = 14.0;
    // Diagonales \\
    for (double d = -h; d < w; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + h, h), netPaint);
    }
    // Diagonales //
    for (double d = 0; d < w + h; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d - h, h), netPaint);
    }

    // 3) Petite ombre intérieure haute (perspective)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.35),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.25),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.35)),
    );

    // 4) Poteaux + barre — blancs épais avec léger relief
    final framePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    const postW = 7.0;
    // Poteau gauche
    canvas.drawRect(Rect.fromLTWH(0, 0, postW, h), framePaint);
    // Poteau droit
    canvas.drawRect(Rect.fromLTWH(w - postW, 0, postW, h), framePaint);
    // Barre transversale
    canvas.drawRect(Rect.fromLTWH(0, 0, w, postW), framePaint);

    // Ombre intérieure sur les poteaux (côté droit du gauche + gauche du droit)
    final shadeP = Paint()..color = Colors.black.withValues(alpha: 0.20);
    canvas.drawRect(Rect.fromLTWH(postW, 0, 2, h), shadeP);
    canvas.drawRect(Rect.fromLTWH(w - postW - 2, 0, 2, h), shadeP);
    // Ombre sous la barre
    canvas.drawRect(Rect.fromLTWH(0, postW, w, 2), shadeP);
  }

  @override
  bool shouldRepaint(_GoalPainter old) => false;
}

class _CrowdPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Fond gris-bleu (tribunes)
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFF26354A));
    // Petits points de couleur (spectateurs) sur 4 rangées
    const colors = [
      Color(0xFFFF6B6B),
      Color(0xFFFFB347),
      Color(0xFF77DDFF),
      Color(0xFFFFD93D),
      Color(0xFFB088F9),
      Color(0xFF80FFA0),
      Color(0xFFFFFFFF),
      Color(0xFFE63946),
    ];
    final rng = _PseudoRng(42);
    const rows = 4;
    final rowH = h / (rows + 1);
    const dotSize = 4.5;
    for (int r = 0; r < rows; r++) {
      final y = rowH * (r + 0.7);
      for (double x = 4; x < w; x += 7) {
        final jitter = (rng.next() - 0.5) * 2;
        final c = colors[rng.nextInt(colors.length)];
        canvas.drawCircle(
            Offset(x + jitter, y + jitter),
            dotSize / 2,
            Paint()..color = c);
      }
    }
    // Bandeau publicité orange en bas
    canvas.drawRect(Rect.fromLTWH(0, h - 12, w, 12),
        Paint()..color = const Color(0xFFEF6C00));
  }

  @override
  bool shouldRepaint(_CrowdPainter old) => false;
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Bandes alternées de pelouse (effet tonte)
    final dark = Paint()..color = const Color(0xFF1E5F2A);
    final light = Paint()..color = const Color(0xFF276A33);
    const bandH = 20.0;
    for (double y = 0; y < h; y += bandH) {
      canvas.drawRect(
          Rect.fromLTWH(0, y, w, bandH),
          (y / bandH).floor().isEven ? dark : light);
    }
    // Ligne de surface (arc + ligne) — esquisse
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    // Ligne droite à mi-hauteur
    canvas.drawLine(
        Offset(w * 0.1, h * 0.18),
        Offset(w * 0.9, h * 0.18),
        linePaint);
    // Demi-cercle (point de penalty stylisé)
    canvas.drawCircle(Offset(w / 2, h * 0.55), 5,
        Paint()..color = Colors.white.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_PitchPainter old) => false;
}

// Mini RNG déterministe pour la foule (toujours pareille à chaque build)
class _PseudoRng {
  int _state;
  _PseudoRng(int seed) : _state = seed;
  int next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state;
  }
  int nextInt(int max) => next() % max;
}

// ════════════════════════════════════════════════════════════════
// FIGURES — gardien & joueur (formes Flutter)
// ════════════════════════════════════════════════════════════════

// SVG vectoriel — gardien vue de face, bras grand écart (silhouette
// 100% paths à courbes, plus aucun rectangle visible)
const String _kSvgKeeper = r'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 150">
  <defs>
    <linearGradient id="kJersey" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#22C8DA"/>
      <stop offset="100%" stop-color="#0E9EAE"/>
    </linearGradient>
    <linearGradient id="kSkin" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#F2C99E"/>
      <stop offset="100%" stop-color="#D9A678"/>
    </linearGradient>
  </defs>
  <!-- Ombre au sol -->
  <ellipse cx="50" cy="143" rx="30" ry="4" fill="#000" opacity="0.4"/>
  <!-- Cuisses arrondies -->
  <path d="M40,92 Q40,89 43,89 L46,89 Q49,89 49,92 L49,118 Q49,121 46,121 L43,121 Q40,121 40,118 Z"
        fill="url(#kSkin)" stroke="#000" stroke-width="0.5"/>
  <path d="M51,92 Q51,89 54,89 L57,89 Q60,89 60,92 L60,118 Q60,121 57,121 L54,121 Q51,121 51,118 Z"
        fill="url(#kSkin)" stroke="#000" stroke-width="0.5"/>
  <!-- Chaussettes blanches -->
  <path d="M40,114 L49,114 L49,121 L40,121 Z" fill="#FFFFFF" stroke="#000" stroke-width="0.3"/>
  <path d="M51,114 L60,114 L60,121 L51,121 Z" fill="#FFFFFF" stroke="#000" stroke-width="0.3"/>
  <!-- Chaussures rondes -->
  <ellipse cx="44.5" cy="125" rx="9" ry="5" fill="#1A1A1A" stroke="#000" stroke-width="0.4"/>
  <ellipse cx="55.5" cy="125" rx="9" ry="5" fill="#1A1A1A" stroke="#000" stroke-width="0.4"/>
  <!-- Short courbé -->
  <path d="M32,74 Q30,74 30,76 L30,90 Q30,94 32,94 L46,94 L48,90 L52,90 L54,94 L68,94 Q70,94 70,90 L70,76 Q70,74 68,74 Z"
        fill="#1A1A1A" stroke="#000" stroke-width="0.5"/>
  <!-- Maillot (silhouette tapered, épaules arrondies) -->
  <path d="M26,44 Q26,32 38,30 Q42,33 50,33 Q58,33 62,30 Q74,32 74,44 L74,78 Q74,80 72,80 L28,80 Q26,80 26,78 Z"
        fill="url(#kJersey)" stroke="#000" stroke-width="0.6"/>
  <!-- Rayure verticale blanche -->
  <path d="M48,38 L52,38 L52,78 L48,78 Z" fill="#FFFFFF" opacity="0.85"/>
  <!-- Numéro 1 -->
  <text x="50" y="60" font-family="Arial Black,sans-serif" font-size="14"
        font-weight="900" fill="#FFFFFF" text-anchor="middle">1</text>
  <!-- Bras gauche (courbe organique) -->
  <path d="M26,44 Q14,42 6,50 Q2,54 4,60 Q8,58 14,54 Q22,50 26,48 Z"
        fill="url(#kJersey)" stroke="#000" stroke-width="0.5"/>
  <!-- Bras droit -->
  <path d="M74,44 Q86,42 94,50 Q98,54 96,60 Q92,58 86,54 Q78,50 74,48 Z"
        fill="url(#kJersey)" stroke="#000" stroke-width="0.5"/>
  <!-- Gants jaunes (bombés) -->
  <ellipse cx="5" cy="56" rx="7.5" ry="6.5" fill="#FFD500" stroke="#000" stroke-width="1"/>
  <ellipse cx="95" cy="56" rx="7.5" ry="6.5" fill="#FFD500" stroke="#000" stroke-width="1"/>
  <!-- Cou tapered -->
  <path d="M46,28 L54,28 Q55,32 54,36 L46,36 Q45,32 46,28 Z" fill="url(#kSkin)"/>
  <!-- Tête (ovale légère) -->
  <ellipse cx="50" cy="20" rx="11" ry="13" fill="url(#kSkin)" stroke="#000" stroke-width="0.5"/>
  <!-- Cheveux (calotte qui suit le crâne) -->
  <path d="M39,18 Q39,7 50,7 Q61,7 61,18 Q61,14 56,11 Q50,9 44,11 Q39,14 39,18 Z" fill="#1E1E1E"/>
  <!-- Sourcils -->
  <path d="M43,19 Q46,17.5 49,19" stroke="#1E1E1E" stroke-width="1.5" fill="none" stroke-linecap="round"/>
  <path d="M51,19 Q54,17.5 57,19" stroke="#1E1E1E" stroke-width="1.5" fill="none" stroke-linecap="round"/>
  <!-- Yeux -->
  <circle cx="45.5" cy="22.5" r="1.5" fill="#1E1E1E"/>
  <circle cx="54.5" cy="22.5" r="1.5" fill="#1E1E1E"/>
  <!-- Petit reflet dans les yeux -->
  <circle cx="46" cy="22" r="0.4" fill="#FFFFFF"/>
  <circle cx="55" cy="22" r="0.4" fill="#FFFFFF"/>
  <!-- Nez -->
  <path d="M50,24 Q49,27 50,29 Q51,27 50,24 Z" fill="#C99068"/>
  <!-- Bouche (concentré) -->
  <path d="M46,30.5 Q50,32 54,30.5" stroke="#1E1E1E" stroke-width="1.2" fill="none" stroke-linecap="round"/>
</svg>
''';

// SVG vectoriel — joueur vu de DOS, debout (silhouette en paths courbes)
const String _kSvgPlayerStand = r'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 150">
  <defs>
    <linearGradient id="pSkin" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#8C6749"/>
      <stop offset="100%" stop-color="#6E4A30"/>
    </linearGradient>
    <linearGradient id="pJersey" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#1A1A1A"/>
      <stop offset="100%" stop-color="#000000"/>
    </linearGradient>
  </defs>
  <!-- Ombre -->
  <ellipse cx="50" cy="143" rx="33" ry="4" fill="#000" opacity="0.4"/>
  <!-- Cuisses arrondies -->
  <path d="M40,92 Q40,89 43,89 L46,89 Q49,89 49,92 L49,118 Q49,121 46,121 L43,121 Q40,121 40,118 Z"
        fill="url(#pSkin)" stroke="#000" stroke-width="0.5"/>
  <path d="M51,92 Q51,89 54,89 L57,89 Q60,89 60,92 L60,118 Q60,121 57,121 L54,121 Q51,121 51,118 Z"
        fill="url(#pSkin)" stroke="#000" stroke-width="0.5"/>
  <!-- Chaussettes -->
  <path d="M40,114 L49,114 L49,121 L40,121 Z" fill="#FFFFFF" stroke="#000" stroke-width="0.3"/>
  <path d="M51,114 L60,114 L60,121 L51,121 Z" fill="#FFFFFF" stroke="#000" stroke-width="0.3"/>
  <!-- Chaussures -->
  <ellipse cx="44.5" cy="125" rx="9" ry="5" fill="#1A1A1A" stroke="#000" stroke-width="0.4"/>
  <ellipse cx="55.5" cy="125" rx="9" ry="5" fill="#1A1A1A" stroke="#000" stroke-width="0.4"/>
  <!-- Short blanc courbé -->
  <path d="M32,74 Q30,74 30,76 L30,90 Q30,94 32,94 L46,94 L48,90 L52,90 L54,94 L68,94 Q70,94 70,90 L70,76 Q70,74 68,74 Z"
        fill="#FFFFFF" stroke="#000" stroke-width="0.5"/>
  <!-- Maillot noir tapered avec épaules arrondies -->
  <path d="M26,44 Q26,32 38,30 L62,30 Q74,32 74,44 L74,78 Q74,80 72,80 L28,80 Q26,80 26,78 Z"
        fill="url(#pJersey)" stroke="#1A1A1A" stroke-width="0.4"/>
  <!-- Numéro 10 dans le dos -->
  <text x="50" y="62" font-family="Arial Black,sans-serif" font-size="22"
        font-weight="900" fill="#FFFFFF" text-anchor="middle">10</text>
  <!-- Bras gauche le long du corps (courbé) -->
  <path d="M26,44 Q22,44 22,48 Q22,62 24,76 L30,78 L30,46 Z" fill="url(#pJersey)"/>
  <!-- Bras droit le long du corps -->
  <path d="M74,44 Q78,44 78,48 Q78,62 76,76 L70,78 L70,46 Z" fill="url(#pJersey)"/>
  <!-- Mains -->
  <circle cx="24" cy="80" r="4.5" fill="url(#pSkin)" stroke="#000" stroke-width="0.4"/>
  <circle cx="76" cy="80" r="4.5" fill="url(#pSkin)" stroke="#000" stroke-width="0.4"/>
  <!-- Cou -->
  <path d="M46,28 L54,28 Q55,32 54,36 L46,36 Q45,32 46,28 Z" fill="url(#pSkin)"/>
  <!-- Tête vue de dos -->
  <ellipse cx="50" cy="20" rx="11" ry="13" fill="url(#pSkin)" stroke="#000" stroke-width="0.5"/>
  <!-- Cheveux (couvrent toute la tête vue de dos) -->
  <path d="M39,18 Q39,6 50,6 Q61,6 61,18 L61,25 Q60,22 50,22 Q40,22 39,25 Z" fill="#0A0A0A"/>
</svg>
''';

// SVG vectoriel — joueur en pleine frappe (jambe droite swingée, bras
// en équilibre, silhouette à courbes)
const String _kSvgPlayerKick = r'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 150">
  <defs>
    <linearGradient id="kkSkin" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#8C6749"/>
      <stop offset="100%" stop-color="#6E4A30"/>
    </linearGradient>
    <linearGradient id="kkJersey" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#1A1A1A"/>
      <stop offset="100%" stop-color="#000000"/>
    </linearGradient>
  </defs>
  <!-- Ombre allongée -->
  <ellipse cx="50" cy="143" rx="38" ry="4" fill="#000" opacity="0.4"/>
  <!-- Jambe d'appui gauche -->
  <path d="M40,92 Q40,89 43,89 L46,89 Q49,89 49,92 L49,118 Q49,121 46,121 L43,121 Q40,121 40,118 Z"
        fill="url(#kkSkin)" stroke="#000" stroke-width="0.5"/>
  <path d="M40,114 L49,114 L49,121 L40,121 Z" fill="#FFFFFF" stroke="#000" stroke-width="0.3"/>
  <ellipse cx="44.5" cy="125" rx="9" ry="5" fill="#1A1A1A" stroke="#000" stroke-width="0.4"/>
  <!-- Jambe de frappe droite (groupe avec rotation oblique) -->
  <g transform="translate(56 92) rotate(-35)">
    <path d="M0,0 Q0,-3 3,-3 L7,-3 Q10,-3 10,0 L10,28 Q10,31 7,31 L3,31 Q0,31 0,28 Z"
          fill="url(#kkSkin)" stroke="#000" stroke-width="0.5"/>
    <path d="M0,26 L10,26 L10,31 L0,31 Z" fill="#FFFFFF" stroke="#000" stroke-width="0.3"/>
    <ellipse cx="5" cy="34" rx="11" ry="5" fill="#1A1A1A" stroke="#000" stroke-width="0.4"/>
  </g>
  <!-- Short blanc courbé -->
  <path d="M32,74 Q30,74 30,76 L30,90 Q30,94 32,94 L46,94 L48,90 L52,90 L54,94 L68,94 Q70,94 70,90 L70,76 Q70,74 68,74 Z"
        fill="#FFFFFF" stroke="#000" stroke-width="0.5"/>
  <!-- Maillot noir -->
  <path d="M26,44 Q26,32 38,30 L62,30 Q74,32 74,44 L74,78 Q74,80 72,80 L28,80 Q26,80 26,78 Z"
        fill="url(#kkJersey)" stroke="#1A1A1A" stroke-width="0.4"/>
  <!-- Numéro 10 -->
  <text x="50" y="62" font-family="Arial Black,sans-serif" font-size="22"
        font-weight="900" fill="#FFFFFF" text-anchor="middle">10</text>
  <!-- Bras gauche ouvert pour équilibre (courbe) -->
  <path d="M26,44 Q14,42 6,52 Q2,56 4,62 Q8,60 14,56 Q22,52 26,50 Z"
        fill="url(#kkJersey)"/>
  <!-- Bras droit suit la frappe (vers l'avant) -->
  <path d="M74,44 Q86,46 92,58 Q94,62 92,66 Q86,62 80,58 Q76,54 74,52 Z"
        fill="url(#kkJersey)"/>
  <!-- Mains -->
  <circle cx="5" cy="58" r="4.5" fill="url(#kkSkin)" stroke="#000" stroke-width="0.4"/>
  <circle cx="92" cy="62" r="4.5" fill="url(#kkSkin)" stroke="#000" stroke-width="0.4"/>
  <!-- Cou -->
  <path d="M46,28 L54,28 Q55,32 54,36 L46,36 Q45,32 46,28 Z" fill="url(#kkSkin)"/>
  <!-- Tête (légèrement penchée vers la frappe — décalée à droite) -->
  <ellipse cx="51" cy="20" rx="11" ry="13" fill="url(#kkSkin)" stroke="#000" stroke-width="0.5"/>
  <!-- Cheveux -->
  <path d="M40,18 Q40,6 51,6 Q62,6 62,18 L62,25 Q61,22 51,22 Q41,22 40,25 Z" fill="#0A0A0A"/>
</svg>
''';

class _KeeperFigure extends StatelessWidget {
  final bool diving;
  const _KeeperFigure({required this.diving});
  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(_kSvgKeeper, fit: BoxFit.contain);
  }
}

class _PlayerFigure extends StatelessWidget {
  final bool kicking;
  const _PlayerFigure({this.kicking = false});
  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      kicking ? _kSvgPlayerKick : _kSvgPlayerStand,
      fit: BoxFit.contain,
    );
  }
}

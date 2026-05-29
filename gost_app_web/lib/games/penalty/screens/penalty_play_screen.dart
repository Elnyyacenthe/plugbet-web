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
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../../../widgets/network_lost_overlay.dart';
import '../../../ludo/services/audio_service.dart';
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
  }

  @override
  void dispose() {
    _shotCtrl.dispose();
    _bannerTimer?.cancel();
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
      final goalW = w * 0.78;
      final goalH = h * 0.32;
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
      final keeperW = goalW * 0.16;
      final keeperHomeX = goalLeft + (goalW - keeperW) / 2;
      final keeperY = goalTop + goalH * 0.32;
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
                width: keeperW, height: goalH * 0.55,
                child: _KeeperFigure(diving: _keeperDir != null && t > 0.1),
              ),
              // 6) Joueur (statique, en bas)
              Positioned(
                left: ballHomeX - w * 0.07,
                top: ballHomeY - h * 0.16,
                width: w * 0.10, height: h * 0.18,
                child: const _PlayerFigure(),
              ),
              // 7) Ballon (animé)
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

    // Son de frappe (reused : déplacement pion)
    try { AudioService.instance.playPawnMove(); } catch (_) {}

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
        AudioService.instance.playWin();
      } else {
        AudioService.instance.playCapture();
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
    // Filet : grille fine en gris clair
    final netPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    const cellW = 20.0;
    const cellH = 18.0;
    // Lignes verticales
    for (double x = cellW; x < w; x += cellW) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), netPaint);
    }
    // Lignes horizontales
    for (double y = cellH; y < h; y += cellH) {
      canvas.drawLine(Offset(0, y), Offset(w, y), netPaint);
    }
    // Cadre (poteaux + barre) blanc épais
    final framePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    // 2 poteaux + barre transversale
    canvas.drawLine(Offset(2, 0), Offset(2, h), framePaint);
    canvas.drawLine(Offset(w - 2, 0), Offset(w - 2, h), framePaint);
    canvas.drawLine(Offset(0, 2), Offset(w, 2), framePaint);
    // Petit dégradé d'ombre intérieur
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.5), shadowPaint);
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

class _KeeperFigure extends StatelessWidget {
  final bool diving;
  const _KeeperFigure({required this.diving});
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Bras écartés (rectangle horizontal)
        Positioned(
          top: 14,
          child: Container(
            width: 44,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xFF1AB6C8),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        // Tête
        Positioned(
          top: 0,
          child: Container(
            width: 14, height: 14,
            decoration: const BoxDecoration(
              color: Color(0xFFE2B48E),
              shape: BoxShape.circle,
            ),
          ),
        ),
        // Maillot (corps cyan)
        Positioned(
          top: 12,
          child: Container(
            width: 22, height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF1AB6C8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        // Short noir
        Positioned(
          top: 36,
          child: Container(
            width: 22, height: 12,
            color: Colors.black,
          ),
        ),
        // Jambes
        Positioned(
          top: 46,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 12, color: const Color(0xFFE2B48E)),
            const SizedBox(width: 4),
            Container(width: 6, height: 12, color: const Color(0xFFE2B48E)),
          ]),
        ),
      ],
    );
  }
}

class _PlayerFigure extends StatelessWidget {
  const _PlayerFigure();
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Tête
        Positioned(
          top: 0,
          child: Container(
            width: 14, height: 14,
            decoration: const BoxDecoration(
              color: Color(0xFF7C5A3E),
              shape: BoxShape.circle,
            ),
          ),
        ),
        // Maillot noir
        Positioned(
          top: 12,
          child: Container(
            width: 24, height: 28,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        // Short blanc
        Positioned(
          top: 38,
          child: Container(
            width: 24, height: 14,
            color: Colors.white,
          ),
        ),
        // Jambes
        Positioned(
          top: 50,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 14, color: const Color(0xFF7C5A3E)),
            const SizedBox(width: 4),
            Container(width: 6, height: 14, color: const Color(0xFF7C5A3E)),
          ]),
        ),
      ],
    );
  }
}

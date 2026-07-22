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
import '../../../services/audio_service.dart';
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
  late final AnimationController _ambientCtrl; // foule mexican wave (loop)
  late final AnimationController _confettiCtrl; // confettis sur but (one-shot)
  late final AnimationController _shakeCtrl; // camera shake (one-shot)
  PenaltyDirection? _aimDir; // direction choisie par le joueur
  PenaltyDirection? _keeperDir; // direction serveur du gardien

  @override
  void initState() {
    super.initState();
    AudioService.instance.configureGame('penalty');
    _shotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    PenaltyAudio.startAmbient();
  }

  @override
  void dispose() {
    _shotCtrl.dispose();
    _ambientCtrl.dispose();
    _confettiCtrl.dispose();
    _shakeCtrl.dispose();
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
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              title: Text(
                showResult
                    ? 'Résultat'
                    : 'Tir $shotDisplayed / ${round.totalShots}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, letterSpacing: 1),
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
        _scorePill('BUTS', round.goals, AppColors.neonGreen,
            Icons.sports_soccer_rounded),
        _scorePill(
            'RATÉS', round.misses, AppColors.neonRed, Icons.close_rounded),
        _scorePill('MISE', round.betAmount, AppColors.neonYellow,
            Icons.monetization_on_rounded),
      ],
    );
  }

  Widget _scorePill(String label, int value, Color c, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.withValues(alpha: 0.18),
            c.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: c.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(color: c.withValues(alpha: 0.2), blurRadius: 12),
        ],
      ),
      child: Column(children: [
        Icon(icon, color: c, size: 16),
        const SizedBox(height: 2),
        Text('$value',
            style:
                TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w900)),
        Text(label,
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700)),
      ]),
    );
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
      final aimZoneX =
          _aimDir == null ? ballHomeX : _zoneCenterX(goalLeft, goalW, _aimDir!);
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
        animation: Listenable.merge([
          _shotCtrl,
          _ambientCtrl,
          _confettiCtrl,
          _shakeCtrl,
        ]),
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

          // Camera shake : oscillation rapide pendant 450ms (apres but)
          final shakeT = _shakeCtrl.value;
          final shakeAmp = shakeT > 0 ? (1 - shakeT) * 8 : 0.0;
          final shakeX =
              shakeAmp * (shakeT * 30).remainder(2) > 1 ? shakeAmp : -shakeAmp;
          final shakeY = shakeAmp * 0.5;

          return Transform.translate(
            offset: Offset(shakeX, shakeY),
            child: Stack(
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
                  top: 0,
                  left: 0,
                  right: 0,
                  height: h * 0.18,
                  child:
                      CustomPaint(painter: _CrowdPainter(_ambientCtrl.value)),
                ),
                // 3) Sol : lignes de pelouse + ligne de surface
                Positioned(
                  left: 0,
                  right: 0,
                  top: groundY,
                  bottom: 0,
                  child: CustomPaint(painter: _PitchPainter()),
                ),
                // 4) Cage (poteaux + filet)
                Positioned(
                  left: goalLeft,
                  top: goalTop,
                  width: goalW,
                  height: goalH,
                  child: CustomPaint(
                    painter: _GoalPainter(),
                  ),
                ),
                // 5) Gardien (animé)
                Positioned(
                  left: keeperX,
                  top: keeperYAnim,
                  width: keeperW,
                  height: keeperH,
                  child: _KeeperFigure(diving: _keeperDir != null && t > 0.1),
                ),
                // 6) Joueur (statique en attente, jambe levée pendant le tir)
                Positioned(
                  left: ballHomeX - w * 0.10,
                  top: ballHomeY - h * 0.24,
                  width: w * 0.20,
                  height: h * 0.26,
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
                  width: ballSize,
                  height: ballSize,
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
                    top: h * 0.02,
                    left: 16,
                    right: 16,
                    child: _shotResultBanner(_lastShot!),
                  ),
                // 10) Hint quand pas d'animation
                if (!_animating && !_showBanner)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text('Tape une zone du but pour tirer',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                // 11) Confettis sur but (full screen)
                if (_confettiCtrl.value > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ConfettiPainter(_confettiCtrl.value),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    });
  }

  double _zoneCenterX(double goalLeft, double goalW, PenaltyDirection d) {
    final zoneW = goalW / 3;
    switch (d) {
      case PenaltyDirection.left:
        return goalLeft + zoneW * 0.5;
      case PenaltyDirection.center:
        return goalLeft + zoneW * 1.5;
      case PenaltyDirection.right:
        return goalLeft + zoneW * 2.5;
    }
  }

  List<Widget> _buildTapZones(
    double goalLeft,
    double goalTop,
    double goalW,
    double goalH,
    double goalRight,
    double goalBottom,
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
              blurRadius: 14,
              spreadRadius: 1),
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

    // Son de résultat + VFX si but
    try {
      if (res.isGoal) {
        PenaltyAudio.playGoal();
        _confettiCtrl.forward(from: 0);
        _shakeCtrl.forward(from: 0);
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
      try {
        await wallet.refresh();
      } catch (_) {}
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
                : (isAbandoned ? AppColors.textMuted : AppColors.neonRed),
          ),
          const SizedBox(height: 18),
          Text(
            isWin
                ? 'VICTOIRE !'
                : (isAbandoned ? 'Round abandonné' : 'DÉFAITE'),
            style: TextStyle(
              color: isWin
                  ? AppColors.neonYellow
                  : (isAbandoned ? AppColors.textSecondary : AppColors.neonRed),
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
            _bilanPill(
                '-${round.betAmount} coins (mise perdue)', AppColors.neonRed),
          const Spacer(),
          GestureDetector(
            onTap: () {
              prov.reset();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const PenaltyBetScreen()),
              );
            },
            child: Container(
              width: double.infinity,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.neonGreen,
                    AppColors.neonGreen.withValues(alpha: 0.75),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonGreen.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Text('Rejouer',
                  style: TextStyle(
                      color: AppColors.bgDark,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5)),
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
          style:
              TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w900)),
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
            style: TextStyle(color: AppColors.textSecondary, height: 1.5)),
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
                    color: AppColors.neonRed, fontWeight: FontWeight.w700)),
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

    // 1) Voile sombre dans la cage (profondeur)
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h),
        Paint()..color = Colors.black.withValues(alpha: 0.22));

    // 2) Filet : maille CARRÉE serrée (plus pro qu'un cross-hatch diagonal)
    final netPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 0.8;
    const cell = 11.0;
    // Verticales legerement obliques pour donner perspective (centre attire)
    for (double x = 0; x <= w; x += cell) {
      final px = x;
      canvas.drawLine(
        Offset(px, 0),
        Offset(px + (w / 2 - px) * 0.12, h), // converge vers centre en bas
        netPaint,
      );
    }
    // Horizontales avec pas plus grand vers le bas (perspective)
    double y = 0;
    double step = cell * 0.7;
    while (y <= h) {
      canvas.drawLine(Offset(0, y), Offset(w, y), netPaint);
      step *= 1.04;
      y += step;
    }

    // 3) Ombre haute (depth from above)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.45),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.40),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h * 0.45)),
    );

    // 4) Poteaux + barre avec effet 3D (gradient chrome)
    const postW = 8.0;
    final postGrad = LinearGradient(
      colors: [
        Colors.white.withValues(alpha: 0.95),
        Colors.white,
        Colors.white.withValues(alpha: 0.75),
      ],
      stops: const [0, 0.5, 1.0],
    );

    // Poteau gauche
    final leftRect = Rect.fromLTWH(0, 0, postW, h);
    canvas.drawRect(
        leftRect, Paint()..shader = postGrad.createShader(leftRect));
    // Poteau droit
    final rightRect = Rect.fromLTWH(w - postW, 0, postW, h);
    canvas.drawRect(
        rightRect, Paint()..shader = postGrad.createShader(rightRect));
    // Barre transversale
    final topRect = Rect.fromLTWH(0, 0, w, postW);
    canvas.drawRect(
      topRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0.7),
          ],
        ).createShader(topRect),
    );

    // Ombres internes (poteau cote interieur + sous la barre)
    final shadeP = Paint()..color = Colors.black.withValues(alpha: 0.30);
    canvas.drawRect(Rect.fromLTWH(postW, 0, 3, h), shadeP);
    canvas.drawRect(Rect.fromLTWH(w - postW - 3, 0, 3, h), shadeP);
    canvas.drawRect(Rect.fromLTWH(0, postW, w, 3), shadeP);
  }

  @override
  bool shouldRepaint(_GoalPainter old) => false;
}

// Confettis qui tombent apres un but (animation 2.2s)
class _ConfettiPainter extends CustomPainter {
  final double t; // 0..1
  _ConfettiPainter(this.t);

  static final List<_ConfettiParticle> _particles = List.generate(60, (i) {
    final rng = _PseudoRng(7919 + i * 31);
    return _ConfettiParticle(
      xStart: rng.next() / 0x7fffffff,
      delay: (rng.next() / 0x7fffffff) * 0.35,
      speed: 0.55 + (rng.next() / 0x7fffffff) * 0.45,
      drift: (rng.next() / 0x7fffffff - 0.5) * 0.18,
      hue: rng.nextInt(7),
      size: 4.0 + (rng.next() / 0x7fffffff) * 5.0,
      rotSpeed: 4 + (rng.next() / 0x7fffffff) * 8,
    );
  });

  static const _palette = [
    Color(0xFFFFD93D),
    Color(0xFFE63946),
    Color(0xFF06A77D),
    Color(0xFF118AB2),
    Color(0xFFEF476F),
    Color(0xFFFFD166),
    Color(0xFF8338EC),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    for (final p in _particles) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Fall + drift lateral
      final cx = (p.xStart + p.drift * local) * size.width;
      final cy = local * p.speed * size.height;
      if (cy > size.height) continue;
      // Fade out vers la fin
      final fade = (1 - local * 0.7).clamp(0.0, 1.0);
      final color = _palette[p.hue].withValues(alpha: fade);
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(local * p.rotSpeed);
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: p.size, height: p.size * 0.5),
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

class _ConfettiParticle {
  final double xStart;
  final double delay;
  final double speed;
  final double drift;
  final int hue;
  final double size;
  final double rotSpeed;
  const _ConfettiParticle({
    required this.xStart,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.hue,
    required this.size,
    required this.rotSpeed,
  });
}

class _CrowdPainter extends CustomPainter {
  final double t; // 0..1 wave phase
  _CrowdPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Fond tribune avec gradient (toit assombri en haut)
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF14202F),
            Color(0xFF1F2F44),
            Color(0xFF26354A),
          ],
        ).createShader(Offset.zero & size),
    );

    // Toit du stade : barre sombre en haut + projecteurs (cercles lumineux)
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, 8),
      Paint()..color = const Color(0xFF0A1118),
    );
    // 4 projecteurs blancs
    final flood = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (int i = 0; i < 4; i++) {
      final cx = (w / 5) * (i + 1);
      canvas.drawCircle(Offset(cx, 4), 4, flood);
      // halo lumiere descendante
      canvas.drawRect(
        Rect.fromLTWH(cx - 30, 8, 60, h * 0.6),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(cx - 30, 8, 60, h * 0.6))
          ..blendMode = BlendMode.plus,
      );
    }

    // Spectateurs : silhouettes humanoides realistes (tete + epaules + bras)
    // Couleurs jerseys desaturees pour effet plus naturel (pas du fluo).
    const palette = [
      Color(0xFFD45050),
      Color(0xFFE0A028),
      Color(0xFF4DA8C7),
      Color(0xFFE8C842),
      Color(0xFF8A6FD0),
      Color(0xFF66BA7A),
      Color(0xFFC83B45),
      Color(0xFF2A6DAA),
      Color(0xFF4F5663),
      Color(0xFFB85433),
      Color(0xFFFFFFFF),
      Color(0xFF1A1A1A),
    ];
    final rng = _PseudoRng(42);
    const rows = 6;
    final rowH = (h - 22) / (rows + 1);

    for (int r = 0; r < rows; r++) {
      // Rangee plus proches en bas = plus grandes (effet perspective)
      final scale = 0.7 + (r / (rows - 1)) * 0.6;
      final y = 18 + rowH * (r + 0.5);
      final dx = 7.0 + r * 0.6;
      final headR = 1.8 * scale;
      final shoulderW = 6.0 * scale;
      final shoulderH = 3.0 * scale;
      final armReach = 4.5 * scale;

      for (double x = 4; x < w; x += dx) {
        final jitter = (rng.next() / 0x7fffffff - 0.5) * 1.4;
        final jersey = palette[rng.nextInt(palette.length)];
        final raisesArms = (rng.next() / 0x7fffffff) < 0.15; // 15% bras leves

        // Mexican wave : effet vague (rises 8-10px en passant)
        final wavePos = t * w * 1.5;
        final dist = (x - wavePos).abs() % w;
        final waveAmp = (1.0 - (dist / 50)).clamp(0.0, 1.0);
        final yWave = y - waveAmp * 7;
        final cx = x + jitter;

        // 1) Epaules + torse (trapeze, plus large en haut)
        final shoulderPath = Path()
          ..moveTo(cx - shoulderW / 2, yWave + headR + 1)
          ..lineTo(cx + shoulderW / 2, yWave + headR + 1)
          ..lineTo(cx + shoulderW / 2 - 0.5, yWave + headR + 1 + shoulderH)
          ..lineTo(cx - shoulderW / 2 + 0.5, yWave + headR + 1 + shoulderH)
          ..close();
        canvas.drawPath(shoulderPath, Paint()..color = jersey);

        // 2) Bras (leves si wave OU random, sinon le long du corps)
        if (raisesArms || waveAmp > 0.6) {
          // Bras leves "V"
          canvas.drawLine(
            Offset(cx - shoulderW / 2 + 0.5, yWave + headR + 1),
            Offset(cx - shoulderW / 2 - 1.5, yWave - armReach),
            Paint()
              ..color = jersey
              ..strokeWidth = 1.4 * scale
              ..strokeCap = StrokeCap.round,
          );
          canvas.drawLine(
            Offset(cx + shoulderW / 2 - 0.5, yWave + headR + 1),
            Offset(cx + shoulderW / 2 + 1.5, yWave - armReach),
            Paint()
              ..color = jersey
              ..strokeWidth = 1.4 * scale
              ..strokeCap = StrokeCap.round,
          );
        }

        // 3) Tete (couleur peau ou sombre alternant pour diversite)
        final skinTone = (rng.nextInt(3) == 0)
            ? const Color(0xFF6B4423) // peau foncee
            : (rng.nextInt(2) == 0
                ? const Color(0xFFC99068)
                : const Color(0xFFE6B894)); // peau plus claire
        canvas.drawCircle(
          Offset(cx, yWave),
          headR,
          Paint()..color = skinTone,
        );
      }
    }

    // Bandeau publicité (LED scrolling effect)
    final adRect = Rect.fromLTWH(0, h - 14, w, 14);
    canvas.drawRect(
      adRect,
      Paint()
        ..shader = LinearGradient(
          colors: const [
            Color(0xFF0066CC),
            Color(0xFF003D7A),
            Color(0xFF0066CC),
          ],
        ).createShader(adRect),
    );
    // Texte PLUGBET scrolling
    final scroll = (t * w * 1.5) % (w + 100) - 100;
    final tp = TextPainter(
      text: const TextSpan(
        text: 'PLUGBET · PARIS · CASINO · BONUS · PLUGBET · PARIS',
        style: TextStyle(
          color: Color(0xFFFFD93D),
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(scroll, h - 12));
  }

  @override
  bool shouldRepaint(_CrowdPainter old) => old.t != t;
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Pelouse : gradient + bandes de tonte alternees (perspective)
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF1A5A24),
            Color(0xFF2A7838),
          ],
        ).createShader(Offset.zero & size),
    );
    // Bandes alternees fines (effet tondeuse rotative)
    final darkBand = Paint()..color = Colors.black.withValues(alpha: 0.10);
    const bandH = 14.0;
    for (double y = 0; y < h; y += bandH * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, bandH), darkBand);
    }

    // Lignes du terrain (blanc semi-transparent)
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    // Ligne 18 yards box (rectangle ouvert, ouverture vers le bas)
    final boxLeft = w * 0.20;
    final boxRight = w * 0.80;
    final boxTop = h * 0.05;
    final boxBottom = h * 0.55;
    canvas.drawLine(
        Offset(boxLeft, boxTop), Offset(boxRight, boxTop), linePaint);
    canvas.drawLine(
        Offset(boxLeft, boxTop), Offset(boxLeft, boxBottom), linePaint);
    canvas.drawLine(
        Offset(boxRight, boxTop), Offset(boxRight, boxBottom), linePaint);

    // Ligne 6 yards (interieure)
    final smLeft = w * 0.35;
    final smRight = w * 0.65;
    final smTop = h * 0.05;
    final smBottom = h * 0.22;
    canvas.drawLine(Offset(smLeft, smTop), Offset(smRight, smTop), linePaint);
    canvas.drawLine(Offset(smLeft, smTop), Offset(smLeft, smBottom), linePaint);
    canvas.drawLine(
        Offset(smRight, smTop), Offset(smRight, smBottom), linePaint);

    // Penalty spot (gros point blanc)
    final spotY = h * 0.42;
    canvas.drawCircle(
      Offset(w / 2, spotY),
      4.5,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    // Arc demi-cercle au-dessus du point (penalty arc - se courbe vers le bas)
    final arcRect = Rect.fromCenter(
      center: Offset(w / 2, spotY),
      width: 90,
      height: 90,
    );
    canvas.drawArc(arcRect, 0.5, 2.2, false, linePaint);
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
      <stop offset="60%" stop-color="#1AB3C3"/>
      <stop offset="100%" stop-color="#0A8A98"/>
    </linearGradient>
    <linearGradient id="kSkin" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#C99068"/>
      <stop offset="100%" stop-color="#9E6E4A"/>
    </linearGradient>
    <linearGradient id="kPant" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#0E9EAE"/>
      <stop offset="100%" stop-color="#075A66"/>
    </linearGradient>
  </defs>
  <!-- Ombre au sol -->
  <ellipse cx="50" cy="146" rx="26" ry="3" fill="#000" opacity="0.45"/>

  <!-- JAMBES (legerement flechies, position 'ready') -->
  <!-- Cuisse gauche -->
  <path d="M42,92 Q41,90 43.5,89 L46.5,89 Q48.5,90 48,93 L47,116 Q47,118 45,118 L43,118 Q41,118 41,115 Z"
        fill="url(#kPant)" stroke="#063038" stroke-width="0.6"/>
  <!-- Cuisse droite -->
  <path d="M52,93 Q51.5,90 53.5,89 L56.5,89 Q59,90 58,92 L59,115 Q59,118 57,118 L55,118 Q53,118 53,116 Z"
        fill="url(#kPant)" stroke="#063038" stroke-width="0.6"/>
  <!-- Mollets / chaussettes blanches -->
  <path d="M41,116 L48,116 L48,128 Q48,130 46,130 L43,130 Q41,130 41,128 Z" fill="#FFFFFF" stroke="#000" stroke-width="0.4"/>
  <path d="M52,116 L59,116 L59,128 Q59,130 57,130 L54,130 Q52,130 52,128 Z" fill="#FFFFFF" stroke="#000" stroke-width="0.4"/>
  <!-- Chaussures (vue legerement perspective) -->
  <ellipse cx="44.5" cy="133" rx="8" ry="3.5" fill="#1A1A1A" stroke="#000" stroke-width="0.5"/>
  <ellipse cx="55.5" cy="133" rx="8" ry="3.5" fill="#1A1A1A" stroke="#000" stroke-width="0.5"/>
  <ellipse cx="43.5" cy="132" rx="6" ry="1.2" fill="#3A3A3A"/>
  <ellipse cx="54.5" cy="132" rx="6" ry="1.2" fill="#3A3A3A"/>

  <!-- TORSE (forme V plus athletique) -->
  <path d="M31,46 Q30,38 38,33 Q43,35 50,35 Q57,35 62,33 Q70,38 69,46 L72,80 Q72,82 70,82 L30,82 Q28,82 28,80 Z"
        fill="url(#kJersey)" stroke="#063038" stroke-width="0.7"/>
  <!-- Bande horizontale poitrine -->
  <rect x="28" y="56" width="44" height="3" fill="#FFFFFF" opacity="0.9"/>
  <rect x="28" y="62" width="44" height="2" fill="#FFFFFF" opacity="0.6"/>
  <!-- Numero 1 dans le dos -->
  <text x="50" y="74" font-family="Impact, Arial Black,sans-serif" font-size="13"
        font-weight="900" fill="#FFFFFF" text-anchor="middle">1</text>
  <!-- Col en V -->
  <path d="M44,33 L50,40 L56,33 L54,32 L50,36 L46,32 Z" fill="#075A66"/>

  <!-- BRAS (pose 'ready' : semi-flechis, gants en avant pas grands ecartes) -->
  <!-- Bras gauche -->
  <path d="M28,48 Q22,50 18,58 Q14,68 16,76 Q19,68 22,62 Q26,54 31,52 Z"
        fill="url(#kJersey)" stroke="#063038" stroke-width="0.5"/>
  <!-- Bras droit -->
  <path d="M72,48 Q78,50 82,58 Q86,68 84,76 Q81,68 78,62 Q74,54 69,52 Z"
        fill="url(#kJersey)" stroke="#063038" stroke-width="0.5"/>
  <!-- Avant-bras visibles (peau) -->
  <ellipse cx="16" cy="76" rx="3" ry="6" fill="url(#kSkin)" stroke="#000" stroke-width="0.4"/>
  <ellipse cx="84" cy="76" rx="3" ry="6" fill="url(#kSkin)" stroke="#000" stroke-width="0.4"/>
  <!-- Gants jaunes (en avant, semi-fermes) -->
  <path d="M11,78 Q8,82 12,88 Q18,90 22,86 Q23,82 20,78 L18,78 Q17,80 18,84 L15,84 Q14,80 16,78 Z"
        fill="#FFD500" stroke="#A88A00" stroke-width="0.8"/>
  <path d="M89,78 Q92,82 88,88 Q82,90 78,86 Q77,82 80,78 L82,78 Q83,80 82,84 L85,84 Q86,80 84,78 Z"
        fill="#FFD500" stroke="#A88A00" stroke-width="0.8"/>
  <!-- Detail brides gants -->
  <line x1="11" y1="80" x2="22" y2="80" stroke="#A88A00" stroke-width="0.4"/>
  <line x1="78" y1="80" x2="89" y2="80" stroke="#A88A00" stroke-width="0.4"/>

  <!-- COU (plus court, plus naturel) -->
  <path d="M46,29 L54,29 L54,33 Q54,34 53,34 L47,34 Q46,34 46,33 Z" fill="url(#kSkin)"/>
  <ellipse cx="50" cy="34" rx="4" ry="1" fill="#000" opacity="0.18"/>

  <!-- TETE (plus petite, ovale realiste 8x10 au lieu de 11x13) -->
  <ellipse cx="50" cy="20" rx="8" ry="10" fill="url(#kSkin)" stroke="#000" stroke-width="0.6"/>
  <!-- Oreilles -->
  <ellipse cx="42" cy="20" rx="1.3" ry="2.2" fill="url(#kSkin)" stroke="#000" stroke-width="0.3"/>
  <ellipse cx="58" cy="20" rx="1.3" ry="2.2" fill="url(#kSkin)" stroke="#000" stroke-width="0.3"/>
  <!-- Cheveux (calotte courte) -->
  <path d="M42,17 Q42,9 50,9 Q58,9 58,17 Q56,13 50,12 Q44,13 42,17 Z" fill="#1E1E1E"/>
  <!-- Sourcils plus marques -->
  <path d="M43.5,18 Q46,17 48.5,18.2" stroke="#1E1E1E" stroke-width="1.2" fill="none" stroke-linecap="round"/>
  <path d="M51.5,18.2 Q54,17 56.5,18" stroke="#1E1E1E" stroke-width="1.2" fill="none" stroke-linecap="round"/>
  <!-- Yeux -->
  <ellipse cx="46" cy="21" rx="0.9" ry="1.1" fill="#FFFFFF"/>
  <ellipse cx="54" cy="21" rx="0.9" ry="1.1" fill="#FFFFFF"/>
  <circle cx="46.2" cy="21.2" r="0.7" fill="#1E1E1E"/>
  <circle cx="54.2" cy="21.2" r="0.7" fill="#1E1E1E"/>
  <!-- Nez (ombre laterale) -->
  <path d="M50,23 L48.5,27 Q49.5,28 50,28 Q50.5,28 51.5,27 Z" fill="#9E6E4A"/>
  <!-- Bouche concentre -->
  <line x1="47" y1="29.5" x2="53" y2="29.5" stroke="#1E1E1E" stroke-width="1" stroke-linecap="round"/>
  <!-- Ombre sous chin -->
  <ellipse cx="50" cy="32" rx="6" ry="0.8" fill="#000" opacity="0.18"/>
</svg>
''';

// SVG vectoriel — joueur vu de DOS, debout (proportions humaines realistes)
const String _kSvgPlayerStand = r'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 150">
  <defs>
    <linearGradient id="pSkin" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#8C6749"/>
      <stop offset="100%" stop-color="#5E3F26"/>
    </linearGradient>
    <linearGradient id="pJersey" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#2A2A2A"/>
      <stop offset="50%" stop-color="#1A1A1A"/>
      <stop offset="100%" stop-color="#000000"/>
    </linearGradient>
    <linearGradient id="pShort" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#FFFFFF"/>
      <stop offset="100%" stop-color="#D0D0D0"/>
    </linearGradient>
  </defs>
  <!-- Ombre au sol -->
  <ellipse cx="50" cy="146" rx="28" ry="3" fill="#000" opacity="0.45"/>

  <!-- JAMBES (formes plus realistes avec mollet/cuisse separes) -->
  <!-- Jambe gauche : cuisse + mollet -->
  <path d="M41,95 Q40,93 42,92 L46,92 Q48,93 48,95 L48,114 Q48,116 46,116 L43,116 Q41,116 41,114 Z"
        fill="url(#pShort)" stroke="#888" stroke-width="0.4"/>
  <path d="M41,114 Q40,113 42,112 L46,112 Q48,114 47,116 L47,130 Q47,132 45,132 L43,132 Q41,131 41,130 Z"
        fill="url(#pSkin)" stroke="#000" stroke-width="0.4"/>
  <!-- Jambe droite -->
  <path d="M52,95 Q52,93 54,92 L58,92 Q60,93 59,95 L59,114 Q59,116 57,116 L54,116 Q52,116 52,114 Z"
        fill="url(#pShort)" stroke="#888" stroke-width="0.4"/>
  <path d="M52,114 Q52,113 54,112 L58,112 Q60,114 59,116 L59,130 Q59,132 57,132 L55,132 Q53,131 53,130 Z"
        fill="url(#pSkin)" stroke="#000" stroke-width="0.4"/>
  <!-- Chaussettes (bas de la jambe) -->
  <rect x="41" y="128" width="7" height="4" fill="#FFFFFF" stroke="#000" stroke-width="0.3"/>
  <rect x="52" y="128" width="7" height="4" fill="#FFFFFF" stroke="#000" stroke-width="0.3"/>
  <!-- Chaussures (plates, vue legere perspective) -->
  <ellipse cx="44.5" cy="135" rx="8" ry="3.5" fill="#1A1A1A" stroke="#000" stroke-width="0.5"/>
  <ellipse cx="55.5" cy="135" rx="8" ry="3.5" fill="#1A1A1A" stroke="#000" stroke-width="0.5"/>
  <line x1="38" y1="134" x2="52" y2="134" stroke="#FFFFFF" stroke-width="0.4"/>
  <line x1="49" y1="134" x2="63" y2="134" stroke="#FFFFFF" stroke-width="0.4"/>

  <!-- SHORT (avec separation centrale) -->
  <path d="M33,76 Q32,75 32,77 L32,92 Q32,94 34,94 L48,94 L50,90 L52,94 L66,94 Q68,94 68,92 L68,77 Q68,75 67,76 Z"
        fill="url(#pShort)" stroke="#888" stroke-width="0.5"/>
  <line x1="50" y1="80" x2="50" y2="92" stroke="#AAA" stroke-width="0.5"/>

  <!-- TORSE forme V (epaules larges, taille fine) -->
  <path d="M30,46 Q29,38 36,32 Q43,34 50,34 Q57,34 64,32 Q71,38 70,46 L72,78 Q72,80 70,80 L30,80 Q28,80 28,78 Z"
        fill="url(#pJersey)" stroke="#000" stroke-width="0.5"/>
  <!-- Detail couture verticale -->
  <line x1="50" y1="34" x2="50" y2="80" stroke="#3A3A3A" stroke-width="0.3"/>
  <!-- Numero 10 grand dans le dos -->
  <text x="50" y="64" font-family="Impact, Arial Black, sans-serif" font-size="26"
        font-weight="900" fill="#FFFFFF" text-anchor="middle">10</text>
  <!-- Col arriere -->
  <path d="M44,33 Q50,36 56,33 L56,35 Q50,38 44,35 Z" fill="#000"/>

  <!-- BRAS le long du corps -->
  <path d="M28,46 Q24,46 23,52 L22,74 Q22,77 24,77 L31,77 L31,48 Z" fill="url(#pJersey)" stroke="#000" stroke-width="0.4"/>
  <path d="M72,46 Q76,46 77,52 L78,74 Q78,77 76,77 L69,77 L69,48 Z" fill="url(#pJersey)" stroke="#000" stroke-width="0.4"/>
  <!-- Avant-bras (peau visible sous la manche courte) -->
  <ellipse cx="25" cy="83" rx="3.5" ry="6" fill="url(#pSkin)" stroke="#000" stroke-width="0.4"/>
  <ellipse cx="75" cy="83" rx="3.5" ry="6" fill="url(#pSkin)" stroke="#000" stroke-width="0.4"/>

  <!-- COU plus court -->
  <path d="M46,30 L54,30 L53,34 L47,34 Z" fill="url(#pSkin)"/>
  <ellipse cx="50" cy="34" rx="4" ry="1" fill="#000" opacity="0.2"/>

  <!-- TETE (proportions naturelles 7.5x9.5 au lieu de 11x13) -->
  <ellipse cx="50" cy="22" rx="7.5" ry="9.5" fill="url(#pSkin)" stroke="#000" stroke-width="0.5"/>
  <!-- Oreilles -->
  <ellipse cx="42.5" cy="22" rx="1.2" ry="2" fill="url(#pSkin)" stroke="#000" stroke-width="0.3"/>
  <ellipse cx="57.5" cy="22" rx="1.2" ry="2" fill="url(#pSkin)" stroke="#000" stroke-width="0.3"/>
  <!-- Cheveux courts noirs vue de dos -->
  <path d="M42,19 Q42,12 50,11 Q58,12 58,19 L58,25 Q56,22.5 50,22.5 Q44,22.5 42,25 Z" fill="#0A0A0A"/>
  <!-- Detail coupe : ligne nuque -->
  <path d="M44,29 Q50,30.5 56,29" stroke="#0A0A0A" stroke-width="0.6" fill="none"/>
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

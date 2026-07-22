// ============================================================
// AVIATOR - Ecran de jeu principal (style casino multijoueur)
// Premium redesign — logique de jeu strictement inchangée.
// Layout :
//   • Wide (>=900px) : panneau gauche (live bets) + centre (jeu) + panneau droit (gains)
//   • Mobile : panneaux en sheets repliables, centre plein ecran
//   • Bas : historique crashes + 1/2 panneaux de mise
// ============================================================

import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../models/aviator_models.dart';
import '../providers/aviator_provider.dart';
import '../widgets/multiplier_curve_painter.dart';
import '../widgets/bet_slot.dart';
import '../widgets/plane_widget.dart';
import '../widgets/live_bets_panel.dart';
import '../widgets/live_winnings_panel.dart';
import '../widgets/aviator_background.dart';
import '../../../widgets/network_lost_overlay.dart';
import '../../../services/audio_service.dart';

const _kAviatorRed = Color(0xFFEF4444);
const _kAviatorOrange = Color(0xFFF97316);

class AviatorGameScreen extends StatelessWidget {
  final bool demoMode;
  const AviatorGameScreen({super.key, this.demoMode = false});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AviatorProvider()..isDemoMode = demoMode,
      child: const _AviatorBody(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
class _AviatorBody extends StatefulWidget {
  const _AviatorBody();
  @override
  State<_AviatorBody> createState() => _AviatorBodyState();
}

class _AviatorBodyState extends State<_AviatorBody>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  bool _showLiveBetsSheet = false;
  bool _showWinningsSheet = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 24).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
  }

  Future<void> _initAudio() async {
    await AudioService.instance.configureGame('aviator');
    AudioService.instance.startBackgroundMusic();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    AudioService.instance.stopBackgroundMusic();
    super.dispose();
  }

  void _onPhaseCrashed() {
    HapticFeedback.heavyImpact();
    AudioService.instance.playCrash();
    _shakeCtrl.forward(from: 0);
  }

  void _onCashOut(AviatorProvider prov, AviatorBet bet) {
    HapticFeedback.mediumImpact();
    AudioService.instance.playClimb();
    prov.cashOut(bet);
  }

  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Consumer<AviatorProvider>(
      builder: (ctx, prov, _) {
        if (prov.phase == AviatorPhase.crashed &&
            _shakeCtrl.status == AnimationStatus.dismissed) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _onPhaseCrashed());
        }

        return Scaffold(
          backgroundColor: const Color(0xFF050508),
          extendBodyBehindAppBar: false,
          appBar: _buildAppBar(prov, wallet),
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0B0B14),
                  Color(0xFF050508),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final wide = constraints.maxWidth >= 900;
                if (wide) return _buildWideLayout(prov);
                return _buildMobileLayout(prov);
              },
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // LAYOUT WIDE (>= 900px) : 3 colonnes
  // ─────────────────────────────────────────────────────────
  Widget _buildWideLayout(AviatorProvider prov) {
    return Row(
      children: [
        const LiveBetsPanel(width: 260),
        Expanded(
          child: Column(
            children: [
              _buildCrashHistory(prov),
              Expanded(child: _buildGameCenter(prov)),
              _buildBetPanel(prov),
            ],
          ),
        ),
        const LiveWinningsPanel(width: 200),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // LAYOUT MOBILE : panneaux en sheets repliables
  // ─────────────────────────────────────────────────────────
  Widget _buildMobileLayout(AviatorProvider prov) {
    return Stack(
      children: [
        Column(
          children: [
            _buildCrashHistory(prov),
            _buildMobileStatsBar(prov),
            Expanded(child: _buildGameCenter(prov)),
            _buildBetPanel(prov),
          ],
        ),
        if (_showLiveBetsSheet)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => setState(() => _showLiveBetsSheet = false),
              child: Row(
                children: [
                  const LiveBetsPanel(width: 240),
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                      child: Container(
                        width: MediaQuery.of(context).size.width - 240,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_showWinningsSheet)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: () => setState(() => _showWinningsSheet = false),
              child: Row(
                children: [
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                      child: Container(
                        width: MediaQuery.of(context).size.width - 200,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  const LiveWinningsPanel(width: 200),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── Barre stats (mobile) : accès rapide aux panneaux ───
  Widget _buildMobileStatsBar(AviatorProvider prov) {
    final totalBets = prov.liveBets.length;
    final totalWagered = prov.liveBets.fold<int>(0, (a, b) => a + b.amount);
    return Container(
      color: const Color(0xFF0A0A10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showLiveBetsSheet = true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0F2015),
                      AppColors.neonGreen.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.neonGreen.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.groups, color: Colors.white70, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$totalBets paris · $totalWagered',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: Colors.white54, size: 14),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showWinningsSheet = true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF0F2015),
                      AppColors.neonGreen.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.neonGreen.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonGreen.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.bolt, color: AppColors.neonGreen, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'Gains live',
                      style: TextStyle(
                          color: AppColors.neonGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        color: Colors.white54, size: 14),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────
  AppBar _buildAppBar(AviatorProvider prov, WalletProvider wallet) {
    return AppBar(
      backgroundColor: const Color(0xFF0A0A10),
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0A0A10),
              Color.lerp(const Color(0xFF0A0A10), _kAviatorRed, 0.08)!,
            ],
          ),
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Text('✈ ',
              style: TextStyle(
                fontSize: 18,
                color: _kAviatorRed,
                shadows: [
                  Shadow(color: _kAviatorRed.withValues(alpha: 0.6), blurRadius: 10),
                ],
              )),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_kAviatorRed, Color(0xFFFF8A8A)],
            ).createShader(bounds),
            child: const Text(
              'AVIATOR',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                fontSize: 16,
              ),
            ),
          ),
          if (prov.isDemoMode) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.neonBlue.withValues(alpha: 0.28),
                    AppColors.neonBlue.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.neonBlue.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonBlue.withValues(alpha: 0.25),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Text('DEMO',
                  style: TextStyle(
                      color: AppColors.neonBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.neonYellow.withValues(alpha: 0.2),
                  AppColors.neonYellow.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.monetization_on,
                    color: AppColors.neonYellow, size: 16),
                const SizedBox(width: 4),
                Text(
                  prov.isDemoMode ? '∞' : '${wallet.coins}',
                  style: TextStyle(
                      color: AppColors.neonYellow,
                      fontWeight: FontWeight.w800,
                      fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            prov.isDemoMode ? Icons.money_off : Icons.play_circle,
            color: AppColors.textMuted,
            size: 20,
          ),
          tooltip: prov.isDemoMode ? 'Quitter demo' : 'Mode demo',
          onPressed: prov.toggleDemo,
        ),
      ],
    );
  }

  // ─── Historique crashes ──────────────────────────────────
  Widget _buildCrashHistory(AviatorProvider prov) {
    final history = prov.crashHistory;
    return Container(
      height: 34,
      color: const Color(0xFF0A0A10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: history.length,
        itemBuilder: (_, i) {
          final r = history[i];
          final color = r.isEarly
              ? _kAviatorRed
              : r.isMid
                  ? _kAviatorOrange
                  : AppColors.neonGreen;
          return Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.20),
                  color.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 5),
              ],
            ),
            child: Center(
              child: Text(
                '${r.crashPoint.toStringAsFixed(2)}x',
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Zone de jeu centrale (fond casino + courbe + avion) ──
  Widget _buildGameCenter(AviatorProvider prov) {
    final progress = prov.phase == AviatorPhase.waiting
        ? 0.0
        : (log(1.0 + prov.multiplier.clamp(0.0, 9999)) / log(51))
            .clamp(0.0, 0.95);

    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (ctx, child) {
        final shake = prov.phase == AviatorPhase.crashed
            ? sin(_shakeAnim.value * pi) * 6
            : 0.0;
        return Transform.translate(
          offset: Offset(shake, 0),
          child: child,
        );
      },
      child: Stack(
        children: [
          // 1) Fond rayonnant casino
          const Positioned.fill(child: AviatorBackground()),

          // 2) Logo AVIATOR stylise (en filigrane dans le fond)
          const Center(
            child: IgnorePointer(
              child: _AviatorLogoWatermark(),
            ),
          ),

          // 3) Courbe multiplicateur
          Positioned.fill(
            child: CustomPaint(
              painter: MultiplierCurvePainter(
                progress: progress,
                multiplier: prov.multiplier,
                crashed: prov.phase == AviatorPhase.crashed,
                waiting: prov.phase == AviatorPhase.waiting,
              ),
            ),
          ),

          // 4) Avion rouge
          if (prov.phase != AviatorPhase.waiting)
            PlaneWidget(
              progress: progress,
              multiplier: prov.multiplier,
              crashed: prov.phase == AviatorPhase.crashed,
            ),

          // 5) Multiplicateur central
          Center(child: _buildMultiplierDisplay(prov)),

          // 6) Seeds (fair) en bas, apres crash
          if (prov.phase == AviatorPhase.crashed)
            Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: _buildProvablyFair(prov),
            ),
        ],
      ),
    );
  }

  Widget _buildMultiplierDisplay(AviatorProvider prov) {
    if (prov.phase == AviatorPhase.waiting) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PROCHAIN VOL',
              style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _kAviatorRed.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
            child: Text(
              '${prov.countdownSecs}s',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 60,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(
                        color: _kAviatorRed,
                        blurRadius: 24,
                        offset: Offset(0, 0)),
                  ]),
            ),
          ),
        ],
      );
    }

    if (prov.phase == AviatorPhase.crashed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _kAviatorRed.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kAviatorRed.withValues(alpha: 0.4)),
            ),
            child: const Text('FLEW AWAY',
                style: TextStyle(
                    color: _kAviatorRed,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3)),
          ),
          const SizedBox(height: 6),
          Text(
            '${prov.multiplier.toStringAsFixed(2)}x',
            style: TextStyle(
                color: _kAviatorRed,
                fontSize: 64,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                      color: _kAviatorRed.withValues(alpha: 0.7),
                      blurRadius: 24),
                  Shadow(
                      color: _kAviatorRed.withValues(alpha: 0.35),
                      blurRadius: 46),
                ]),
          ),
        ],
      );
    }

    return ScaleTransition(
      scale: _pulseAnim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${prov.multiplier.toStringAsFixed(2)}x',
            style: TextStyle(
              color: Colors.white,
              fontSize: 70,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: (prov.multiplier >= 10
                          ? AppColors.neonGreen
                          : _kAviatorRed)
                      .withValues(alpha: 0.6),
                  blurRadius: 28,
                ),
                Shadow(
                  color: (prov.multiplier >= 10
                          ? AppColors.neonGreen
                          : _kAviatorOrange)
                      .withValues(alpha: 0.3),
                  blurRadius: 50,
                ),
              ],
            ),
          ),
          if (prov.bet1.autoCashOut != null || prov.bet2.autoCashOut != null)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Auto: x${(prov.bet1.autoCashOut ?? prov.bet2.autoCashOut)!.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProvablyFair(AviatorProvider prov) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🔒 Provably Fair',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              _seedRow('Server', prov.serverSeed),
              _seedRow('Client', prov.clientSeed),
              _seedRow('Hash', prov.roundHash),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seedRow(String label, String value) {
    return Row(
      children: [
        Text('$label: ',
            style: const TextStyle(color: Colors.white60, fontSize: 9)),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white70, fontSize: 9, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  // ─── Panneau mises (bas) ─────────────────────────────────
  Widget _buildBetPanel(AviatorProvider prov) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A10),
        border: Border(
          top: BorderSide(color: _kAviatorOrange.withValues(alpha: 0.15)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Mise 1 + (optionnel) Mise 2 cote a cote
          if (prov.showBet2)
            Row(
              children: [
                Expanded(
                    child: BetSlot(
                  bet: prov.bet1,
                  provider: prov,
                  onCashOut: () => _onCashOut(prov, prov.bet1),
                )),
                const SizedBox(width: 6),
                Expanded(
                    child: BetSlot(
                  bet: prov.bet2,
                  provider: prov,
                  onCashOut: () => _onCashOut(prov, prov.bet2),
                )),
              ],
            )
          else
            BetSlot(
              bet: prov.bet1,
              provider: prov,
              onCashOut: () => _onCashOut(prov, prov.bet1),
            ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: prov.toggleBet2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    prov.showBet2
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline,
                    color: Colors.white54,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    prov.showBet2 ? 'Retirer 2eme mise' : '+ Ajouter 2eme mise',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Logo AVIATOR stylise (filigrane derriere la courbe) ──
class _AviatorLogoWatermark extends StatelessWidget {
  const _AviatorLogoWatermark();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.06,
      child: Text(
        'AVIATOR',
        style: TextStyle(
          fontSize: 72,
          fontWeight: FontWeight.w900,
          letterSpacing: 8,
          color: _kAviatorRed,
          shadows: [
            Shadow(
              color: _kAviatorRed.withValues(alpha: 0.4),
              blurRadius: 24,
            ),
          ],
        ),
      ),
    );
  }
}

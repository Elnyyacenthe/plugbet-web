// ============================================================
// AVIATOR - Ecran de jeu principal (style casino multijoueur)
// Layout :
//   • Wide (>=900px) : panneau gauche (live bets) + centre (jeu) + panneau droit (gains)
//   • Mobile : panneaux en sheets repliables, centre plein ecran
//   • Bas : historique crashes + 1/2 panneaux de mise
// ============================================================

import 'dart:math';
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

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onPhaseCrashed() {
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
  }

  void _onCashOut(AviatorProvider prov, AviatorBet bet) {
    HapticFeedback.mediumImpact();
    prov.cashOut(bet);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Consumer<AviatorProvider>(
      builder: (ctx, prov, _) {
        if (prov.phase == AviatorPhase.crashed &&
            _shakeCtrl.status == AnimationStatus.dismissed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _onPhaseCrashed());
        }

        return Scaffold(
          backgroundColor: const Color(0xFF050508),
          appBar: _buildAppBar(prov, wallet),
          body: LayoutBuilder(
            builder: (ctx, constraints) {
              final wide = constraints.maxWidth >= 900;
              if (wide) return _buildWideLayout(prov);
              return _buildMobileLayout(prov);
            },
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
                  Container(
                    width: MediaQuery.of(context).size.width - 240,
                    color: Colors.black.withValues(alpha: 0.55),
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
                  Container(
                    width: MediaQuery.of(context).size.width - 200,
                    color: Colors.black.withValues(alpha: 0.55),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2015),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups,
                        color: Colors.white70, size: 14),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2015),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.neonGreen.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bolt,
                        color: AppColors.neonGreen, size: 14),
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
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          const Text('✈ ',
              style: TextStyle(fontSize: 18, color: Color(0xFFEF4444))),
          const Text(
            'AVIATOR',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 16,
            ),
          ),
          if (prov.isDemoMode) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.neonBlue.withValues(alpha: 0.5)),
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
          child: Row(
            children: [
              Icon(Icons.monetization_on,
                  color: AppColors.neonYellow, size: 16),
              const SizedBox(width: 4),
              Text(
                prov.isDemoMode ? '∞' : '${wallet.coins}',
                style: TextStyle(
                    color: AppColors.neonYellow,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ],
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
      height: 32,
      color: const Color(0xFF0A0A10),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: history.length,
        itemBuilder: (_, i) {
          final r = history[i];
          final color = r.isEarly
              ? const Color(0xFFEF4444)
              : r.isMid
                  ? const Color(0xFFF97316)
                  : AppColors.neonGreen;
          return Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color.withValues(alpha: 0.4)),
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
          const SizedBox(height: 8),
          Text(
            '${prov.countdownSecs}s',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 60,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                      color: Color(0xFFEF4444),
                      blurRadius: 20,
                      offset: Offset(0, 0)),
                ]),
          ),
        ],
      );
    }

    if (prov.phase == AviatorPhase.crashed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('FLEW AWAY',
              style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3)),
          const SizedBox(height: 4),
          Text(
            '${prov.multiplier.toStringAsFixed(2)}x',
            style: TextStyle(
                color: const Color(0xFFEF4444),
                fontSize: 64,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.7),
                      blurRadius: 24),
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
                          : const Color(0xFFEF4444))
                      .withValues(alpha: 0.6),
                  blurRadius: 28,
                ),
              ],
            ),
          ),
          if (prov.bet1.autoCashOut != null || prov.bet2.autoCashOut != null)
            Text(
              'Auto: x${(prov.bet1.autoCashOut ?? prov.bet2.autoCashOut)!.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white54, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildProvablyFair(AviatorProvider prov) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                color: Colors.white70,
                fontSize: 9,
                fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  // ─── Panneau mises (bas) ─────────────────────────────────
  Widget _buildBetPanel(AviatorProvider prov) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A10),
        border: Border(top: BorderSide(color: Color(0xFF1A1A22))),
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
          const SizedBox(height: 4),
          GestureDetector(
            onTap: prov.toggleBet2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
          color: const Color(0xFFEF4444),
          shadows: [
            Shadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.4),
              blurRadius: 24,
            ),
          ],
        ),
      ),
    );
  }
}

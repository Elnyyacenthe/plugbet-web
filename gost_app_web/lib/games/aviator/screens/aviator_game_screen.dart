// ============================================================
// AVIATOR – Écran de jeu principal
// Courbe multiplicateur + avion animé + 2 mises + chat
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/wallet_provider.dart';
import '../models/aviator_models.dart';
import '../providers/aviator_provider.dart';
import '../widgets/multiplier_curve_painter.dart';
import '../widgets/bet_slot.dart';
import '../widgets/plane_widget.dart';

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
  // Animation du multiplicateur (texte pulse)
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Animation crash (shake)
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

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
        // Détecter crash pour animation
        if (prov.phase == AviatorPhase.crashed &&
            _shakeCtrl.status == AnimationStatus.dismissed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _onPhaseCrashed());
        }

        return Scaffold(
          backgroundColor: const Color(0xFF090912),
          appBar: _buildAppBar(prov, wallet),
          body: Column(
            children: [
              // ── Historique crashes ──────────────────────
              _buildCrashHistory(prov),

              // ── Zone de jeu principale ──────────────────
              Expanded(child: _buildGameArea(prov)),

              // ── Panneau mises ───────────────────────────
              _buildBetPanel(prov),
            ],
          ),
        );
      },
    );
  }

  // ─── AppBar ──────────────────────────────────────────────
  AppBar _buildAppBar(AviatorProvider prov, WalletProvider wallet) {
    return AppBar(
      backgroundColor: const Color(0xFF0D0D1A),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Text('✈ ', style: TextStyle(fontSize: 16)),
          Text('Aviator',
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
          if (prov.isDemoMode) ...[
            SizedBox(width: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.5)),
              ),
              child: Text(AppLocalizations.of(context)!.gameDemo,
                  style: TextStyle(
                      color: AppColors.neonBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
      actions: [
        // Solde coins
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Icon(Icons.monetization_on,
                  color: AppColors.neonYellow, size: 16),
              SizedBox(width: 4),
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
        // Toggle demo
        IconButton(
          icon: Icon(
            prov.isDemoMode ? Icons.money_off : Icons.play_circle,
            color: AppColors.textMuted,
            size: 20,
          ),
          tooltip: prov.isDemoMode ? 'Quitter démo' : 'Mode démo',
          onPressed: prov.toggleDemo,
        ),
      ],
    );
  }

  // ─── Historique crashes ──────────────────────────────────
  Widget _buildCrashHistory(AviatorProvider prov) {
    final history = prov.crashHistory;
    return Container(
      height: 36,
      color: const Color(0xFF0D0D1A),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: history.length,
        itemBuilder: (_, i) {
          final r = history[i];
          final color = r.isEarly
              ? const Color(0xFFEF4444)
              : r.isMid
                  ? AppColors.neonOrange
                  : AppColors.neonGreen;
          return Container(
            margin: EdgeInsets.only(right: 6),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              'x${r.crashPoint.toStringAsFixed(2)}',
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          );
        },
      ),
    );
  }

  // ─── Zone de jeu ─────────────────────────────────────────
  Widget _buildGameArea(AviatorProvider prov) {
    // Progress de la courbe : log scale depuis 0
    // mult=0 → 0.0 | mult=1 → 0.14 | mult=5 → 0.41 | mult=50 → 0.95
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
          // Fond étoilé
          const StarField(),

          // Courbe multiplicateur
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

          // ── Avion ──────────────────────────────────────
          if (prov.phase != AviatorPhase.waiting)
            PlaneWidget(
              progress: progress,
              multiplier: prov.multiplier,
              crashed: prov.phase == AviatorPhase.crashed,
            ),

          // ── Multiplicateur central ─────────────────────
          Center(
            child: _buildMultiplierDisplay(prov),
          ),

          // ── Seeds provably fair (après crash) ──────────
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
          Text(AppLocalizations.of(context)!.gameNextFlight,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  letterSpacing: 1)),
          SizedBox(height: 6),
          Text(
            '${prov.countdownSecs}s',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 52,
                fontWeight: FontWeight.w900),
          ),
        ],
      );
    }

    if (prov.phase == AviatorPhase.crashed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(AppLocalizations.of(context)!.gameCrashed,
              style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
          SizedBox(height: 4),
          Text(
            'x${prov.multiplier.toStringAsFixed(2)}',
            style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 56,
                fontWeight: FontWeight.w900),
          ),
        ],
      );
    }

    // Phase flying
    return ScaleTransition(
      scale: _pulseAnim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'x${prov.multiplier.toStringAsFixed(2)}',
            style: TextStyle(
              color: prov.multiplier >= 10
                  ? AppColors.neonGreen
                  : const Color(0xFFF97316),
              fontSize: 58,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: (prov.multiplier >= 10
                          ? AppColors.neonGreen
                          : const Color(0xFFF97316))
                      .withValues(alpha: 0.5),
                  blurRadius: 20,
                ),
              ],
            ),
          ),
          if (prov.bet1.autoCashOut != null || prov.bet2.autoCashOut != null)
            Text(
              'Auto: x${(prov.bet1.autoCashOut ?? prov.bet2.autoCashOut)!.toStringAsFixed(2)}',
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildProvablyFair(AviatorProvider prov) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔒 Provably Fair',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
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
            style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 9,
                fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  // ─── Panneau mises ───────────────────────────────────────
  Widget _buildBetPanel(AviatorProvider prov) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border(
            top: BorderSide(
                color: AppColors.divider.withValues(alpha: 0.3))),
      ),
      child: Column(
        children: [
          // Mise 1 (toujours visible)
          BetSlot(
            bet: prov.bet1,
            provider: prov,
            onCashOut: () => _onCashOut(prov, prov.bet1),
          ),

          // Mise 2 (optionnelle)
          if (prov.showBet2) ...[
            SizedBox(height: 8),
            BetSlot(
              bet: prov.bet2,
              provider: prov,
              onCashOut: () => _onCashOut(prov, prov.bet2),
            ),
          ],

          SizedBox(height: 8),

          // Bouton toggle 2ème mise
          GestureDetector(
            onTap: prov.toggleBet2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  prov.showBet2 ? Icons.remove_circle_outline : Icons.add_circle_outline,
                  color: AppColors.textMuted,
                  size: 14,
                ),
                SizedBox(width: 4),
                Text(
                  prov.showBet2 ? 'Retirer 2ème mise' : '+ Ajouter 2ème mise',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

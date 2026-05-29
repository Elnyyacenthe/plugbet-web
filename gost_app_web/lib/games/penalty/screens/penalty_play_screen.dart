// ============================================================
// PenaltyPlayScreen — déroulement des 5 tirs + écran résultat
// ============================================================
// UX simple (Phase 3c, sans animations) :
//   * 3 gros boutons G/C/D
//   * après chaque tir : overlay 1.5s "BUT" ou "ARRÊT" + direction
//     du gardien
//   * round fini : écran résultat (Victoire +2× / Défaite / Abandon)
//
// Le serveur reste autoritatif sur tout. Le PopScope confirme
// l'abandon (= mise perdue côté serveur).
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../../../widgets/network_lost_overlay.dart';
import '../models/penalty_models.dart';
import '../providers/penalty_provider.dart';
import 'penalty_bet_screen.dart';

class PenaltyPlayScreen extends StatefulWidget {
  const PenaltyPlayScreen({super.key});
  @override
  State<PenaltyPlayScreen> createState() => _PenaltyPlayScreenState();
}

class _PenaltyPlayScreenState extends State<PenaltyPlayScreen> {
  PenaltyShotResult? _lastShot;
  bool _showOverlay = false;
  Timer? _overlayTimer;

  @override
  void dispose() {
    _overlayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    return Consumer<PenaltyProvider>(
      builder: (_, prov, __) {
        final round = prov.round;
        // Si le provider est reset (Rejouer / Retour), on revient en arrière
        if (round == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }

        // Tant que l'overlay du DERNIER tir est affiché, on garde le layout
        // "active" même si le round vient de finir -> le joueur voit le résultat
        // de son tir avant le bilan global.
        final showResult =
            round.status != PenaltyRoundStatus.active && !_showOverlay;
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
            body: Container(
              decoration: BoxDecoration(gradient: AppColors.bgGradient),
              child: SafeArea(
                child: showResult
                    ? _buildResult(prov, round)
                    : _buildActiveRound(prov, round),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Round actif ────────────────────────────────────────────
  Widget _buildActiveRound(PenaltyProvider prov, PenaltyRound round) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _scoreRow(round),
          const SizedBox(height: 18),
          Expanded(child: _goalFrame()),
          const SizedBox(height: 14),
          if (_showOverlay && _lastShot != null) ...[
            _shotResultBanner(_lastShot!),
            const SizedBox(height: 14),
          ],
          _dirButtons(prov),
        ],
      ),
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
      Icon(icon, color: c, size: 18),
      const SizedBox(height: 4),
      Text('$value',
          style: TextStyle(
              color: c, fontSize: 22, fontWeight: FontWeight.w900)),
      Text(label,
          style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _goalFrame() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.4), width: 2),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer_rounded,
                size: 80, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('Choisis ta direction',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Le gardien plonge en même temps',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _shotResultBanner(PenaltyShotResult res) {
    final isGoal = res.isGoal;
    final color = isGoal ? AppColors.neonGreen : AppColors.neonRed;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isGoal ? Icons.sports_soccer_rounded : Icons.shield_rounded,
              color: color, size: 24),
          const SizedBox(width: 10),
          Text(isGoal ? 'BUT !' : 'ARRÊT !',
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1)),
          const SizedBox(width: 12),
          Text('Gardien : ${_dirLabel(res.serverDirection)}',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _dirLabel(PenaltyDirection d) {
    switch (d) {
      case PenaltyDirection.left:   return 'gauche';
      case PenaltyDirection.center: return 'centre';
      case PenaltyDirection.right:  return 'droite';
    }
  }

  Widget _dirButtons(PenaltyProvider prov) {
    final disabled = prov.isShooting || _showOverlay;
    return Row(children: [
      Expanded(child: _dirBtn('GAUCHE', Icons.arrow_back_rounded,
          PenaltyDirection.left, disabled)),
      const SizedBox(width: 10),
      Expanded(child: _dirBtn('CENTRE', Icons.arrow_upward_rounded,
          PenaltyDirection.center, disabled)),
      const SizedBox(width: 10),
      Expanded(child: _dirBtn('DROITE', Icons.arrow_forward_rounded,
          PenaltyDirection.right, disabled)),
    ]);
  }

  Widget _dirBtn(String label, IconData icon, PenaltyDirection d, bool disabled) {
    final accent = AppColors.neonGreen;
    return SizedBox(
      height: 84,
      child: ElevatedButton(
        onPressed: disabled ? null : () => _onTakeShot(d),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.bgElevated,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor:
              AppColors.bgElevated.withValues(alpha: 0.5),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color: accent.withValues(alpha: disabled ? 0.2 : 0.55),
                width: 1.5),
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              size: 24,
              color: disabled ? AppColors.textMuted : accent),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8)),
        ]),
      ),
    );
  }

  Future<void> _onTakeShot(PenaltyDirection dir) async {
    final prov = context.read<PenaltyProvider>();
    final wallet = context.read<WalletProvider>();
    final res = await prov.takeShot(dir);
    if (!mounted || res == null) return;
    setState(() {
      _lastShot = res;
      _showOverlay = true;
    });
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _showOverlay = false);
    });
    if (res.roundFinished) {
      try { await wallet.refresh(); } catch (_) {}
    }
  }

  // ── Écran résultat ─────────────────────────────────────────
  Widget _buildResult(PenaltyProvider prov, PenaltyRound round) {
    final isWin = round.status == PenaltyRoundStatus.won;
    final isLost = round.status == PenaltyRoundStatus.lost;
    final isAbandoned = round.status == PenaltyRoundStatus.abandoned;
    final payout = isWin ? round.betAmount * 2 : 0;

    return Padding(
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
              Navigator.of(context).pop(); // back vers le tab Jeux
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

  // ── Confirm abandon ────────────────────────────────────────
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

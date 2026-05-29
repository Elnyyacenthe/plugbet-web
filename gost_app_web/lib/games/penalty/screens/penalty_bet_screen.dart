// ============================================================
// PenaltyBetScreen — choix de la mise puis lancement du round
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../../../widgets/network_lost_overlay.dart';
import '../providers/penalty_provider.dart';
import 'penalty_play_screen.dart';

class PenaltyBetScreen extends StatefulWidget {
  const PenaltyBetScreen({super.key});

  @override
  State<PenaltyBetScreen> createState() => _PenaltyBetScreenState();
}

class _PenaltyBetScreenState extends State<PenaltyBetScreen> {
  static const int _minBet = 10;
  static const int _maxBet = 1000;
  int _bet = 50;

  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final prov = context.watch<PenaltyProvider>();
    final hasFunds = wallet.coins >= _bet;
    final canPlay = !prov.isStarting && hasFunds;
    final potentialWin = _bet * 2;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: const Text('Penalty',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Icon(Icons.monetization_on,
                  color: AppColors.neonYellow, size: 18),
              const SizedBox(width: 4),
              Text('${wallet.coins}',
                  style: TextStyle(
                      color: AppColors.neonYellow,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ]),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text('Choisis ta mise',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                    '5 tirs au but. Si tu marques plus que tu rates → 2× ta mise.\n'
                    'Sinon tu perds ta mise.',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5)),
                const SizedBox(height: 24),
                _betCard(potentialWin),
                const SizedBox(height: 14),
                Slider(
                  value: _bet.toDouble(),
                  min: _minBet.toDouble(),
                  max: _maxBet.toDouble(),
                  divisions: (_maxBet - _minBet) ~/ 10,
                  activeColor: AppColors.neonGreen,
                  inactiveColor: AppColors.divider,
                  onChanged: prov.isStarting
                      ? null
                      : (v) =>
                          setState(() => _bet = (v / 10).round() * 10),
                ),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Min $_minBet',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                      Text('Max $_maxBet',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ]),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [10, 50, 100, 500, 1000]
                      .map(_presetChip)
                      .toList(),
                ),
                const Spacer(),
                if (prov.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.neonRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              AppColors.neonRed.withValues(alpha: 0.5)),
                    ),
                    child: Text(prov.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.neonRed,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: canPlay ? _onPlay : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonGreen,
                      foregroundColor: AppColors.bgDark,
                      disabledBackgroundColor: AppColors.bgElevated,
                      disabledForegroundColor: AppColors.textMuted,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: prov.isStarting
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.bgDark))
                        : Text(
                            !hasFunds
                                ? 'Solde insuffisant'
                                : 'Jouer ($_bet coins)',
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _betCard(int potentialWin) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        Text('MISE',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('$_bet coins',
            style: TextStyle(
                color: AppColors.neonYellow,
                fontSize: 32,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.emoji_events_rounded,
              size: 14, color: AppColors.neonGreen),
          const SizedBox(width: 4),
          Text('Victoire : +$potentialWin coins',
              style: TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Widget _presetChip(int v) {
    final active = _bet == v;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _bet = v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.neonGreen.withValues(alpha: 0.2)
              : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: (active ? AppColors.neonGreen : AppColors.divider)
                  .withValues(alpha: 0.6)),
        ),
        child: Text('$v',
            style: TextStyle(
                color: active ? AppColors.neonGreen : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800)),
      ),
    );
  }

  Future<void> _onPlay() async {
    final prov = context.read<PenaltyProvider>();
    final wallet = context.read<WalletProvider>();
    final navigator = Navigator.of(context);
    final ok = await prov.startRound(betAmount: _bet);
    if (!mounted) return;
    if (!ok) return; // l'erreur est affichée par prov.error
    try { await wallet.refresh(); } catch (_) {}
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const PenaltyPlayScreen()),
    );
  }
}

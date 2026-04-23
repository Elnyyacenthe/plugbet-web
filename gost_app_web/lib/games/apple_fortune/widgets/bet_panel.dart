// ============================================================
// Apple of Fortune – Bet panel (bottom)
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme.dart';


class BetPanel extends StatelessWidget {
  final int coins;
  final int betAmount;
  final bool isPlaying;
  final bool canCashOut;
  final int currentPotentialWin;
  final double currentMultiplier;
  final bool loading;
  final ValueChanged<int> onBetChanged;
  final VoidCallback onStart;
  final VoidCallback onCashOut;

  const BetPanel({
    super.key,
    required this.coins,
    required this.betAmount,
    required this.isPlaying,
    required this.canCashOut,
    required this.currentPotentialWin,
    required this.currentMultiplier,
    required this.loading,
    required this.onBetChanged,
    required this.onStart,
    required this.onCashOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1726), Color(0xFF040810)],
        ),
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: isPlaying ? _buildPlayingPanel() : _buildBetSetup(context),
    );
  }

  Widget _buildBetSetup(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bet amount row
        Row(
          children: [
            // Quick bet buttons
            _quickBet(50),
            const SizedBox(width: 6),
            _quickBet(100),
            const SizedBox(width: 6),
            _quickBet(200),
            const SizedBox(width: 6),
            _quickBet(500),
            const SizedBox(width: 10),

            // Current bet display
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.monetization_on,
                        color: AppColors.neonYellow, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '$betAmount',
                      style: TextStyle(
                        color: AppColors.neonYellow,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Start button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: loading || betAmount > coins || betAmount <= 0
                ? null
                : onStart,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: Colors.black,
              disabledBackgroundColor: AppColors.textMuted.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                : Text(
                    betAmount > coins
                        ? 'Solde insuffisant'
                        : 'COMMENCER',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayingPanel() {
    return Row(
      children: [
        // Current win info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gain actuel',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.monetization_on,
                      color: AppColors.neonYellow, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '$currentPotentialWin',
                    style: TextStyle(
                      color: AppColors.neonYellow,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'x${currentMultiplier.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: AppColors.neonGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Cash out button
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: canCashOut && !loading ? onCashOut : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD600),
              foregroundColor: Colors.black,
              disabledBackgroundColor: AppColors.textMuted.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              elevation: 0,
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.black,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'CASH OUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '$currentPotentialWin FCFA',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _quickBet(int amount) {
    final isSelected = betAmount == amount;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onBetChanged(amount);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? AppColors.neonYellow.withValues(alpha: 0.15)
              : AppColors.bgCard,
          border: Border.all(
            color: isSelected
                ? AppColors.neonYellow.withValues(alpha: 0.5)
                : AppColors.divider,
          ),
        ),
        child: Text(
          '$amount',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.neonYellow : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

}

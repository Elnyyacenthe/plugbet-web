// ============================================================
// LUDO V2 — Result Screen
// ============================================================

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../models/ludo_models.dart';

class LudoV2ResultScreen extends StatelessWidget {
  final LudoV2Game game;
  final String myId;

  const LudoV2ResultScreen({
    super.key,
    required this.game,
    required this.myId,
  });

  @override
  Widget build(BuildContext context) {
    final isWinner = game.winnerId == myId;
    final pot = game.betAmount * game.turnOrder.length;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icône
                  Icon(
                    isWinner ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                    size: 80,
                    color: isWinner ? AppColors.neonYellow : AppColors.neonRed,
                  ),
                  SizedBox(height: 24),

                  // Titre
                  Text(
                    isWinner ? 'VICTOIRE !' : 'DÉFAITE',
                    style: TextStyle(
                      color: isWinner ? AppColors.neonGreen : AppColors.neonRed,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  SizedBox(height: 12),

                  // Gains
                  if (pot > 0)
                    Text(
                      isWinner ? '+$pot coins' : '-${game.betAmount} coins',
                      style: TextStyle(
                        color: isWinner ? AppColors.neonGreen : AppColors.neonRed,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  SizedBox(height: 32),

                  // Stats
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.cardGradient,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        _statRow('Tours joués', '${game.turnNumber}'),
                        SizedBox(height: 8),
                        _statRow('Joueurs', '${game.turnOrder.length}'),
                        if (pot > 0) ...[
                          SizedBox(height: 8),
                          _statRow('Pot total', '$pot coins'),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 32),

                  // Bouton retour
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonGreen,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'RETOUR AU MENU',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        Text(value, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}

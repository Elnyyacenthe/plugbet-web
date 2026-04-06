// ============================================================
// Plugbet – Écran des jeux
// Ludo, Cora Dice, Checkers (Dames), Solitaire
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/wallet_provider.dart';
import '../ludo_v2/screens/ludo_menu_screen.dart';
import '../games/cora_dice/screens/cora_dice_screen.dart';
import '../games/checkers/screens/checkers_screen.dart';
import '../games/solitaire/screens/solitaire_screen.dart';
import '../games/aviator/screens/aviator_screen.dart';
import '../games/blackjack/screens/blackjack_screen.dart';
import '../games/roulette/screens/roulette_screen.dart';
import '../games/coinflip/screens/coinflip_screen.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(
          'Jeux',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 18),
                SizedBox(width: 4),
                Text(
                  '${wallet.coins}',
                  style: TextStyle(
                    color: AppColors.neonYellow,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Section multijoueur
            _sectionLabel('Multijoueur'),
            SizedBox(height: 10),
            _gameCard(
              context,
              'Ludo',
              'Jeu de plateau classique • 2-4 joueurs',
              Icons.grid_4x4,
              AppColors.neonBlue,
              '2-4',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LudoV2MenuScreen())),
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Cora Dice',
              'Jeu de dés camerounais • 2-6 joueurs • Virtual Coins',
              Icons.casino,
              AppColors.neonGreen,
              '2-6',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CoraDiceScreen())),
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Dames (Checkers)',
              'Plateau 8×8 • Kings • Sauts obligatoires • 200 coins',
              Icons.grid_on,
              AppColors.neonOrange,
              '1v1',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CheckersScreen())),
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Aviator',
              'Crash multiplier • Misez & cashouté avant le crash • Coins',
              Icons.flight,
              const Color(0xFFF97316),
              '1-2 mises',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AviatorScreen())),
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Blackjack',
              '2-4 joueurs vs Dealer • Hit ou Stand • Coins',
              Icons.style,
              const Color(0xFF2E7D32),
              '2-4 joueurs',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BlackjackScreen())),
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Roulette',
              'Multi joueurs • Rouge/Noir/Numéro • Coins',
              Icons.circle,
              const Color(0xFFB71C1C),
              '2-6 joueurs',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RouletteScreen())),
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Pile ou Face',
              'Duel 1v1 • Choisis ton côté • Le gagnant prend tout',
              Icons.monetization_on,
              const Color(0xFFFFD700),
              'Duel',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CoinflipScreen())),
            ),
            SizedBox(height: 20),

            // Section solo
            _sectionLabel('Solo'),
            SizedBox(height: 10),
            _gameCard(
              context,
              'Solitaire',
              'Klondike classique • Fondations par couleur • 200 coins',
              Icons.style,
              const Color(0xFF9C27B0),
              '1P',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SolitaireScreen())),
            ),
            SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: EdgeInsets.only(left: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _gameCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    String players,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(players,
                            style: TextStyle(
                                color: color,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: AppColors.textMuted, size: 16),
          ],
        ),
      ),
    );
  }
}

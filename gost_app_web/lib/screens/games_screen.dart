// ============================================================
// Plugbet – Écran des jeux
// Ludo, Cora Dice, Checkers (Dames), Solitaire
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/wallet_provider.dart';
import '../ludo_v2/screens/ludo_menu_screen.dart';
import '../games/cora_dice/screens/cora_dice_screen.dart';
import '../games/checkers/screens/checkers_screen.dart';
import '../games/solitaire/screens/solitaire_screen.dart';
import '../games/aviator/screens/aviator_screen.dart';
import '../games/blackjack/screens/blackjack_screen.dart';
import '../games/roulette/screens/roulette_screen.dart';
import '../games/coinflip/screens/coinflip_screen.dart';
import '../games/apple_fortune/screens/apple_fortune_screen.dart';
import '../games/mines/screens/mines_screen.dart';
import '../widgets/game_rules_dialog.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(
          t.tabGames,
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
              'assets/games/ludo.png',
              AppColors.neonBlue,
              '2-4',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LudoV2MenuScreen())),
              fallbackWidget: const _LudoBoardIcon(size: 44),
              rules: GameRulesLibrary.ludo,
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Cora Dice',
              'Jeu de dés camerounais • 2-6 joueurs • Virtual Coins',
              'assets/games/cora_dice.png',
              AppColors.neonGreen,
              '2-6',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CoraDiceScreen())),
              fallbackEmoji: '🎲',
              rules: GameRulesLibrary.coraDice,
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Dames (Checkers)',
              'Plateau 8×8 • Kings • Sauts obligatoires • 200 coins',
              'assets/games/checkers.png',
              AppColors.neonOrange,
              '1v1',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CheckersScreen())),
              fallbackEmoji: '♟️',
              rules: GameRulesLibrary.checkers,
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Aviator',
              'Crash multiplier • Misez & cashouté avant le crash • Coins',
              'assets/games/aviator.png',
              const Color(0xFFF97316),
              '1-2 mises',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AviatorScreen())),
              fallbackEmoji: '✈️',
              rules: GameRulesLibrary.aviator,
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Blackjack',
              '2-4 joueurs vs Dealer • Hit ou Stand • Coins',
              'assets/games/blackjack.png',
              const Color(0xFF2E7D32),
              '2-4 joueurs',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BlackjackScreen())),
              fallbackEmoji: '🃏',
              rules: GameRulesLibrary.blackjack,
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Roulette',
              'Multi joueurs • Rouge/Noir/Numéro • Coins',
              'assets/games/roulette.png',
              const Color(0xFFB71C1C),
              '2-6 joueurs',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RouletteScreen())),
              fallbackEmoji: '🎡',
              rules: GameRulesLibrary.roulette,
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Apple of Fortune',
              'Grimpez la pyramide • Multiplicateurs • Cash Out',
              'assets/games/apple_fortune.png',
              const Color(0xFF4CAF50),
              'Solo',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AppleFortuneScreen())),
              fallbackEmoji: '🍎',
              rules: GameRulesLibrary.appleFortune,
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Mines',
              'Revelez les diamants, evitez les bombes • Solo',
              'assets/games/mines.png',
              const Color(0xFFE53935),
              'Solo',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MinesScreen())),
              fallbackEmoji: '💣',
              rules: GameRulesLibrary.mines,
            ),
            SizedBox(height: 12),
            _gameCard(
              context,
              'Pile ou Face',
              'Duel 1v1 • Choisis ton côté • Le gagnant prend tout',
              'assets/games/coinflip.png',
              const Color(0xFFFFD700),
              'Duel',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CoinflipScreen())),
              fallbackEmoji: '🪙',
              rules: GameRulesLibrary.coinflip,
            ),
            SizedBox(height: 20),

            // Section solo
            _sectionLabel('Solo'),
            SizedBox(height: 10),
            _gameCard(
              context,
              'Solitaire',
              'Klondike classique • Fondations par couleur • 200 coins',
              'assets/games/solitaire.png',
              const Color(0xFF9C27B0),
              '1P',
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SolitaireScreen())),
              fallbackEmoji: '♠️',
              rules: GameRulesLibrary.solitaire,
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
    String imageAsset, // chemin asset PNG/JPG
    Color color,
    String players,
    VoidCallback onTap, {
    String fallbackEmoji = '🎮',
    Widget? fallbackWidget, // prioritaire sur fallbackEmoji si fourni
    GameRules? rules, // si fourni, affiche un bouton ? pour voir les regles
  }) {
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
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.28),
                    color.withValues(alpha: 0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: color.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.asset(
                  imageAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallbackWidget != null
                      ? Center(child: fallbackWidget)
                      : Center(
                          child: Text(
                            fallbackEmoji,
                            style: const TextStyle(fontSize: 32),
                          ),
                        ),
                ),
              ),
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
            // Bouton regles (si defini) — tap = ouvre le dialog
            if (rules != null)
              GestureDetector(
                onTap: () => GameRulesDialog.show(context, rules),
                child: Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                    border: Border.all(
                      color: color.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.help_outline_rounded,
                    color: color,
                    size: 18,
                  ),
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

// ============================================================
// _LudoBoardIcon — Mini plateau Ludo dessine en CustomPaint
// 4 quadrants colores (rouge/vert/jaune/bleu) + croix + centre
// ============================================================
class _LudoBoardIcon extends StatelessWidget {
  final double size;
  const _LudoBoardIcon({this.size = 44});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LudoBoardPainter()),
    );
  }
}

class _LudoBoardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final half = w / 2;
    final third = w / 3;

    // Rayon coin des quadrants
    final radius = Radius.circular(w * 0.08);

    // 4 quadrants colores (home bases)
    final red = Paint()..color = const Color(0xFFE53935);
    final green = Paint()..color = const Color(0xFF43A047);
    final yellow = Paint()..color = const Color(0xFFFDD835);
    final blue = Paint()..color = const Color(0xFF1E88E5);

    // Top-left : rouge
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, 0, third, third),
        topLeft: radius,
      ),
      red,
    );
    // Top-right : vert
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w - third, 0, third, third),
        topRight: radius,
      ),
      green,
    );
    // Bottom-left : bleu
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, h - third, third, third),
        bottomLeft: radius,
      ),
      blue,
    );
    // Bottom-right : jaune
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(w - third, h - third, third, third),
        bottomRight: radius,
      ),
      yellow,
    );

    // Croix centrale (chemin)
    final white = Paint()..color = Colors.white;
    // Bande verticale
    canvas.drawRect(
      Rect.fromLTWH(third, 0, third, h),
      white,
    );
    // Bande horizontale
    canvas.drawRect(
      Rect.fromLTWH(0, third, w, third),
      white,
    );

    // Centre : losange multicolore
    final center = Offset(half, half);
    final centerSize = w * 0.14;
    final path1 = Path()
      ..moveTo(center.dx, center.dy - centerSize)
      ..lineTo(center.dx + centerSize, center.dy)
      ..lineTo(center.dx, center.dy)
      ..close();
    final path2 = Path()
      ..moveTo(center.dx + centerSize, center.dy)
      ..lineTo(center.dx, center.dy + centerSize)
      ..lineTo(center.dx, center.dy)
      ..close();
    final path3 = Path()
      ..moveTo(center.dx, center.dy + centerSize)
      ..lineTo(center.dx - centerSize, center.dy)
      ..lineTo(center.dx, center.dy)
      ..close();
    final path4 = Path()
      ..moveTo(center.dx - centerSize, center.dy)
      ..lineTo(center.dx, center.dy - centerSize)
      ..lineTo(center.dx, center.dy)
      ..close();
    canvas.drawPath(path1, green);
    canvas.drawPath(path2, yellow);
    canvas.drawPath(path3, blue);
    canvas.drawPath(path4, red);

    // Bordure noire legere autour
    final border = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        Radius.circular(w * 0.08),
      ),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

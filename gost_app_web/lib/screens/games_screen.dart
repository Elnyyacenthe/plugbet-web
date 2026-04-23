// ============================================================
// Plugbet – Écran des jeux
// Fantasy en featured + grille 2 colonnes + leaderboard
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/wallet_provider.dart';
import '../fantasy/screens/fantasy_home_screen.dart';
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
import '../widgets/players_leaderboard.dart';

class _Game {
  final String title;
  final String subtitle;
  final IconData icon;
  final String imageAsset;
  final Color color;
  final Widget Function(BuildContext) builder;
  final GameRules? rules;
  const _Game({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.imageAsset,
    required this.color,
    required this.builder,
    this.rules,
  });
}

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final t = AppLocalizations.of(context)!;

    final games = <_Game>[
      _Game(
        title: 'Ludo',
        subtitle: 'Plateau classique • 2-4 joueurs',
        icon: Icons.dashboard_rounded,
        imageAsset: 'assets/games/ludo.png',
        color: AppColors.neonBlue,
        builder: (_) => const LudoV2MenuScreen(),
        rules: GameRulesLibrary.ludo,
      ),
      _Game(
        title: 'Cora Dice',
        subtitle: 'Jeu de dés camerounais',
        icon: Icons.casino_rounded,
        imageAsset: 'assets/games/cora_dice.jpg',
        color: AppColors.neonGreen,
        builder: (_) => const CoraDiceScreen(),
        rules: GameRulesLibrary.coraDice,
      ),
      _Game(
        title: 'Dames',
        subtitle: 'Plateau 8×8 • 1v1',
        icon: Icons.grid_4x4_rounded,
        imageAsset: 'assets/games/dames.jpg',
        color: AppColors.neonOrange,
        builder: (_) => const CheckersScreen(),
        rules: GameRulesLibrary.checkers,
      ),
      _Game(
        title: 'Aviator',
        subtitle: 'Crash multiplier',
        icon: Icons.flight_takeoff_rounded,
        imageAsset: 'assets/games/aviator.png',
        color: const Color(0xFFF97316),
        builder: (_) => const AviatorScreen(),
        rules: GameRulesLibrary.aviator,
      ),
      _Game(
        title: 'Blackjack',
        subtitle: '2-4 joueurs vs Dealer',
        icon: Icons.style_rounded,
        imageAsset: 'assets/games/blackjack.jpg',
        color: const Color(0xFF2E7D32),
        builder: (_) => const BlackjackScreen(),
        rules: GameRulesLibrary.blackjack,
      ),
      _Game(
        title: 'Roulette',
        subtitle: 'Multi joueurs • Rouge/Noir',
        icon: Icons.donut_large_rounded,
        imageAsset: 'assets/games/roulette.jpg',
        color: const Color(0xFFB71C1C),
        builder: (_) => const RouletteScreen(),
        rules: GameRulesLibrary.roulette,
      ),
      _Game(
        title: 'Apple Fortune',
        subtitle: 'Pyramide multiplicateurs',
        icon: Icons.change_history_rounded,
        imageAsset: 'assets/games/apple_fortune.png',
        color: const Color(0xFF4CAF50),
        builder: (_) => const AppleFortuneScreen(),
        rules: GameRulesLibrary.appleFortune,
      ),
      _Game(
        title: 'Mines',
        subtitle: 'Diamants vs bombes',
        icon: Icons.diamond_rounded,
        imageAsset: 'assets/games/mines.png',
        color: const Color(0xFFE53935),
        builder: (_) => const MinesScreen(),
        rules: GameRulesLibrary.mines,
      ),
      _Game(
        title: 'Pile ou Face',
        subtitle: 'Duel 1v1',
        icon: Icons.monetization_on_rounded,
        imageAsset: 'assets/games/coinflip.png',
        color: const Color(0xFFFFD700),
        builder: (_) => const CoinflipScreen(),
        rules: GameRulesLibrary.coinflip,
      ),
      _Game(
        title: 'Solitaire',
        subtitle: 'Klondike • Solo',
        icon: Icons.layers_rounded,
        imageAsset: 'assets/games/solitaire.png',
        color: const Color(0xFF9C27B0),
        builder: (_) => const SolitaireScreen(),
        rules: GameRulesLibrary.solitaire,
      ),
    ];

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
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 18),
                const SizedBox(width: 4),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // ───── JEU PRINCIPAL : Fantasy Premier League ─────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _featuredCard(context),
            ),

            // ───── Section autres jeux ─────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    'TOUS LES JEUX',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${games.length}',
                      style: TextStyle(
                        color: AppColors.neonGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ───── Grille 2 colonnes ─────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.88,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: games.length,
                itemBuilder: (context, i) => _gameTile(context, games[i]),
              ),
            ),

            const SizedBox(height: 16),

            // ───── Top joueurs avec chat ─────
            const PlayersLeaderboard(),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // FEATURED CARD : Fantasy Premier League
  // ────────────────────────────────────────────────────────────
  Widget _featuredCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FantasyHomeScreen()),
      ),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF38003C).withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
          children: [
            // Fond image Fantasy (avec fallback gradient si manquante)
            Positioned.fill(
              child: Image.asset(
                'assets/games/fantasy.jpg',
                fit: BoxFit.cover,
                cacheWidth: 800,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF38003C),
                        const Color(0xFF00FF87),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Overlay sombre pour lisibilite du texte
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.15),
                    ],
                  ),
                ),
              ),
            ),

            // Contenu
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'PRINCIPAL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('⚽', style: TextStyle(fontSize: 24)),
                          const SizedBox(width: 8),
                          Text(
                            'Fantasy Premier League',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Construis ton équipe • Affronte tes amis',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // GAME TILE : carte plein-cadre, fond gradient intense,
  // icone geante en watermark + overlay sombre pour le texte
  // ────────────────────────────────────────────────────────────
  Widget _gameTile(BuildContext context, _Game g) {
    final darkEnd = Color.lerp(g.color, Colors.black, 0.75)!;
    return GestureDetector(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: g.builder)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: g.color.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // FOND : image si elle existe, sinon gradient de couleur
              // cacheWidth limite le decodage en RAM (sinon full resolution)
              Positioned.fill(
                child: Image.asset(
                  g.imageAsset,
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (_, __, ___) {
                    // Fallback : gradient + icone si image pas encore ajoutee
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [g.color, darkEnd],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          g.icon,
                          size: 80,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Overlay sombre en bas pour lisibilite du texte
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 72,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),

              // Bouton regles (coin haut droit)
              if (g.rules != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => GameRulesDialog.show(context, g.rules!),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                      child: const Icon(
                        Icons.help_outline_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),

              // Texte en bas
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      g.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      g.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

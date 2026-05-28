// ============================================================
// GamesHomePage — hub d'accueil des jeux WebView (pay-to-play)
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../../../widgets/network_lost_overlay.dart';
import '../constants/games_constants.dart';
import '../models/game_model.dart';
import '../providers/games_hub_provider.dart';
import '../widgets/category_filter.dart';
import '../widgets/game_card.dart';
import 'game_play_page.dart';

class GamesHomePage extends StatelessWidget {
  const GamesHomePage({super.key});

  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        centerTitle: true,
        title: const Text('Jeux',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Consumer<GamesHubProvider>(
        builder: (_, prov, __) {
          final games = prov.filtered;
          return Column(
            children: [
              const SizedBox(height: 10),
              CategoryFilter(
                available: prov.availableCategories,
                selected: prov.selectedCategory,
                onChanged: prov.selectCategory,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: games.isEmpty
                    ? _empty()
                    : LayoutBuilder(
                        builder: (ctx, c) {
                          final cols = (c.maxWidth / kGameCardMinWidth)
                              .floor()
                              .clamp(2, 6);
                          return GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: kGameCardAspectRatio,
                            ),
                            itemCount: games.length,
                            itemBuilder: (_, i) => GameCard(
                              game: games[i],
                              onTap: () => _onPickGame(context, games[i]),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Aucun jeu dans cette catégorie pour l\'instant.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ),
      );

  Future<void> _onPickGame(BuildContext context, GameModel game) async {
    final wallet = context.read<WalletProvider>();
    final prov = context.read<GamesHubProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Pré-check solde local
    if (game.entryPriceCoins > 0 && wallet.coins < game.entryPriceCoins) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.neonRed,
          content: Text('Solde insuffisant (${game.entryPriceCoins} coins requis)'),
        ),
      );
      return;
    }

    final confirmed = await _confirmPay(context, game);
    if (confirmed != true) return;

    final ok = await prov.startSession(game);
    if (!context.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.neonRed,
          content: const Text('Impossible de démarrer la session'),
        ),
      );
      return;
    }

    // Refresh wallet + push page de jeu
    try { await wallet.refresh(); } catch (_) {}
    if (!context.mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => const GamePlayPage()),
    );
  }

  Future<bool?> _confirmPay(BuildContext context, GameModel game) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(game.title,
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          game.entryPriceCoins == 0
              ? 'Session gratuite de ${game.sessionDurationMinutes} min. Lancer ?'
              : 'Payer ${game.entryPriceCoins} coins pour ${game.sessionDurationMinutes} min de jeu ?\n\nLa mise n\'est pas remboursable.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: AppColors.bgDark,
            ),
            child: Text(game.entryPriceCoins == 0 ? 'Jouer' : 'Payer & jouer',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

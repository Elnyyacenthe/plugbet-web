// ============================================================
// GamesHomePage — hub d'accueil des jeux WebView (pay-to-play)
// ============================================================
// >>> DESIGN PREMIUM <<<
// Seul l'habillage visuel a ete retravaille (fond degrade profond,
// en-tete stylisee, dialogue de confirmation en glassmorphism). Toute
// la logique (provider, filtres, startSession, navigation, wallet...)
// est strictement identique a l'original.
// ============================================================

import 'dart:ui';
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.bgBlueNight, AppColors.bgDark],
            ),
            border: Border(
              bottom: BorderSide(
                color: AppColors.neonPurple.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_esports_rounded,
                color: AppColors.neonPurple, size: 22),
            const SizedBox(width: 8),
            const Text('Jeux',
                style: TextStyle(
                    fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Consumer<GamesHubProvider>(
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
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videogame_asset_off_rounded,
                  size: 48, color: AppColors.textMuted.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Text(
                'Aucun jeu dans cette catégorie pour l\'instant.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
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
          content:
              Text('Solde insuffisant (${game.entryPriceCoins} coins requis)'),
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
    try {
      await wallet.refresh();
    } catch (_) {}
    if (!context.mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => const GamePlayPage()),
    );
  }

  Future<bool?> _confirmPay(BuildContext context, GameModel game) {
    final free = game.entryPriceCoins == 0;
    final accent = free ? AppColors.neonGreen : AppColors.neonYellow;
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.bgCard.withValues(alpha: 0.96),
                    AppColors.bgBlueNight.withValues(alpha: 0.96),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: accent.withValues(alpha: 0.45),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.25),
                    blurRadius: 30,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.14),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.5), width: 1),
                    ),
                    child: Icon(
                        free
                            ? Icons.play_circle_fill_rounded
                            : Icons.paid_rounded,
                        color: accent,
                        size: 30),
                  ),
                  const SizedBox(height: 14),
                  Text(game.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Text(
                    free
                        ? 'Session gratuite de ${game.sessionDurationMinutes} min. Lancer ?'
                        : 'Payer ${game.entryPriceCoins} coins pour ${game.sessionDurationMinutes} min de jeu ?\n\nLa mise n\'est pas remboursable.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                        fontSize: 13.5),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                  color: AppColors.divider, width: 1),
                            ),
                          ),
                          child: Text('Annuler',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.45),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: AppColors.bgDark,
                              elevation: 0,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(free ? 'Jouer' : 'Payer & jouer',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

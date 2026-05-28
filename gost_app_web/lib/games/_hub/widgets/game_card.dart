// ============================================================
// GameCard — carte d'un jeu dans le grid
// ============================================================

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/game_model.dart';

class GameCard extends StatelessWidget {
  final GameModel game;
  final VoidCallback onTap;
  const GameCard({super.key, required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.35), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _thumbnail(),
                      if (game.featured)
                        Positioned(
                          top: 8, left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.neonYellow.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('VEDETTE',
                              style: TextStyle(
                                color: AppColors.bgDark,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              )),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(game.category.icon,
                          size: 12, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(game.category.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11)),
                      ),
                      _pricePill(),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnail() {
    final asset = game.thumbnailAsset;
    final url = game.thumbnailUrl;
    if (asset != null) {
      return Image.asset(asset, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder());
    }
    if (url != null) {
      return Image.network(url, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder());
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        color: AppColors.bgElevated,
        child: Center(
          child: Icon(game.category.icon,
              size: 44, color: AppColors.textMuted),
        ),
      );

  Widget _pricePill() {
    final free = game.entryPriceCoins == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: free
            ? AppColors.neonGreen.withValues(alpha: 0.18)
            : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (free ? AppColors.neonGreen : AppColors.divider)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        free ? 'Gratuit' : '${game.entryPriceCoins} c',
        style: TextStyle(
          color: free ? AppColors.neonGreen : AppColors.textSecondary,
          fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

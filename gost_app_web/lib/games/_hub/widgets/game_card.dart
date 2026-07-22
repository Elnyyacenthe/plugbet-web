// ============================================================
// GameCard — carte d'un jeu dans le grid
// ============================================================
// >>> DESIGN PREMIUM <<<
// Seul l'habillage visuel a ete retravaille (gradients, glow neon par
// categorie, scrim, badge vedette glassy, micro-animation au tap). La
// logique (game, onTap) est strictement identique a l'original.
// ============================================================

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/game_category.dart';
import '../models/game_model.dart';

class GameCard extends StatefulWidget {
  final GameModel game;
  final VoidCallback onTap;
  const GameCard({super.key, required this.game, required this.onTap});

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool _pressed = false;

  GameModel get game => widget.game;

  /// Couleur d'accent neon derivee de la categorie (purement decoratif).
  Color get _accent {
    switch (game.category) {
      case GameCategory.sport:
        return AppColors.neonGreen;
      case GameCategory.arcade:
        return AppColors.neonPurple;
      case GameCategory.action:
        return AppColors.neonOrange;
      case GameCategory.puzzle:
        return AppColors.neonBlue;
      case GameCategory.racing:
        return AppColors.neonRed;
      case GameCategory.casual:
        return AppColors.neonYellow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(16),
          splashColor: accent.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.bgCardLight,
                  AppColors.bgCard,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(alpha: 0.30),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.16),
                  blurRadius: 16,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _thumbnail(),
                        // Scrim degrade bas -> lisibilite + profondeur
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  AppColors.bgCard.withValues(alpha: 0.55),
                                ],
                                stops: const [0.55, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // Reflet vitre haut-gauche (matière/relief)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.center,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.12),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (game.featured)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: _featuredBadge(),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Row(children: [
                        Icon(game.category.icon, size: 12, color: accent),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(game.category.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
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
      ),
    );
  }

  Widget _featuredBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE082), Color(0xFFFFC107)],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonYellow.withValues(alpha: 0.55),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 11, color: Color(0xFF5A3D00)),
          const SizedBox(width: 3),
          Text('VEDETTE',
              style: TextStyle(
                color: const Color(0xFF5A3D00),
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              )),
        ],
      ),
    );
  }

  Widget _thumbnail() {
    final asset = game.thumbnailAsset;
    final url = game.thumbnailUrl;
    if (asset != null) {
      return Image.asset(asset,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    }
    if (url != null) {
      return Image.network(url,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final accent = _accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.25),
          radius: 1.15,
          colors: [
            Color.lerp(AppColors.bgElevated, accent, 0.22)!,
            AppColors.bgCard,
          ],
        ),
      ),
      child: Center(
        // Médaillon d'icône embossé (relief + halo néon)
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.35, -0.4),
              colors: [
                Color.lerp(AppColors.bgElevated, Colors.white, 0.10)!,
                AppColors.bgCard,
              ],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.2),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 16),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            game.category.icon,
            size: 32,
            color: accent,
            shadows: [
              Shadow(color: accent.withValues(alpha: 0.7), blurRadius: 12),
              const Shadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pricePill() {
    final free = game.entryPriceCoins == 0;
    final color = free ? AppColors.neonGreen : AppColors.neonYellow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: Text(
        free ? 'Gratuit' : '${game.entryPriceCoins} c',
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

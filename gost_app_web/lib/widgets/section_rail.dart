// ============================================================
// Plugbet – Rail de section + mini-affiche (chrome sombre)
// ============================================================
// Brique de la page « Top / Populaire » : une section = un titre avec
// une flèche « Tout voir », suivi d'une liste horizontale scrollable de
// [MiniPoster] (petites affiches rectangulaires à coins arrondis).
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'plugbet_wordmark.dart' show kPlugbetGreen;

/// Section titrée avec un rail horizontal scrollable.
class SectionRail extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  final double height;
  final List<Widget> children;

  const SectionRail({
    super.key,
    required this.title,
    required this.children,
    this.onSeeAll,
    this.height = 178,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (onSeeAll != null)
                InkWell(
                  onTap: onSeeAll,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'Tout voir',
                          style: TextStyle(
                            color: kPlugbetGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.arrow_forward_rounded,
                            size: 15, color: kPlugbetGreen),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ],
    );
  }
}

/// Petite affiche rectangulaire à coins arrondis : image de fond
/// (avec fallback dégradé + icône), titre en bas, badge optionnel.
class MiniPoster extends StatelessWidget {
  /// Chemin de l'image de fond. Si null, on affiche le fallback dégradé.
  final String? imageAsset;
  final String title;
  final String? subtitle;
  final IconData fallbackIcon;
  final String? badge;

  /// Largeur fixe (rails). null = s'étend à la cellule (grilles).
  final double? width;
  final VoidCallback onTap;

  const MiniPoster({
    super.key,
    required this.imageAsset,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.fallbackIcon = Icons.sports_esports_rounded,
    this.badge,
    this.width = 120,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageAsset == null)
                _fallback()
              else
                Image.asset(
                  imageAsset!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(),
                ),
              // Voile bas pour le titre.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.15),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                      stops: const [0.4, 0.65, 1],
                    ),
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: kPlugbetGreen,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 9,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kPlugbetGreen.withValues(alpha: 0.75),
            const Color(0xFF131C2E),
          ],
        ),
      ),
      child: Center(
        child: Icon(fallbackIcon,
            size: 34, color: Colors.white.withValues(alpha: 0.9)),
      ),
    );
  }
}

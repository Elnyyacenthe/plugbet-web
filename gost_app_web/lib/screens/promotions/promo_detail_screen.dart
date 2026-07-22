// ============================================================
// Plugbet — PromoDetailScreen (composant générique réutilisable)
// ============================================================
// UN SEUL écran de détail, paramétré par l'ID de la promo. Le contenu est
// piloté par les données du PromoItem (titre, description longue, bannière,
// conditions, CTA) — aucune page codée en dur par promo. La carte promo 2Up
// et les promos existantes utilisent donc le même composant.
//
// Repli propre : si l'ID ne correspond à aucune promo active -> écran
// « Promo introuvable » avec accès à la liste globale. Le bouton retour
// (AppBar) ramène à l'écran appelant (la liste des promos quand on y arrive
// depuis celle-ci).
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/promo_item.dart';
import '../../providers/promo_provider.dart';
import '../../theme/app_theme.dart';
import 'promotions_screen.dart';

class PromoDetailScreen extends StatelessWidget {
  /// Identifiant/slug de la promo à afficher.
  final String promoId;

  const PromoDetailScreen({super.key, required this.promoId});

  @override
  Widget build(BuildContext context) {
    final promo = context.watch<PromoProvider>().byId(promoId);
    if (promo == null) return _NotFound();

    final accent = AppColors.primary;
    const onDark = Colors.white;

    final ctaLabel = (promo.actionLabel == null ||
            promo.actionLabel == 'EN SAVOIR PLUS')
        ? 'J\'AI COMPRIS'
        : promo.actionLabel!;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: onDark,
        title: const Text('PROMOTION',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _banner(promo, accent),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (promo.badgeLabel != null) ...[
                  _pill(promo.badgeLabel!, accent),
                  const SizedBox(height: 10),
                ],
                Text(
                  promo.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                if (promo.highlightedReward != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    promo.highlightedReward!,
                    style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
                if (promo.endDate != null) ...[
                  const SizedBox(height: 10),
                  _countdown(promo),
                ],
                const SizedBox(height: 18),
                Text(
                  promo.longDescription ?? promo.description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 14.5,
                    height: 1.5,
                  ),
                ),
                if (promo.conditions.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const Text(
                    'CONDITIONS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...promo.conditions.map((c) => _conditionRow(c, accent)),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      ctaLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(PromoItem promo, Color accent) {
    const height = 230.0;
    if (promo.imageUrl.isNotEmpty) {
      // Affiche paysage en priorité, repli sur le portrait puis le dégradé.
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Image.asset(
          promo.bannerImageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
            promo.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradientBanner(height, accent),
          ),
        ),
      );
    }
    return _gradientBanner(height, accent);
  }

  Widget _gradientBanner(double height, Color accent) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.35),
            AppColors.bgCard,
          ],
        ),
      ),
      child: Center(
        child: Icon(Icons.trending_up_rounded,
            size: 76, color: accent),
      ),
    );
  }

  Widget _pill(String label, Color accent) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _conditionRow(String text, Color accent) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_rounded, size: 17, color: accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _countdown(PromoItem promo) {
    final d = promo.remainingTime;
    if (d == Duration.zero) return const SizedBox.shrink();
    final days = d.inDays;
    final hours = d.inHours % 24;
    final label = days > 0 ? '$days j $hours h restants' : '$hours h restants';
    return Row(
      children: [
        const Icon(Icons.schedule_rounded, size: 15, color: Colors.white70),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Repli : promo inconnue / expirée.
class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded,
                  size: 64, color: Colors.white38),
              const SizedBox(height: 14),
              const Text(
                'Promo introuvable',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cette promotion n\'est plus disponible.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const PromotionsScreen()),
                ),
                child: const Text('VOIR TOUTES LES PROMOS',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Plugbet — FAQ / Règlement (dont 2Up)
// ============================================================
// Explique le fonctionnement du 2Up (pas de cote réduite, conditions
// d'éligibilité, sports/marchés couverts, exclusions) et renvoie vers
// l'écran Jeu responsable. Contenu data-driven (liste de sections).
// ============================================================

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_icons.dart';
import 'responsible_gaming_screen.dart';

class _Faq {
  final String q;
  final String a;
  final List<String> bullets;
  const _Faq(this.q, this.a, {this.bullets = const []});
}

const List<_Faq> _faqs = [
  _Faq(
    'Qu\'est-ce que le 2Up ?',
    'Le 2Up est un paiement anticipé. Sur un pari pré-match « Résultat final » '
        '(1X2), si l\'équipe sur laquelle tu as parié (1 ou 2) atteint le seuil '
        'd\'avance requis en cours de match, ton pari est immédiatement réglé '
        'GAGNANT — même si le score change ensuite (remontée, nul ou défaite).',
    bullets: [
      'La cote n\'est JAMAIS réduite pour ce paiement anticipé.',
      'Si ton équipe gagne sans jamais atteindre le seuil, ton pari reste gagnant normalement à la fin.',
      'C\'est un déclenchement anticipé, pas une condition supplémentaire.',
    ],
  ),
  _Faq(
    'Quels sont les seuils par sport ?',
    'Le seuil d\'avance déclenchant le 2Up dépend du sport :',
    bullets: [
      'Football : 2 buts d\'avance.',
      'Basketball : 20 points d\'avance.',
      'Tennis : 2 sets d\'avance.',
      'Football américain : 17 points d\'avance.',
      'Baseball : 5 runs d\'avance.',
    ],
  ),
  _Faq(
    'Quels paris sont éligibles au 2Up ?',
    'Le 2Up s\'applique uniquement dans un cadre précis :',
    bullets: [
      'Paris pré-match sur le marché « Résultat final » (1X2).',
      'Sélection 1 (domicile) ou 2 (extérieur) uniquement.',
      'Le match nul (N) n\'est jamais éligible.',
      'Non applicable aux Bet Builders ni aux autres marchés.',
      'Uniquement sur les sports/compétitions dont les scores live sont couverts.',
    ],
  ),
  _Faq(
    'Comment ça marche pour un combiné ?',
    'Dans un pari combiné, si une sélection déclenche son 2Up, elle est marquée '
        'gagnante. Mais les autres sélections doivent gagner normalement pour que '
        'le combiné entier soit payé.',
  ),
  _Faq(
    'Et si le match est arrêté ou annulé ?',
    'Si le 2Up s\'est déjà déclenché, ton pari reste gagnant (le paiement est '
        'acquis). Si le match est annulé avant tout déclenchement, les règles '
        'standards d\'annulation s\'appliquent (remboursement de la mise).',
  ),
  _Faq(
    'Le 2Up remplace-t-il la vente anticipée (cash-out) ?',
    'Le 2Up est indépendant du cash-out. S\'il se déclenche, ton pari est déjà '
        'gagné : le cash-out manuel n\'a plus lieu d\'être sur ce pari.',
  ),
];

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('FAQ & Règlement',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Bandeau 2Up
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.25),
                  AppColors.bgCard,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Icon(Icons.trending_up_rounded,
                  color: AppColors.primary, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '2UP — Deux buts d\'avance, tu gagnes déjà ! Découvre les règles ci-dessous.',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.3),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          ..._faqs.map((f) => _FaqTile(faq: f)),
          const SizedBox(height: 20),
          // Renvoi Jeu responsable
          _linkCard(
            context,
            icon: AppIcons.verified,
            title: 'Jeu responsable',
            subtitle:
                'Fixe tes limites de mise ou active l\'auto-exclusion. Le 2Up ne contourne jamais ces protections.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ResponsibleGamingScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35)),
              ],
            ),
          ),
          Icon(AppIcons.chevronRight, color: AppColors.textMuted, size: 18),
        ]),
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _Faq faq;
  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textMuted,
          title: Text(faq.q,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(faq.a,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.5)),
            if (faq.bullets.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...faq.bullets.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(b,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

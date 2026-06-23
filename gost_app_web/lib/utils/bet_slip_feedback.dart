// ============================================================
// BetSlipFeedback — Helper unique pour afficher le bon message
//                  apres un toggle de pari dans le panier.
// ============================================================
// Centralise les 3 cas :
//   - Ajout       : "+ Sélection ajoutée au combiné"
//   - Retrait     : "Sélection retirée"
//   - Remplacement: "Sélection du match remplacée — 1 seul pari par match
//                    autorise dans un combine"
//
// Pourquoi un remplacement et pas un rejet ?
// Regle pro (1xBet/Bet365) : dans un combine, 2 selections du meme match
// sont rejetees car non-independantes (ex: Real Madrid gagne + Real Madrid
// marque -> evenements correles, le bookmaker ne paye pas).
// Notre UX : on remplace au lieu de rejeter -> moins frustrant + on
// previent clairement l'utilisateur.
// ============================================================

import 'package:flutter/material.dart';
import '../state/bet_slip_controller.dart';
import '../theme/app_theme.dart';

class BetSlipFeedback {
  BetSlipFeedback._();

  static void show(BuildContext context, ToggleResult r, BetSelection current) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (r.wasRemoved) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.bgElevated,
        duration: const Duration(milliseconds: 1400),
        content: Row(children: [
          Icon(Icons.remove_circle_outline_rounded,
              size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Sélection retirée — ${current.marketLabel}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 12)),
          ),
        ]),
      ));
      return;
    }
    if (r.wasReplaced) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.neonYellow.withValues(alpha: 0.12),
        duration: const Duration(milliseconds: 2200),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.neonYellow),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Sélection du match remplacée',
                    style: TextStyle(
                      color: AppColors.neonYellow,
                      fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('1 seul pari par match dans un combiné. '
                'Nouvelle sélection : ${current.marketLabel}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 11)),
          ],
        ),
      ));
      return;
    }
    // wasAdded
    messenger.showSnackBar(SnackBar(
      backgroundColor: AppColors.bgElevated,
      duration: const Duration(milliseconds: 1200),
      content: Row(children: [
        Icon(Icons.add_circle_outline_rounded,
            size: 14, color: AppColors.neonGreen),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Ajoutée au combiné — ${current.marketLabel}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary, fontSize: 12)),
        ),
      ]),
    ));
  }
}

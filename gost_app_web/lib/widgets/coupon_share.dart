// ============================================================
// coupon_share — dialogues « Partager » / « Charger » un coupon
// ============================================================
// UI réutilisable (page coupon + détails ticket) au-dessus de
// CouponShareService. Le partage génère un code copiable ; le chargement
// ajoute les sélections reçues au BetSlipController (sans doublon de match).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/coupon_share_service.dart';
import '../state/bet_slip_controller.dart';
import '../theme/app_theme.dart';
import '../theme/app_icons.dart';
import 'plugbet_wordmark.dart' show kPlugbetGreen;

final CouponShareService _service = CouponShareService();

String _humanizeError(Object e) {
  final s = e.toString();
  if (s.contains('EMPTY_COUPON')) return 'Ton coupon est vide.';
  if (s.contains('TOO_MANY_SELECTIONS')) return 'Trop de sélections (40 max).';
  if (s.contains('AUTH_REQUIRED')) return 'Connecte-toi pour cette action.';
  if (s.contains('COUPON_NOT_FOUND')) return 'Code introuvable.';
  if (s.contains('COUPON_EXPIRED')) return 'Ce coupon a expiré.';
  if (s.contains('CODE_REQUIRED')) return 'Entre un code.';
  return 'Une erreur est survenue. Réessaie.';
}

/// Message de la notification flottante après chargement (matchs terminés
/// retirés, doublons ignorés, sélections ajoutées).
String _loadResultMessage(int added, int skipped, int expired) {
  if (added == 0 && skipped == 0 && expired == 0) return 'Coupon vide.';
  // Aucun ajout possible et le blocage vient des matchs déjà commencés.
  if (added == 0 && skipped == 0 && expired > 0) {
    return expired == 1
        ? 'Le match de ce coupon est déjà commencé — rien à charger.'
        : 'Tous les matchs de ce coupon sont déjà commencés — rien à charger.';
  }
  final parts = <String>[];
  if (added > 0) parts.add('$added ajouté${added > 1 ? 's' : ''}');
  if (expired > 0) {
    parts.add(
        '$expired terminé${expired > 1 ? 's' : ''} retiré${expired > 1 ? 's' : ''}');
  }
  if (skipped > 0) parts.add('$skipped déjà au coupon');
  return parts.join(' · ');
}

SnackBar _snack(String msg, {Color? bg}) => SnackBar(
      backgroundColor: bg ?? AppColors.bgElevated,
      duration: const Duration(seconds: 3),
      content: Text(msg,
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
    );

/// Partage une liste de sélections -> génère un code et l'affiche.
Future<void> shareCouponSelections(
    BuildContext context, List<BetSelection> sels) async {
  final messenger = ScaffoldMessenger.of(context);
  if (sels.isEmpty) {
    messenger.showSnackBar(_snack('Ton coupon est vide.'));
    return;
  }
  SharedCouponResult? r;
  Object? err;
  try {
    r = await _service.share(sels);
  } catch (e) {
    err = e;
  }
  if (!context.mounted) return;
  if (err != null || r == null) {
    messenger.showSnackBar(_snack(_humanizeError(err ?? 'error')));
    return;
  }
  await _showCodeDialog(context, r);
}

Future<void> _showCodeDialog(BuildContext context, SharedCouponResult r) {
  final messenger = ScaffoldMessenger.of(context);
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: Row(children: [
        Icon(AppIcons.share, color: kPlugbetGreen, size: 20),
        const SizedBox(width: 8),
        Text('Coupon partagé',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          '${r.count} sélection${r.count > 1 ? 's' : ''}. Envoie ce code à un '
          'ami — il pourra le charger dans son propre coupon.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: r.code));
            messenger.showSnackBar(_snack('Code copié : ${r.code}'));
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kPlugbetGreen.withValues(alpha: 0.5)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(r.code,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  )),
              const SizedBox(width: 10),
              Icon(AppIcons.copy, size: 18, color: AppColors.textMuted),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text('Valable 7 jours',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ]),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: r.code));
            messenger.showSnackBar(_snack('Code copié : ${r.code}'));
          },
          child: Text('Copier',
              style: TextStyle(
                  color: kPlugbetGreen, fontWeight: FontWeight.w900)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Fermer', style: TextStyle(color: AppColors.textMuted)),
        ),
      ],
    ),
  );
}

/// Dialogue « Charger un coupon » : saisie du code -> ajout au coupon.
Future<void> showLoadCouponDialog(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  final textCtrl = TextEditingController();
  bool busy = false;

  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> doLoad() async {
          final code = textCtrl.text.trim();
          if (code.isEmpty) {
            messenger.showSnackBar(_snack('Entre un code.'));
            return;
          }
          setLocal(() => busy = true);
          List<BetSelection>? sels;
          Object? err;
          try {
            sels = await _service.load(code);
          } catch (e) {
            err = e;
          }
          if (!ctx.mounted) return;
          if (err != null || sels == null) {
            setLocal(() => busy = false);
            messenger.showSnackBar(_snack(_humanizeError(err ?? 'error')));
            return;
          }
          final ctrl = BetSlipController.instance;
          final now = DateTime.now();
          int added = 0, skipped = 0, expired = 0;
          for (final s in sels) {
            // Match déjà commencé / terminé -> non pariable, on l'écarte.
            if (s.isLive || !s.kickoff.isAfter(now)) {
              expired++;
              continue;
            }
            if (ctrl.hasMatch(s.matchId)) {
              skipped++;
              continue;
            }
            ctrl.toggle(s);
            added++;
          }
          Navigator.pop(ctx);
          messenger.showSnackBar(_snack(
            _loadResultMessage(added, skipped, expired),
            bg: added > 0 ? AppColors.primary : AppColors.bgElevated,
          ));
        }

        return AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Row(children: [
            Icon(AppIcons.qrCode, color: kPlugbetGreen, size: 20),
            const SizedBox(width: 8),
            Text('Charger un coupon',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Colle le code reçu d\'un ami pour ajouter ses sélections à ton '
              'coupon.',
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: textCtrl,
              autofocus: true,
              enabled: !busy,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              maxLength: 8,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Ex : A1B2C3',
                hintStyle: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 16,
                    letterSpacing: 2),
                filled: true,
                fillColor: AppColors.bgElevated,
                suffixIcon: IconButton(
                  icon: Icon(AppIcons.paste, color: AppColors.textMuted, size: 20),
                  tooltip: 'Coller',
                  onPressed: () async {
                    final d = await Clipboard.getData('text/plain');
                    if (d?.text != null) {
                      textCtrl.text = d!.text!.trim().toUpperCase();
                    }
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: busy ? null : doLoad,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPlugbetGreen,
                foregroundColor: Colors.black,
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text('Charger',
                      style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        );
      },
    ),
  );
}

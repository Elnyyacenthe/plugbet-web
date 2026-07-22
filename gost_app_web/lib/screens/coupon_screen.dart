// ============================================================
// Plugbet – Écran Coupon (onglet central de la barre principale)
// ============================================================
// Aperçu du coupon en cours (sélections du BetSlipController). La
// validation/placement réutilise le bottom sheet existant et testé
// (`showBetSlipSheet`). Chrome sombre (#0B1120) cohérent avec la barre.
// ============================================================

import 'package:flutter/material.dart';

import '../state/bet_slip_controller.dart';
import '../widgets/bet_slip.dart';
import '../widgets/coupon_share.dart';
import '../theme/app_theme.dart';
import '../theme/app_icons.dart';
import '../widgets/plugbet_wordmark.dart' show kPlugbetGreen;
import '../widgets/main_bottom_nav.dart' show TicketIcon;

class CouponScreen extends StatelessWidget {
  const CouponScreen({super.key});

  static String _fmt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = BetSlipController.instance;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: ctrl,
          builder: (context, _) {
            final items = ctrl.items;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, items.length, ctrl),
                Expanded(
                  child: items.isEmpty
                      ? _EmptyCoupon(onLoad: () => showLoadCouponDialog(context))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _SelectionTile(
                            sel: items[i],
                            onRemove: () => ctrl.remove(items[i].matchId),
                          ),
                        ),
                ),
                if (items.isNotEmpty) _footer(context, ctrl),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int n, BetSlipController ctrl) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
      child: Row(
        children: [
          TicketIcon(size: 26, color: kPlugbetGreen),
          const SizedBox(width: 10),
          Text(
            'Mon coupon',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          // Charger un coupon partagé (toujours dispo, même vide).
          IconButton(
            onPressed: () => showLoadCouponDialog(context),
            icon: Icon(AppIcons.qrCode, size: 22, color: AppColors.textMuted),
            tooltip: 'Charger un coupon',
            splashRadius: 22,
          ),
          // Partager le coupon en cours.
          if (n > 0)
            IconButton(
              onPressed: () => shareCouponSelections(context, ctrl.items),
              icon: Icon(AppIcons.share, size: 22, color: kPlugbetGreen),
              tooltip: 'Partager le coupon',
              splashRadius: 22,
            ),
          if (n > 0)
            TextButton(
              onPressed: ctrl.clear,
              child: Text(
                'Vider',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, BetSlipController ctrl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.divider)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _line('Cote totale', ctrl.combinedOdds.toStringAsFixed(2)),
          const SizedBox(height: 6),
          _line('Mise', '${_fmt(ctrl.stake)} FCFA'),
          const SizedBox(height: 6),
          _line('Gain potentiel', '${_fmt(ctrl.potentialWin)} FCFA',
              highlight: true),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => showBetSlipSheet(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPlugbetGreen,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Valider le coupon',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: highlight ? kPlugbetGreen : AppColors.textPrimary,
            fontSize: highlight ? 16 : 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SelectionTile extends StatelessWidget {
  final BetSelection sel;
  final VoidCallback onRemove;

  const _SelectionTile({required this.sel, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sel.marketLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sel.matchLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            sel.odds.toStringAsFixed(2),
            style: const TextStyle(
              color: kPlugbetGreen,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded,
                size: 18, color: AppColors.textMuted),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _EmptyCoupon extends StatelessWidget {
  final VoidCallback onLoad;
  const _EmptyCoupon({required this.onLoad});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TicketIcon(size: 64, color: AppColors.textMuted),
          const SizedBox(height: 18),
          Text(
            'Aucune sélection',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Ajoute des paris depuis l\'onglet Populaire, ou charge le coupon partagé par un ami.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onLoad,
            icon: Icon(AppIcons.qrCode, size: 18, color: kPlugbetGreen),
            label: Text('Charger un coupon',
                style: TextStyle(
                    color: kPlugbetGreen, fontWeight: FontWeight.w900)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: kPlugbetGreen.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

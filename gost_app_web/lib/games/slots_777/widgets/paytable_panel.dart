// ============================================================
// PaytablePanel — Bottom sheet table des gains
// ============================================================

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/slot_models.dart';

class PaytablePanel extends StatelessWidget {
  const PaytablePanel({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B0E33),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const PaytablePanel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Text('💰', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text('Table des gains',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                )),
          ]),
          const SizedBox(height: 14),
          _section('3 SYMBOLES IDENTIQUES (sur la ligne)', context),
          ...Paytable.threeOfAKind.entries.map(_payRow),
          const SizedBox(height: 14),
          _section('2 SYMBOLES IDENTIQUES (sur la ligne)', context),
          ...Paytable.twoOfAKind.entries.map(_payRow),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.neonYellow.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.neonYellow.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline,
                  size: 16, color: AppColors.neonYellow),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Les gains s\'appliquent uniquement sur la ligne centrale. '
                  'Chaque spin est independant.',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _section(String label, BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Divider(color: AppColors.divider, thickness: 0.5)),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              )),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: AppColors.divider, thickness: 0.5)),
        ]),
      );

  Widget _payRow(MapEntry<SlotSymbol, int> e) {
    final s = e.key;
    final m = e.value;
    final isJackpot = s == SlotSymbol.seven && m >= 500;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 60,
          child: Text(s.emoji,
              style: TextStyle(
                  fontSize: 22,
                  color: s.isSeven ? AppColors.neonRed : null,
                  fontWeight:
                      s.isSeven ? FontWeight.w900 : FontWeight.normal)),
        ),
        Expanded(
          child: Text(s.label,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              )),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isJackpot
                ? AppColors.neonRed
                : AppColors.neonGreen.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isJackpot ? Colors.transparent : AppColors.neonGreen,
              width: 0.6,
            ),
          ),
          child: Text(
            isJackpot ? '×$m JACKPOT' : '×$m',
            style: TextStyle(
              color: isJackpot ? Colors.white : AppColors.neonGreen,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ]),
    );
  }
}

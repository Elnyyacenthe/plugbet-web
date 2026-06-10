// ============================================================
// BetSlip — Pill flottante + BottomSheet panier de paris
// ============================================================
// 2 widgets exportes :
//   - BetSlipPill   : pill flottante en bas a droite, badge nb selections
//   - showBetSlipSheet(context) : ouvre la bottom sheet du panier
//
// Le panier ecoute BetSlipController (singleton, ChangeNotifier).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../state/bet_slip_controller.dart';

// ── Pill flottante ────────────────────────────────────────

class BetSlipPill extends StatelessWidget {
  final VoidCallback onTap;
  const BetSlipPill({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: BetSlipController.instance,
      builder: (context, _) {
        final n = BetSlipController.instance.count;
        if (n == 0) return const SizedBox.shrink();

        final c = BetSlipController.instance;
        final cote = c.combinedOdds.toStringAsFixed(2);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.neonGreen,
                      AppColors.neonGreen.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonGreen.withValues(alpha: 0.45),
                      blurRadius: 12, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text('$n',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Panier de paris',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            )),
                        const SizedBox(height: 1),
                        Text(
                          'Cote totale : ×$cote',
                          style: TextStyle(
                            color: Colors.black.withValues(alpha: 0.75),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_upward_rounded,
                      color: Colors.black, size: 20),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Badge LIVE / À venir / VIRT (utilise dans le panier + single sheet) ──

Widget _badgeFor(BetSelection s) {
  final Color bg;
  final Color fg;
  final String label;
  final bool bordered;
  if (s.isVirtual) {
    bg = AppColors.neonPurple;
    fg = Colors.white;
    label = 'VIRT';
    bordered = false;
  } else if (s.isLive) {
    bg = AppColors.neonRed;
    fg = Colors.white;
    label = 'LIVE';
    bordered = false;
  } else {
    bg = AppColors.bgCard;
    fg = AppColors.textMuted;
    label = 'À venir';
    bordered = true;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
      border: bordered
          ? Border.all(
              color: AppColors.divider.withValues(alpha: 0.5), width: 0.5)
          : null,
    ),
    child: Text(label,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        )),
  );
}

// ── Single bet sheet (tap simple sur une cote) ────────────

Future<void> showSingleBetSheet(BuildContext context, BetSelection sel) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SingleBetSheet(selection: sel),
  );
}

class _SingleBetSheet extends StatefulWidget {
  final BetSelection selection;
  const _SingleBetSheet({required this.selection});

  @override
  State<_SingleBetSheet> createState() => _SingleBetSheetState();
}

class _SingleBetSheetState extends State<_SingleBetSheet> {
  late final TextEditingController _stakeCtrl;
  int _stake = 1000;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _stakeCtrl = TextEditingController(text: '$_stake');
    _stakeCtrl.addListener(() {
      final v = int.tryParse(_stakeCtrl.text.trim()) ?? 0;
      if (v > 0) setState(() => _stake = v.clamp(100, 1000000));
    });
  }

  @override
  void dispose() {
    _stakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.selection;
    final win = (_stake * s.odds).round();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Row(children: [
          Icon(Icons.flash_on_rounded,
              color: AppColors.neonYellow, size: 22),
          const SizedBox(width: 8),
          Text('Pari simple',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              )),
          const Spacer(),
          TextButton.icon(
            icon: Icon(Icons.add_box_rounded,
                size: 16, color: AppColors.neonGreen),
            label: Text('Au combiné',
                style: TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                )),
            onPressed: () {
              BetSlipController.instance.toggle(s);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _badgeFor(s),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.matchLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    )),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.check_circle_rounded,
                  size: 13, color: AppColors.neonGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.marketLabel,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.neonGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.neonGreen.withValues(alpha: 0.6),
                      width: 0.6),
                ),
                child: Text('×${s.odds.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: AppColors.neonGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    )),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            Icon(Icons.savings_rounded,
                size: 18, color: AppColors.neonYellow),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _stakeCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                cursorColor: AppColors.neonGreen,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            Text('FCFA',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                )),
            const SizedBox(width: 14),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          for (final v in [500, 1000, 2500, 5000])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () {
                  setState(() => _stake = v);
                  _stakeCtrl.text = '$v';
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.divider.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  child: Text('+$v',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      )),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.3), width: 0.6),
          ),
          child: Row(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cote',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text('×${s.odds.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: AppColors.neonYellow,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    )),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gain potentiel',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text('$win FCFA',
                    style: TextStyle(
                      color: AppColors.neonGreen,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    )),
              ],
            ),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: _submitting
              ? Center(
                  child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.neonGreen),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: () => _doSubmit(context),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(
                    'Parier · $_stake FCFA',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 0.3),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
        ),
      ]),
    );
  }

  Future<void> _doSubmit(BuildContext context) async {
    setState(() => _submitting = true);
    final res = await BetSlipController.instance
        .submitSingle(widget.selection, _stake);
    if (!context.mounted) return;
    setState(() => _submitting = false);
    if (res.success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.neonGreen,
          duration: const Duration(seconds: 2),
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pari validé · gain potentiel ${res.potentialPayout} FCFA',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ]),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.neonRed,
          duration: const Duration(seconds: 3),
          content: Text(res.error ?? 'Erreur',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      );
    }
  }
}

// ── Bottom sheet panier combine ───────────────────────────

Future<void> showBetSlipSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _BetSlipSheet(),
  );
}

class _BetSlipSheet extends StatefulWidget {
  const _BetSlipSheet();

  @override
  State<_BetSlipSheet> createState() => _BetSlipSheetState();
}

class _BetSlipSheetState extends State<_BetSlipSheet> {
  late final TextEditingController _stakeCtrl;
  final _ctrl = BetSlipController.instance;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _stakeCtrl = TextEditingController(text: '${_ctrl.stake}');
    _stakeCtrl.addListener(() {
      final v = int.tryParse(_stakeCtrl.text.trim()) ?? 0;
      if (v > 0) _ctrl.setStake(v);
    });
  }

  @override
  void dispose() {
    _stakeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final items = _ctrl.items;
          return Column(children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _header(items.length),
            const SizedBox(height: 8),
            _modeSwitch(),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? _empty()
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _selectionTile(items[i]),
                    ),
            ),
            if (items.isNotEmpty) _footer(),
          ]);
        },
      ),
    );
  }

  Widget _header(int n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Icon(Icons.receipt_long_rounded,
            color: AppColors.neonGreen, size: 22),
        const SizedBox(width: 8),
        Text('Mon panier',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            )),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.neonGreen.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$n',
              style: TextStyle(
                color: AppColors.neonGreen,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              )),
        ),
        const Spacer(),
        if (n > 0)
          TextButton.icon(
            onPressed: () => _ctrl.clear(),
            icon: Icon(Icons.delete_outline, size: 16, color: AppColors.neonRed),
            label: Text('Vider',
                style: TextStyle(
                  color: AppColors.neonRed,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                )),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ]),
    );
  }

  Widget _modeSwitch() {
    final mode = _ctrl.mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.4), width: 0.5),
        ),
        child: Row(children: [
          _modeChip(BetMode.combine, 'Combiné',
              'Une mise, toutes les cotes multipliées', mode),
          _modeChip(BetMode.simple, 'Simples',
              'Chaque sélection = un pari indépendant', mode),
        ]),
      ),
    );
  }

  Widget _modeChip(BetMode m, String label, String hint, BetMode current) {
    final active = m == current;
    return Expanded(
      child: InkWell(
        onTap: () => _ctrl.setMode(m),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.neonGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                color: active ? Colors.black : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              )),
        ),
      ),
    );
  }

  Widget _selectionTile(BetSelection s) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _badgeFor(s),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.matchLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                )),
          ),
          InkWell(
            onTap: () => _ctrl.remove(s.matchId),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 16, color: AppColors.textMuted),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.check_circle_rounded,
              size: 12, color: AppColors.neonGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(s.marketLabel,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                )),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: AppColors.neonGreen.withValues(alpha: 0.6),
                  width: 0.6),
            ),
            child: Text('×${s.odds.toStringAsFixed(2)}',
                style: TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                )),
          ),
        ]),
      ]),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.receipt_long_rounded,
              size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Panier vide',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 6),
          Text(
            'Appuie sur une cote (1, X ou 2) d\'un match\n'
            'pour ajouter une sélection à ton panier.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ]),
      ),
    );
  }

  Widget _footer() {
    final mode = _ctrl.mode;
    final n = _ctrl.count;
    final isCombine = mode == BetMode.combine;
    final coteTotale = _ctrl.combinedOdds;
    final totalStake = _ctrl.totalStake;
    final win = _ctrl.potentialWin;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        border: Border(
          top: BorderSide(
              color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      child: Column(children: [
        // Mise input
        Row(children: [
          Text(isCombine ? 'Mise du combiné' : 'Mise par pari',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              )),
          const Spacer(),
          if (!isCombine && n > 1)
            Text('Total débité : $totalStake FCFA',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                )),
        ]),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            Icon(Icons.savings_rounded,
                size: 18, color: AppColors.neonYellow),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _stakeCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                cursorColor: AppColors.neonGreen,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            Text('FCFA',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                )),
            const SizedBox(width: 14),
          ]),
        ),
        const SizedBox(height: 8),
        // Quick-stake chips
        Row(children: [
          for (final v in [500, 1000, 2500, 5000])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () {
                  _ctrl.setStake(v);
                  _stakeCtrl.text = '$v';
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.divider.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  child: Text('+$v',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      )),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        // Summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.3), width: 0.6),
          ),
          child: Row(children: [
            if (isCombine) ...[
              _summaryCol('Cote totale', '×${coteTotale.toStringAsFixed(2)}',
                  AppColors.neonYellow),
              const SizedBox(width: 12),
            ],
            _summaryCol('Sélections', '$n', AppColors.textPrimary),
            const Spacer(),
            _summaryCol(
              'Gain potentiel',
              '$win FCFA',
              AppColors.neonGreen,
              right: true,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // CTA
        SizedBox(
          width: double.infinity,
          height: 50,
          child: _submitting
              ? Center(
                  child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.neonGreen),
                  ),
                )
              : ElevatedButton.icon(
            onPressed: () => _submit(context),
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: Text(
              'Valider le pari · $totalStake FCFA',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 0.3),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _summaryCol(String label, String value, Color valueColor,
      {bool right = false}) {
    return Column(
      crossAxisAlignment:
          right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            )),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
              color: valueColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            )),
      ],
    );
  }

  Future<void> _submit(BuildContext context) async {
    setState(() => _submitting = true);
    final res = await _ctrl.submit();
    if (!context.mounted) return;
    setState(() => _submitting = false);
    if (res.success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.neonGreen,
          duration: const Duration(seconds: 2),
          content: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.black, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pari validé · gain potentiel ${res.potentialPayout} FCFA',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ]),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.neonRed,
          duration: const Duration(seconds: 3),
          content: Text(res.error ?? 'Erreur',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      );
    }
  }
}

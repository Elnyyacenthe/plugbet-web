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
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_icons.dart';
import '../theme/app_reliefs.dart';
import '../theme/app_surfaces.dart';
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
              borderRadius: AppRadius.brMd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.brMd,
                  gradient: AppSurfaces.raisedGradient(AppColors.primary),
                  boxShadow: AppSurfaces.raised(
                      glow: AppColors.primary, elevation: 1.1),
                ),
                child: Row(children: [
                  // Le compteur est gravé dans le pill : un puits, pas
                  // une pastille posée dessus.
                  InsetPanel(
                    radius: AppRadius.xs,
                    depth: 0.8,
                    baseColor: AppSurfaces.darken(AppColors.primary, 0.35),
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Text('$n',
                            style: TextStyle(
                              color: AppSurfaces.inkOn(AppColors.primary),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            )),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Panier de paris',
                            style: TextStyle(
                              color: AppSurfaces.inkOn(AppColors.primary),
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.2,
                            )),
                        const SizedBox(height: 1),
                        Text(
                          'Cote totale : ×$cote',
                          style: TextStyle(
                            color: AppSurfaces.inkOn(AppColors.primary)
                                .withValues(alpha: 0.75),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(AppIcons.up,
                      color: AppSurfaces.inkOn(AppColors.primary), size: 20),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Badge LIVE / À venir / FLASH (utilise dans le panier + single sheet) ──

Widget _badgeFor(BetSelection s) {
  final Color bg;
  final Color fg;
  final String label;
  final bool bordered;
  if (s.isVirtual) {
    bg = AppColors.neonPurple;
    fg = Colors.white;
    label = 'FLASH';
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

// ── Indicateur 2Up (paiement anticipe) sur une selection eligible ──
Widget _twoUpBadge(BetSelection s) {
  if (!s.twoUpEligible) return const SizedBox.shrink();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Text('2UP',
        style: TextStyle(
          color: Colors.black,
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
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Row(children: [
          Icon(AppIcons.bets, color: AppColors.neonYellow, size: 22),
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
            icon:
                Icon(AppIcons.addCircle, size: 16, color: AppColors.primaryInk),
            label: Text('Au combiné',
                style: TextStyle(
                  color: AppColors.primaryInk,
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _badgeFor(s),
              if (s.twoUpEligible) ...[
                const SizedBox(width: 6),
                _twoUpBadge(s),
              ],
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
              Icon(AppIcons.checkCircleFilled,
                  size: 13, color: AppColors.primaryInk),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryInk.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.primaryInk.withValues(alpha: 0.6),
                      width: 0.6),
                ),
                child: Text('×${s.odds.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: AppColors.primaryInk,
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
            Icon(AppIcons.savings, size: 18, color: AppColors.neonYellow),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _stakeCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                cursorColor: AppColors.primaryInk,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                color: AppColors.primaryInk.withValues(alpha: 0.3), width: 0.6),
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
                      color: AppColors.primaryInk,
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
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.primaryInk),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: () => _doSubmit(context),
                  icon: const Icon(AppIcons.bets, size: 18),
                  label: Text(
                    'Parier · $_stake FCFA',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 0.3),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
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
    final res =
        await BetSlipController.instance.submitSingle(widget.selection, _stake);
    if (!context.mounted) return;
    setState(() => _submitting = false);
    if (res.success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
          content: Row(children: [
            const Icon(AppIcons.checkCircleFilled,
                color: AppColors.onPrimary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pari validé · gain potentiel ${res.potentialPayout} FCFA',
                style: const TextStyle(
                  color: AppColors.onPrimary,
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

// ── Bottom sheet panier combine (style 1xBet) ─────────────

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
  final _bonusCodeCtrl = TextEditingController();
  final _ctrl = BetSlipController.instance;
  bool _submitting = false;

  /// Wallet balance affichee dans la section paiement.
  /// null = en cours de fetch. Chargee depuis profiles.coins une fois.
  int? _walletBalance;

  @override
  void initState() {
    super.initState();
    _stakeCtrl = TextEditingController(text: '${_ctrl.stake}');
    _stakeCtrl.addListener(() {
      final v = int.tryParse(_stakeCtrl.text.trim()) ?? 0;
      if (v > 0) _ctrl.setStake(v);
    });
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final res = await Supabase.instance.client
          .from('user_profiles')
          .select('coins')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _walletBalance = (res?['coins'] as num?)?.toInt() ?? 0);
    } catch (_) {/* silencieux */}
  }

  @override
  void dispose() {
    _stakeCtrl.dispose();
    _bonusCodeCtrl.dispose();
    super.dispose();
  }

  void _bumpStake(int delta) {
    final v = (_ctrl.stake + delta).clamp(25, 2150000);
    _ctrl.setStake(v);
    _stakeCtrl.text = '$v';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, scrollCtrl) => AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final items = _ctrl.items;
          return Column(children: [
            // Handle
            Container(
              width: 40,
              height: 4,
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
                      itemBuilder: (_, i) => _selectionTile1xBet(items[i]),
                    ),
            ),
            if (items.isNotEmpty) _footer1xBet(),
          ]);
        },
      ),
    );
  }

  Widget _header(int n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Icon(AppIcons.receipt, color: AppColors.primaryInk, size: 22),
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
            color: AppColors.primaryInk.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$n',
              style: TextStyle(
                color: AppColors.primaryInk,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              )),
        ),
        const Spacer(),
        if (n > 0)
          TextButton.icon(
            onPressed: () => _ctrl.clear(),
            icon: Icon(AppIcons.delete, size: 16, color: AppColors.neonRed),
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
      // Même commutateur que le sélecteur de sport : sillon + touche.
      child: InsetPanel(
        radius: AppRadius.xs,
        padding: const EdgeInsets.all(3),
        baseColor: AppColors.bgDark,
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
        borderRadius: AppRadius.brXs,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brXs,
            gradient:
                active ? AppSurfaces.raisedGradient(AppColors.primary) : null,
            boxShadow: active
                ? AppSurfaces.raised(glow: AppColors.primary, elevation: 0.5)
                : null,
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                color: active
                    ? AppSurfaces.inkOn(AppColors.primary)
                    : AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              )),
        ),
      ),
    );
  }

  /// Tile style 1xBet :
  ///   [icone sport] Competition (en gris)                              [X]
  ///   Equipe A — Equipe B (gros bleu)
  ///   [LIVE] 1ère mi-temps, (2-7)   (rouge si live, gris si kickoff)
  ///   Temps réglementaire / Market label              [cote] [↑ ou ↓]
  Widget _selectionTile1xBet(BetSelection s) {
    final teams = _parseTeams(s.matchLabel);
    final sportIcon = _sportIcon(s);
    final hasLiveScore = s.isLive && s.homeScore != null && s.awayScore != null;
    final previous = s.previousOdds;
    final oddsChanged = previous != null && (s.odds - previous).abs() > 0.001;
    final wentUp = oddsChanged && s.odds > previous;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: oddsChanged
                ? (wentUp ? AppColors.primaryInk : AppColors.neonRed)
                    .withValues(alpha: 0.4)
                : AppColors.divider.withValues(alpha: 0.5),
            width: oddsChanged ? 0.9 : 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Ligne 1 : sport icon + competition + X ──
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(sportIcon, size: 12, color: AppColors.textMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.competition ?? (s.isVirtual ? 'Match Flash' : 'Sport'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          if (s.twoUpEligible) ...[
            _twoUpBadge(s),
            const SizedBox(width: 6),
          ],
          InkWell(
            onTap: () => _ctrl.remove(s.matchId),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(AppIcons.close, size: 18, color: AppColors.textMuted),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        // ── Ligne 2 : equipes en gros ──
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                height: 1.25,
              ),
              children: [
                TextSpan(text: teams.home),
                if (teams.away.isNotEmpty)
                  TextSpan(
                      text: '  —  ',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      )),
                if (teams.away.isNotEmpty) TextSpan(text: teams.away),
              ],
            ),
          ),
        ),
        // ── Ligne 3 : status match (LIVE + score ou date) ──
        if (s.isLive || s.isVirtual)
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 4),
            child: Row(children: [
              if (s.isLive) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.neonRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ] else if (s.isVirtual) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.neonPurple,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(_statusLine(s, hasLiveScore: hasLiveScore),
                  style: TextStyle(
                    color: s.isLive ? AppColors.neonRed : AppColors.neonPurple,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  )),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 4),
            child: Text(_formatKickoff(s.kickoff),
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ),
        const SizedBox(height: 8),
        Container(height: 0.5, color: AppColors.divider.withValues(alpha: 0.4)),
        const SizedBox(height: 8),
        // ── Ligne 4 : market label + cote (+ fleche si changement) ──
        Padding(
          padding: const EdgeInsets.only(left: 30, right: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_sectionFor(s.marketLabel),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      )),
                  Text(_pickFor(s.marketLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // PlugLock : verrou de cote (uniquement en live, la ou ca bouge)
            if (s.isLive) ...[
              _lockButton(s),
              const SizedBox(width: 8),
            ],
            // Bloc cote (avec previous odds barree si change)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (oddsChanged)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      wentUp ? AppIcons.chevronUp : AppIcons.chevronDown,
                      size: 18,
                      color: wentUp ? AppColors.primaryInk : AppColors.neonRed,
                    ),
                    Text(previous.toStringAsFixed(2),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: AppColors.textMuted,
                        )),
                  ]),
                Text(s.odds.toStringAsFixed(2),
                    style: TextStyle(
                      color: oddsChanged
                          ? (wentUp ? AppColors.primaryInk : AppColors.neonRed)
                          : AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    )),
              ],
            ),
          ]),
        ),
      ]),
    );
  }

  /// PlugLock — bouton de verrouillage de la cote (garantie de cote).
  /// Quand il est actif, le rafraichisseur ne modifie plus la cote : elle
  /// est garantie a la validation, meme si le marche bouge.
  Widget _lockButton(BetSelection s) {
    final locked = s.locked;
    return InkWell(
      onTap: () => _ctrl.toggleLock(s.matchId, s.marketCode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: locked
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: locked
                ? AppColors.primary.withValues(alpha: 0.6)
                : AppColors.divider.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 13,
              color: locked ? AppColors.primary : AppColors.textMuted),
          const SizedBox(width: 3),
          Text('LOCK',
              style: TextStyle(
                color: locked ? AppColors.primary : AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              )),
        ]),
      ),
    );
  }

  /// Renvoie le 1er fragment du market_label avant " — "
  String _sectionFor(String label) {
    final idx = label.indexOf(' — ');
    if (idx > 0) return label.substring(0, idx).trim();
    final idx2 = label.indexOf(':');
    if (idx2 > 0) return label.substring(0, idx2).trim();
    return 'Pari';
  }

  /// Renvoie le 2e fragment du market_label apres " — "
  String _pickFor(String label) {
    final idx = label.indexOf(' — ');
    if (idx > 0) return label.substring(idx + 3).trim();
    final idx2 = label.indexOf(':');
    if (idx2 > 0) return label.substring(idx2 + 1).trim();
    return label;
  }

  /// Parse "Home vs Away" / "Home - Away" -> (home, away)
  ({String home, String away}) _parseTeams(String label) {
    final patterns = [
      RegExp(r'\s+vs\.?\s+', caseSensitive: false),
      RegExp(r'\s+-\s+'),
    ];
    for (final p in patterns) {
      final parts = label.split(p);
      if (parts.length == 2) {
        return (home: parts[0].trim(), away: parts[1].trim());
      }
    }
    return (home: label, away: '');
  }

  IconData _sportIcon(BetSelection s) {
    final sport = s.sportName?.toLowerCase();
    if (sport == 'basketball') return AppIcons.basketball;
    if (sport == 'americanfootball' || sport == 'american_football') {
      return Icons.sports_football_rounded;
    }
    if (sport == 'baseball') return Icons.sports_baseball_rounded;
    if (sport == 'tennis') return AppIcons.tennis;
    // Defaut soccer
    return AppIcons.football;
  }

  String _statusLine(BetSelection s, {required bool hasLiveScore}) {
    if (s.isLive) {
      final scorePart = hasLiveScore ? ' (${s.homeScore}-${s.awayScore})' : '';
      final mn = s.minute != null ? "${s.minute}'" : 'LIVE';
      return '$mn$scorePart';
    }
    if (s.isVirtual) return 'Match Flash';
    return _formatKickoff(s.kickoff);
  }

  String _formatKickoff(DateTime dt) {
    final l = dt.toLocal();
    const months = [
      'janv',
      'févr',
      'mars',
      'avr',
      'mai',
      'juin',
      'juil',
      'août',
      'sept',
      'oct',
      'nov',
      'déc',
    ];
    final dd = l.day.toString().padLeft(2, '0');
    final mo = months[(l.month - 1).clamp(0, 11)];
    final hh = l.hour.toString().padLeft(2, '0');
    final mn = l.minute.toString().padLeft(2, '0');
    return '$dd $mo $hh:$mn';
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(AppIcons.receipt, size: 56, color: AppColors.textMuted),
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

  Widget _footer1xBet() {
    final mode = _ctrl.mode;
    final n = _ctrl.count;
    final isCombine = mode == BetMode.combine;
    final coteTotale = _ctrl.combinedOdds;
    final totalStake = _ctrl.totalStake;
    final win = _ctrl.potentialWin;
    final hasChanges = _ctrl.hasOddsChanges;
    // Pour la fleche globale: si TOTAL cote a augmente, fleche verte
    double? prevCombined;
    if (isCombine && hasChanges) {
      prevCombined =
          _items.fold<double>(1, (acc, s) => acc * (s.previousOdds ?? s.odds));
      if ((prevCombined - coteTotale).abs() < 0.001) prevCombined = null;
    }
    final coteWentUp = prevCombined != null && coteTotale > prevCombined;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        border: Border(
          top: BorderSide(
              color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Résumé "Événements + Cote totale" ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Row(children: [
                Icon(AppIcons.layers, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text('Événements',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$n',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
              ]),
            ),
            Container(
              width: 0.6,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: AppColors.divider.withValues(alpha: 0.5),
            ),
            Expanded(
              child: Row(children: [
                Text(isCombine ? 'Cote' : 'Total',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (prevCombined != null)
                  Icon(
                    coteWentUp ? AppIcons.up : AppIcons.down,
                    size: 14,
                    color:
                        coteWentUp ? AppColors.primaryInk : AppColors.neonRed,
                  ),
                const SizedBox(width: 2),
                Text(coteTotale.toStringAsFixed(3),
                    style: TextStyle(
                        color: prevCombined != null
                            ? (coteWentUp
                                ? AppColors.primaryInk
                                : AppColors.neonRed)
                            : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // ── Section "Quand les cotes changent" ──
        _oddsPolicyTile(),
        const SizedBox(height: 12),
        // ── Solde + Recharger ──
        Row(children: [
          DomeIcon(icon: AppIcons.add, color: AppColors.primary, size: 36),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Solde',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              Text(_walletBalance == null ? '—' : '${_walletBalance!} F',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3)),
            ],
          ),
          const Spacer(),
          Text('Recharger le compte',
              style: TextStyle(
                  color: AppColors.primaryInk,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 2),
          Icon(AppIcons.chevronRight, size: 18, color: AppColors.primaryInk),
        ]),
        const SizedBox(height: 10),
        // ── Code bonus (optionnel) ──
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFFFB020).withValues(alpha: 0.35),
                width: 0.8),
          ),
          child: Row(children: [
            const Icon(Icons.card_giftcard_rounded,
                size: 18, color: Color(0xFFFFB020)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _bonusCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: 'Code bonus (optionnel)',
                  hintStyle: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        // ── Stake input + -/+ + Pari ──
        Row(children: [
          Expanded(
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.divider.withValues(alpha: 0.5),
                    width: 0.5),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _stakeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    cursorColor: AppColors.primaryInk,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _bumpStake(-100),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(AppIcons.remove,
                        size: 18, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _bumpStake(100),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(AppIcons.add,
                        size: 18, color: AppColors.textPrimary),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            width: 130,
            child: _submitting
                ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.primaryInk),
                    ),
                  )
                : ElevatedButton(
                    onPressed: () => _submitWithConfirm(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Pari',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          letterSpacing: 0.3,
                        )),
                  ),
          ),
        ]),
        const SizedBox(height: 4),
        Text('25 F – 2 150 000 F',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        // ── Gains potentiels (en vert) ──
        Row(children: [
          Text('Gains potentiels :',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Text(isCombine ? '$win F' : '$win F (Σ)',
              style: TextStyle(
                  color: AppColors.primaryInk,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2)),
          if (!isCombine && n > 1) ...[
            const Spacer(),
            Text('Total débité : $totalStake F',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ]),
        const SizedBox(height: 14),
        // ── Paris rapides ──
        Text('Paris rapides',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2)),
        const SizedBox(height: 2),
        Text('Choisissez un montant de mise pour placer un pari',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          for (final v in [500, 1000, 2500])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () {
                    _ctrl.setStake(v);
                    _stakeCtrl.text = '$v';
                    _submitWithConfirm(context);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.neonBlue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$v F',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3)),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 2),
      ]),
    );
  }

  List<BetSelection> get _items => _ctrl.items;

  /// Tuile "Quand les cotes changent" : ouvre un menu pour choisir la policy
  Widget _oddsPolicyTile() {
    final policy = _ctrl.oddsPolicy;
    final label = switch (policy) {
      OddsChangePolicy.askConfirm => 'Me demander de confirmer',
      OddsChangePolicy.acceptAll => 'Tout accepter automatiquement',
      OddsChangePolicy.acceptUp => 'Accepter si la cote monte',
      OddsChangePolicy.refuseDown => 'Refuser si la cote baisse',
    };
    return InkWell(
      onTap: _showOddsPolicyDialog,
      borderRadius: BorderRadius.circular(10),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Quand les cotes changent',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2)),
              Text(label,
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Text('Paramètres',
            style: TextStyle(
                color: AppColors.primaryInk,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
        Icon(AppIcons.chevronRight, size: 18, color: AppColors.primaryInk),
      ]),
    );
  }

  Future<void> _showOddsPolicyDialog() async {
    final picked = await showModalBottomSheet<OddsChangePolicy>(
      context: context,
      backgroundColor: AppColors.bgCard,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text('Quand les cotes changent',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              for (final p in OddsChangePolicy.values) _policyOption(ctx, p),
            ]),
          ),
        );
      },
    );
    if (picked != null) _ctrl.setOddsPolicy(picked);
  }

  Widget _policyOption(BuildContext ctx, OddsChangePolicy p) {
    final selected = p == _ctrl.oddsPolicy;
    final (title, hint) = switch (p) {
      OddsChangePolicy.askConfirm => (
          'Me demander de confirmer',
          'Tu valides chaque changement avant de parier'
        ),
      OddsChangePolicy.acceptAll => (
          'Tout accepter automatiquement',
          'Les nouvelles cotes sont appliquees sans demande'
        ),
      OddsChangePolicy.acceptUp => (
          'Accepter si la cote monte',
          'Demande uniquement quand la cote baisse'
        ),
      OddsChangePolicy.refuseDown => (
          'Refuser si la cote baisse',
          'Le pari est refuse en cas de baisse de cote'
        ),
    };
    return InkWell(
      onTap: () => Navigator.pop(ctx, p),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(children: [
          Icon(selected ? AppIcons.radioOn : AppIcons.radioOff,
              color: selected ? AppColors.primaryInk : AppColors.textMuted,
              size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
                Text(hint,
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// Submit qui respecte la policy de changement de cote.
  Future<void> _submitWithConfirm(BuildContext context) async {
    final decision = _ctrl.checkOddsChangePolicy();
    if (decision == 'refuse') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.neonRed,
        duration: const Duration(seconds: 2),
        content: const Text(
            'Pari refusé : la cote a baissé. Modifie ta policy pour accepter.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ));
      return;
    }
    if (decision == 'ask') {
      final accept = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          title: Text('Les cotes ont changé',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15)),
          content: Text(
              'La cote totale de ton combiné est maintenant ×${_ctrl.combinedOdds.toStringAsFixed(3)}.\n\n'
              'Confirmer le pari avec les nouvelles cotes ?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              child: const Text('Accepter',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      );
      if (accept != true) return;
      if (!context.mounted) return;
    }
    _ctrl.ackOddsChanges();
    if (!context.mounted) return;
    await _submit(context);
  }

  // ── Ancien footer (avec mise + cote totale + bouton) ──
  // ignore: unused_element
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
            Icon(AppIcons.savings, size: 18, color: AppColors.neonYellow),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _stakeCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                cursorColor: AppColors.primaryInk,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                color: AppColors.primaryInk.withValues(alpha: 0.3), width: 0.6),
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
              AppColors.primaryInk,
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
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.primaryInk),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: () => _submit(context),
                  icon: const Icon(AppIcons.bets, size: 18),
                  label: Text(
                    'Valider le pari · $totalStake FCFA',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 0.3),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
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
    final res = await _ctrl.submit(bonusCode: _bonusCodeCtrl.text);
    if (!context.mounted) return;
    setState(() => _submitting = false);
    if (res.success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
          content: Row(children: [
            const Icon(AppIcons.checkCircleFilled,
                color: AppColors.onPrimary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pari validé · gain potentiel ${res.potentialPayout} FCFA',
                style: const TextStyle(
                  color: AppColors.onPrimary,
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

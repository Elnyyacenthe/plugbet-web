// ============================================================
// BetsHistoryScreen — Historique des paris (RPC get_my_bets)
// ============================================================
// Charge les 50 derniers paris de l'utilisateur via la RPC
// (RLS user_id = auth.uid()). Pull-to-refresh.
//
// Statut visuel :
//   pending  -> jaune  (en attente du resultat)
//   won      -> vert   (gagne)
//   lost     -> rouge  (perdu)
//   void     -> gris   (annule, remboursement)
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/statpal_service.dart';
import '../theme/app_theme.dart';
import '../utils/bet_live_eval.dart';

class BetsHistoryScreen extends StatefulWidget {
  const BetsHistoryScreen({super.key});

  @override
  State<BetsHistoryScreen> createState() => _BetsHistoryScreenState();
}

class _BetsHistoryScreenState extends State<BetsHistoryScreen>
    with WidgetsBindingObserver {
  List<dynamic> _bets = const [];
  bool _loading = true;
  String? _error;

  // Live tracking : map match_id -> match. Repeuplee toutes les 10s
  // tant que l'ecran est visible et qu'il y a au moins 1 ticket pending.
  Map<String, BettingMatch> _liveById = const {};
  Timer? _livePollTimer;
  static const _pollInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshLive();
    _startLivePolling();
  }

  @override
  void dispose() {
    _livePollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLive();
      _startLivePolling();
    } else if (state == AppLifecycleState.paused) {
      _livePollTimer?.cancel();
    }
  }

  void _startLivePolling() {
    _livePollTimer?.cancel();
    _livePollTimer = Timer.periodic(_pollInterval, (_) => _refreshLive());
  }

  /// Recharge la liste des matchs live (soccer + basket). Silencieux :
  /// une erreur garde le snapshot precedent.
  Future<void> _refreshLive() async {
    try {
      final svc = StatpalService.instance;
      final results = await Future.wait([
        svc.getLiveMatches(sport: Sport.soccer),
        svc.getLiveMatches(sport: Sport.basketball),
      ]);
      if (!mounted) return;
      final map = <String, BettingMatch>{};
      for (final list in results) {
        for (final m in list) {
          map[m.id] = m;
        }
      }
      setState(() => _liveById = map);
    } catch (_) {/* silencieux */}
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client
          .rpc('get_my_bets', params: {'p_limit': 50});
      if (!mounted) return;
      setState(() {
        _bets = res is List ? res : const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _loadAndRefreshLive() async {
    await Future.wait([_load(), _refreshLive()]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text('Mes paris',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            )),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen));
    }
    if (_error != null) return _errorView();
    if (_bets.isEmpty) return _emptyView();
    return RefreshIndicator(
      color: AppColors.neonGreen,
      backgroundColor: AppColors.bgCard,
      onRefresh: _loadAndRefreshLive,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _bets.length,
        itemBuilder: (_, i) => _betCard(_bets[i] as Map<String, dynamic>),
      ),
    );
  }

  Widget _betCard(Map<String, dynamic> bet) {
    final status = bet['status']?.toString() ?? 'pending';
    final betType = bet['bet_type']?.toString() ?? 'simple';
    final stake = (bet['stake'] as num?)?.toInt() ?? 0;
    final totalOdds = (bet['total_odds'] as num?)?.toDouble() ?? 1;
    final payout = (bet['potential_payout'] as num?)?.toInt() ?? 0;
    final actualPayout = (bet['actual_payout'] as num?)?.toInt();
    final isVirtual = (bet['is_virtual'] as bool?) ?? false;
    final createdAt = DateTime.tryParse(bet['created_at']?.toString() ?? '');
    final selections = (bet['selections'] as List?) ?? const [];

    final (statusColor, statusLabel) = _statusVisual(status);

    // ── Live tracking : evaluation par selection + verdict combine ──
    // Seulement pour les tickets encore pending et non-virtuels.
    final List<BetLiveStatus> liveStatuses = [];
    bool anyLive = false;
    if (status == 'pending') {
      for (final sel in selections) {
        final m = sel as Map;
        final selStatus = m['selection_status']?.toString() ?? 'pending';
        if (selStatus != 'pending') {
          liveStatuses.add(BetLiveStatus.unknown);
          continue;
        }
        final matchId = m['match_id']?.toString() ?? '';
        final live = _liveById[matchId];
        if (live == null) {
          liveStatuses.add(BetLiveStatus.unknown);
          continue;
        }
        anyLive = true;
        liveStatuses.add(BetLiveEval.evaluate(
          marketCode: m['market_code']?.toString() ?? '',
          match: live,
        ));
      }
    }
    final combined = (status == 'pending' && anyLive)
        ? BetLiveEval.aggregate(liveStatuses)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 0.6,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: statusColor.withValues(alpha: 0.5), width: 0.5),
            ),
            child: Text(statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                )),
          ),
          const SizedBox(width: 6),
          if (isVirtual)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonPurple,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('VIRT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  )),
            ),
          const SizedBox(width: 6),
          Text(betType == 'combine' ? 'Combiné' : 'Simple',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              )),
          const Spacer(),
          if (combined != null) _liveTicketBadge(combined),
          if (combined != null) const SizedBox(width: 6),
          if (createdAt != null)
            Text(_formatDate(createdAt),
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                )),
        ]),
        const SizedBox(height: 8),
        for (int i = 0; i < selections.length; i++)
          _selectionRow(
            selections[i] as Map,
            liveStatus: liveStatuses.length > i ? liveStatuses[i] : BetLiveStatus.unknown,
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            _statCol('Mise', '$stake FCFA', AppColors.textPrimary),
            const SizedBox(width: 12),
            _statCol('Cote', '×${totalOdds.toStringAsFixed(2)}',
                AppColors.neonYellow),
            const Spacer(),
            _statCol(
              status == 'won' ? 'Gain' : 'Gain potentiel',
              status == 'won' && actualPayout != null
                  ? '$actualPayout FCFA'
                  : '$payout FCFA',
              status == 'won' ? AppColors.neonGreen : AppColors.textPrimary,
              right: true,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _selectionRow(Map sel, {BetLiveStatus liveStatus = BetLiveStatus.unknown}) {
    final status = sel['selection_status']?.toString() ?? 'pending';
    final icon = switch (status) {
      'won' => Icons.check_circle_rounded,
      'lost' => Icons.cancel_rounded,
      'void' => Icons.do_not_disturb_rounded,
      _ => Icons.schedule_rounded,
    };
    final iconColor = switch (status) {
      'won' => AppColors.neonGreen,
      'lost' => AppColors.neonRed,
      'void' => AppColors.textMuted,
      _ => AppColors.neonYellow,
    };
    final odds = (sel['odds'] as num?)?.toDouble();
    // Si le ticket est encore pending et que le match est live, on
    // affiche une seconde ligne avec le score actuel + verdict live.
    final showLive = status == 'pending' &&
        liveStatus != BetLiveStatus.unknown;
    final matchId = sel['match_id']?.toString() ?? '';
    final live = showLive ? _liveById[matchId] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sel['match_label']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
              Text(sel['market_label']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  )),
              if (showLive && live != null) _liveLineSelection(live, liveStatus),
            ],
          ),
        ),
        const SizedBox(width: 6),
        if (odds != null)
          Text('×${odds.toStringAsFixed(2)}',
              style: TextStyle(
                color: AppColors.neonGreen,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              )),
      ]),
    );
  }

  /// 2e ligne sous la selection pending+live : score actuel + verdict.
  Widget _liveLineSelection(BettingMatch m, BetLiveStatus s) {
    final score = '${m.homeScore ?? 0} - ${m.awayScore ?? 0}';
    final minute = m.minute != null ? " ${m.minute}'" : '';
    final (col, label) = _liveStatusVisual(s);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(children: [
        Container(
          width: 5, height: 5,
          decoration: BoxDecoration(
            color: AppColors.neonRed, shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text("LIVE$minute  $score",
            style: TextStyle(
              color: AppColors.neonRed,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            )),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: col.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: col.withValues(alpha: 0.55), width: 0.5),
          ),
          child: Text(label,
              style: TextStyle(
                color: col,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              )),
        ),
      ]),
    );
  }

  /// Badge dans le header du ticket : verdict d'ensemble en live.
  Widget _liveTicketBadge(CombinedLiveStatus c) {
    final Color col;
    final String label;
    if (c.isBust) {
      col = AppColors.neonRed;
      label = 'LIVE · PERDU';
    } else if (c.winning) {
      col = AppColors.neonGreen;
      label = c.hasUnknown ? 'LIVE · OK' : 'LIVE · GAGNE';
    } else {
      col = AppColors.neonRed;
      label = 'LIVE · DERRIERE';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: col.withValues(alpha: 0.55), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
            color: col,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          )),
    );
  }

  (Color, String) _liveStatusVisual(BetLiveStatus s) {
    switch (s) {
      case BetLiveStatus.winning: return (AppColors.neonGreen, 'TU MENES');
      case BetLiveStatus.locked:  return (AppColors.neonGreen, 'ACQUIS');
      case BetLiveStatus.losing:  return (AppColors.neonRed,   'EN RETARD');
      case BetLiveStatus.busted:  return (AppColors.neonRed,   'PERDU LIVE');
      case BetLiveStatus.unknown: return (AppColors.textMuted, '');
    }
  }

  Widget _statCol(String label, String value, Color color, {bool right = false}) {
    return Column(
      crossAxisAlignment:
          right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            )),
        const SizedBox(height: 1),
        Text(value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            )),
      ],
    );
  }

  (Color, String) _statusVisual(String status) {
    switch (status) {
      case 'won':         return (AppColors.neonGreen, 'GAGNÉ');
      case 'lost':        return (AppColors.neonRed, 'PERDU');
      case 'void':        return (AppColors.textMuted, 'ANNULÉ');
      case 'cashed_out':  return (AppColors.neonBlue, 'CASHED OUT');
      default:            return (AppColors.neonYellow, 'EN ATTENTE');
    }
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd/$mm $hh:$mn';
  }

  Widget _emptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.receipt_long_rounded,
              size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Aucun pari',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 6),
          Text('Place ton premier pari dans l\'onglet Paris.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, size: 56, color: AppColors.neonRed),
          const SizedBox(height: 12),
          Text('Erreur',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 6),
          Text(_error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _load,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Reessayer',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    );
  }
}

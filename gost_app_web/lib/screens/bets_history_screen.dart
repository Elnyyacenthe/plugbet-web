// ============================================================
// BetsHistoryScreen — Historique des tickets (refonte 2026-06-11)
// ============================================================
// Source de donnees : RPC get_my_bets_v2 (filtres + pagination).
// Fallback automatique sur get_my_bets v1 si la nouvelle RPC absente.
//
// Fonctionnalites :
//   - Filtres : statut, date, gain min
//   - Recherche : numero de ticket (8 chars prefix) OU equipe
//   - Pagination 50 par page (infinite scroll)
//   - Icone + couleur par sport
//   - Badge statuts : pending, won, lost, void, cashed_out, refunded
//   - Live tracking (preserve l'existant pour tickets pending)
//
// Rétro-compatibilité :
//   - Aucune RPC existante modifiee
//   - Aucune structure DB modifiee
//   - Aucun comportement client supprime
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../services/statpal_service.dart';
import '../services/notification_service.dart';
import '../providers/notification_provider.dart';
import '../theme/app_icons.dart';
import '../theme/app_reliefs.dart';
import '../theme/app_theme.dart';
import '../utils/bet_live_eval.dart';
import 'bet_ticket_detail_screen.dart';
import 'load_coupon_screen.dart';

// ============================================================
// Modeles UI legeres (mapping JSON RPC -> objets typed)
// ============================================================

enum BetStatus { pending, won, lost, voided, cashedOut, refunded, unknown }

BetStatus _parseStatus(String? s) {
  switch (s) {
    case 'pending':     return BetStatus.pending;
    case 'won':         return BetStatus.won;
    case 'lost':        return BetStatus.lost;
    case 'void':        return BetStatus.voided;
    case 'cashed_out':  return BetStatus.cashedOut;
    case 'refunded':    return BetStatus.refunded;
    default:            return BetStatus.unknown;
  }
}

extension on BetStatus {
  String get backendCode {
    switch (this) {
      case BetStatus.pending:    return 'pending';
      case BetStatus.won:        return 'won';
      case BetStatus.lost:       return 'lost';
      case BetStatus.voided:     return 'void';
      case BetStatus.cashedOut:  return 'cashed_out';
      case BetStatus.refunded:   return 'refunded';
      case BetStatus.unknown:    return '';
    }
  }

  // ignore: unused_element
  String get label {
    switch (this) {
      case BetStatus.pending:    return 'EN COURS';
      case BetStatus.won:        return 'GAGNÉ';
      case BetStatus.lost:       return 'PERDU';
      case BetStatus.voided:     return 'ANNULÉ';
      case BetStatus.cashedOut:  return 'CASHOUT';
      case BetStatus.refunded:   return 'REMBOURSÉ';
      case BetStatus.unknown:    return '—';
    }
  }
}

// ignore: unused_element
Color _statusColor(BetStatus s) {
  switch (s) {
    case BetStatus.pending:    return AppColors.neonYellow;
    case BetStatus.won:        return AppColors.primaryInk;
    case BetStatus.lost:       return AppColors.neonRed;
    case BetStatus.voided:     return AppColors.textMuted;
    case BetStatus.cashedOut:  return AppColors.neonBlue;
    case BetStatus.refunded:   return AppColors.neonPurple;
    case BetStatus.unknown:    return AppColors.textMuted;
  }
}

// ============================================================
// Sport detection (depuis match_label ou virtual flag)
// ============================================================
enum DisplaySport { footballReal, basketballReal, footballVirtual, basketballVirtual, tennisVirtual, raceVirtual, greyhoundVirtual, unknown }

extension on DisplaySport {
  IconData get icon {
    switch (this) {
      case DisplaySport.footballReal:
      case DisplaySport.footballVirtual:   return AppIcons.football;
      case DisplaySport.basketballReal:
      case DisplaySport.basketballVirtual: return AppIcons.basketball;
      case DisplaySport.tennisVirtual:     return AppIcons.tennis;
      case DisplaySport.raceVirtual:       return AppIcons.raceCar;
      case DisplaySport.greyhoundVirtual:  return AppIcons.greyhound;
      case DisplaySport.unknown:           return AppIcons.sportUnknown;
    }
  }

  // ignore: unused_element
  Color get color {
    switch (this) {
      case DisplaySport.footballReal:      return AppColors.primaryInk;
      case DisplaySport.footballVirtual:   return AppColors.neonPurple;
      case DisplaySport.basketballReal:    return AppColors.neonYellow;
      case DisplaySport.basketballVirtual: return AppColors.neonBlue;
      case DisplaySport.tennisVirtual:     return AppColors.primaryInk;
      case DisplaySport.raceVirtual:       return AppColors.neonRed;
      case DisplaySport.greyhoundVirtual:  return AppColors.neonYellow;
      case DisplaySport.unknown:           return AppColors.textMuted;
    }
  }

  // ignore: unused_element
  String get label {
    switch (this) {
      case DisplaySport.footballReal:      return 'FOOTBALL';
      case DisplaySport.basketballReal:    return 'BASKET';
      case DisplaySport.footballVirtual:   return 'FOOTBALL FLASH';
      case DisplaySport.basketballVirtual: return 'BASKET FLASH';
      case DisplaySport.tennisVirtual:     return 'TENNIS FLASH';
      case DisplaySport.raceVirtual:       return 'COURSE FLASH';
      case DisplaySport.greyhoundVirtual:  return 'GREYHOUND FLASH';
      case DisplaySport.unknown:           return 'SPORT';
    }
  }
}

DisplaySport _detectSport(List selections, bool isVirtual) {
  if (selections.isEmpty) return DisplaySport.unknown;
  final first = selections.first as Map?;
  final label = (first?['match_label']?.toString() ?? '').toLowerCase();
  // Heuristiques sur le nom du match - simple mais marche en pratique
  if (label.contains('tennis')) {
    return isVirtual ? DisplaySport.tennisVirtual : DisplaySport.unknown;
  }
  if (label.contains('greyhound') || label.contains('levrier')) {
    return DisplaySport.greyhoundVirtual;
  }
  if (label.contains('course') || label.contains('race') || label.contains('grand prix')) {
    return DisplaySport.raceVirtual;
  }
  // Soccer vs basket par mots-cles courants
  final bool isBasket = label.contains('nba') ||
      label.contains('lakers') || label.contains('celtics') ||
      label.contains('knicks') || label.contains('warriors') ||
      label.contains('spurs') || label.contains('rockets');
  if (isBasket) {
    return isVirtual ? DisplaySport.basketballVirtual : DisplaySport.basketballReal;
  }
  return isVirtual ? DisplaySport.footballVirtual : DisplaySport.footballReal;
}

// ============================================================
// Ecran
// ============================================================

class BetsHistoryScreen extends StatefulWidget {
  const BetsHistoryScreen({super.key});

  @override
  State<BetsHistoryScreen> createState() => _BetsHistoryScreenState();
}

class _BetsHistoryScreenState extends State<BetsHistoryScreen>
    with WidgetsBindingObserver {
  // Donnees
  final List<dynamic> _bets = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _totalCount = 0;
  String? _error;

  // Filtres
  BetStatus? _filterStatus;
  DateTime? _filterDateFrom;
  DateTime? _filterDateTo;
  int? _filterMinPayout;
  String _searchQuery = '';
  Timer? _searchDebouncer;
  final _searchCtrl = TextEditingController();

  // Pagination
  static const int _pageSize = 30;
  int _offset = 0;

  // Live tracking (preserve)
  Map<String, BettingMatch> _liveById = const {};

  // Detection des reglements 2Up pour notifier "Ton pari est deja gagne".
  final Set<String> _known2UpBetIds = {};
  bool _seeded2Up = false;
  Timer? _livePollTimer;
  static const _pollInterval = Duration(seconds: 10);

  // Scroll
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _load(reset: true);
    _refreshLive();
    _startLivePolling();
  }

  @override
  void dispose() {
    _livePollTimer?.cancel();
    _searchDebouncer?.cancel();
    _searchCtrl.dispose();
    _scrollController.dispose();
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

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_loadingMore && _hasMore) _loadMore();
    }
  }

  void _startLivePolling() {
    _livePollTimer?.cancel();
    _livePollTimer = Timer.periodic(_pollInterval, (_) => _refreshLive());
  }

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

  /// Charge la 1ere page (avec filtres courants). Reset = vide la liste.
  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
        _hasMore = true;
        _bets.clear();
      });
    } else {
      setState(() => _loading = true);
    }
    try {
      final page = await _fetchPage(limit: _pageSize, offset: 0);
      if (!mounted) return;
      _detect2UpSettlements(page.items);
      setState(() {
        _bets
          ..clear()
          ..addAll(page.items);
        _totalCount = page.total;
        _hasMore = page.hasMore;
        _offset = page.items.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Detecte les tickets nouvellement regles via 2Up et notifie l'utilisateur
  /// ("Ton pari est deja gagne !"). Ne notifie pas au tout premier chargement
  /// (seed) pour eviter les alertes retroactives sur d'anciens paris.
  void _detect2UpSettlements(List<dynamic> items) {
    final current = <String>{};
    for (final b in items) {
      if (b is Map &&
          b['settled_via_2up'] == true &&
          b['status']?.toString() == 'won') {
        current.add(b['id']?.toString() ?? '');
      }
    }
    current.remove('');
    if (!_seeded2Up) {
      _known2UpBetIds.addAll(current);
      _seeded2Up = true;
      return;
    }
    final fresh = current.difference(_known2UpBetIds);
    _known2UpBetIds.addAll(current);
    if (fresh.isEmpty) return;
    // Notification in-app (feed)
    try {
      context.read<NotificationProvider>().add(
            title: 'Ton pari est déjà gagné ! 🎉',
            body: 'Réglé gagnant en avance grâce au 2Up.',
            icon: AppIcons.checkCircleFilled,
            color: AppColors.primary,
          );
    } catch (_) {/* provider absent : ignore */}
    // Notification OS locale
    NotificationService.instance.showPushNotification(
      title: 'Ton pari est déjà gagné ! 🎉',
      body: 'Un de tes paris a été réglé gagnant en avance grâce au 2Up.',
      payload: '2up',
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchPage(limit: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        _bets.addAll(page.items);
        _totalCount = page.total;
        _hasMore = page.hasMore;
        _offset += page.items.length;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// Fetch une page via la RPC v2 (filtres + pagination).
  /// Fallback automatique sur v1 si v2 absente (compat zero-risque).
  Future<_BetsPage> _fetchPage({required int limit, required int offset}) async {
    final c = Supabase.instance.client;
    final params = <String, dynamic>{
      'p_limit': limit,
      'p_offset': offset,
    };
    if (_filterStatus != null) {
      params['p_status'] = _filterStatus!.backendCode;
    }
    if (_filterDateFrom != null) {
      params['p_date_from'] = _filterDateFrom!.toIso8601String();
    }
    if (_filterDateTo != null) {
      params['p_date_to'] = _filterDateTo!.toIso8601String();
    }
    if (_filterMinPayout != null) {
      params['p_min_payout'] = _filterMinPayout;
    }
    if (_searchQuery.trim().isNotEmpty) {
      params['p_search'] = _searchQuery.trim();
    }
    try {
      final res = await c.rpc('get_my_bets_v2', params: params);
      if (res is Map) {
        final items = (res['items'] as List?) ?? const [];
        final total = (res['total'] as num?)?.toInt() ?? items.length;
        final hasMore = res['has_more'] as bool? ?? false;
        return _BetsPage(items: items, total: total, hasMore: hasMore);
      }
      return const _BetsPage(items: [], total: 0, hasMore: false);
    } catch (e) {
      // Fallback v1 (sans filtres ni pagination) - tolerance pannique
      if (offset == 0 && _filterStatus == null && _searchQuery.isEmpty &&
          _filterDateFrom == null && _filterDateTo == null && _filterMinPayout == null) {
        final res = await c.rpc('get_my_bets', params: {'p_limit': limit});
        final items = res is List ? res : const [];
        return _BetsPage(items: items, total: items.length, hasMore: false);
      }
      rethrow;
    }
  }

  // ── Filtres handlers ──
  void _setFilterStatus(BetStatus? s) {
    setState(() => _filterStatus = s);
    _load(reset: true);
  }

  void _setFilterMinPayout(int? v) {
    setState(() => _filterMinPayout = v);
    _load(reset: true);
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now(),
      initialDateRange: (_filterDateFrom != null && _filterDateTo != null)
          ? DateTimeRange(start: _filterDateFrom!, end: _filterDateTo!)
          : null,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.primaryInk,
            onPrimary: AppColors.onPrimary,
            surface: AppColors.bgCard,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (range == null) return;
    setState(() {
      _filterDateFrom = DateTime(range.start.year, range.start.month, range.start.day);
      _filterDateTo = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);
    });
    _load(reset: true);
  }

  void _clearDateRange() {
    setState(() {
      _filterDateFrom = null;
      _filterDateTo = null;
    });
    _load(reset: true);
  }

  void _onSearchChanged(String v) {
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _searchQuery = v);
      _load(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: ReliefAppBar(
        title: 'Mes paris',
        actions: [
          IconButton(
            icon: Icon(AppIcons.qrCode,
                color: AppColors.primaryInk, size: 22),
            tooltip: 'Charger un coupon',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LoadCouponScreen(),
              ));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          _searchBar(),
          _filtersBar(),
          if (_totalCount > 0) _resultsCount(),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Row(children: [
          Icon(AppIcons.search, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Numéro ticket ou équipe…',
                hintStyle: TextStyle(
                  color: AppColors.textMuted, fontSize: 12,
                  fontWeight: FontWeight.w500),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                _onSearchChanged('');
              },
              child: Icon(AppIcons.close,
                  size: 16, color: AppColors.textMuted),
            ),
        ]),
      ),
    );
  }

  Widget _filtersBar() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _filterChip(
            label: 'Tous',
            selected: _filterStatus == null,
            onTap: () => _setFilterStatus(null),
          ),
          _filterChip(
            label: 'En cours',
            color: AppColors.neonYellow,
            selected: _filterStatus == BetStatus.pending,
            onTap: () => _setFilterStatus(BetStatus.pending),
          ),
          _filterChip(
            label: 'Gagnés',
            color: AppColors.primaryInk,
            selected: _filterStatus == BetStatus.won,
            onTap: () => _setFilterStatus(BetStatus.won),
          ),
          _filterChip(
            label: 'Perdus',
            color: AppColors.neonRed,
            selected: _filterStatus == BetStatus.lost,
            onTap: () => _setFilterStatus(BetStatus.lost),
          ),
          _filterChip(
            label: 'Annulés',
            color: AppColors.textMuted,
            selected: _filterStatus == BetStatus.voided,
            onTap: () => _setFilterStatus(BetStatus.voided),
          ),
          // Separateur
          Container(
            width: 1, height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            color: AppColors.divider,
          ),
          _filterChip(
            label: _filterDateFrom != null && _filterDateTo != null
                ? '${_fmtDateShort(_filterDateFrom!)}→${_fmtDateShort(_filterDateTo!)}'
                : 'Date',
            icon: AppIcons.calendar,
            selected: _filterDateFrom != null,
            onTap: _pickDateRange,
            onLongPress: _filterDateFrom != null ? _clearDateRange : null,
          ),
          _filterChip(
            label: _filterMinPayout != null
                ? '≥ ${_filterMinPayout}F'
                : 'Gain min',
            icon: AppIcons.card,
            selected: _filterMinPayout != null,
            onTap: _showMinPayoutDialog,
            onLongPress: _filterMinPayout != null
                ? () => _setFilterMinPayout(null)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    Color? color,
    IconData? icon,
    VoidCallback? onLongPress,
  }) {
    final accent = color ?? AppColors.primaryInk;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : AppColors.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? accent
                  : AppColors.divider.withValues(alpha: 0.4),
              width: selected ? 1.2 : 0.5,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: selected ? accent : AppColors.textMuted),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                  color: selected ? accent : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                )),
          ]),
        ),
      ),
    );
  }

  Future<void> _showMinPayoutDialog() async {
    int? selected = _filterMinPayout;
    final values = [1000, 5000, 10000, 50000, 100000];
    final result = await showDialog<int?>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Gain potentiel minimum',
            style: TextStyle(
              color: AppColors.textPrimary, fontSize: 14,
              fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            dense: true,
            title: Text('Aucun filtre',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            onTap: () => Navigator.pop(ctx, -1),
          ),
          for (final v in values)
            ListTile(
              dense: true,
              title: Text('≥ $v FCFA',
                  style: TextStyle(
                    color: selected == v
                        ? AppColors.primaryInk
                        : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(ctx, v),
            ),
        ]),
      ),
    );
    if (result == null) return;
    _setFilterMinPayout(result == -1 ? null : result);
  }

  Widget _resultsCount() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(children: [
        Text('$_totalCount ticket${_totalCount > 1 ? 's' : ''}',
            style: TextStyle(
              color: AppColors.textMuted, fontSize: 11,
              fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _body() {
    if (_loading && _bets.isEmpty) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.primaryInk));
    }
    if (_error != null) return _errorView();
    if (_bets.isEmpty) return _emptyView();
    return RefreshIndicator(
      color: AppColors.primaryInk,
      backgroundColor: AppColors.bgCard,
      onRefresh: () async {
        await Future.wait([_load(reset: true), _refreshLive()]);
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: _bets.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _bets.length) return _loadMoreFooter();
          return _betCard(_bets[i] as Map<String, dynamic>);
        },
      ),
    );
  }

  Widget _loadMoreFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _loadingMore
            ? SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                  color: AppColors.primaryInk, strokeWidth: 2.2),
              )
            : Text('Faites défiler pour charger plus',
                style: TextStyle(
                  color: AppColors.textMuted, fontSize: 11,
                  fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _betCard(Map<String, dynamic> bet) {
    final betId = bet['id']?.toString() ?? '';
    final status = _parseStatus(bet['status']?.toString());
    final betType = bet['bet_type']?.toString() ?? 'simple';
    final stake = (bet['stake'] as num?)?.toInt() ?? 0;
    final totalOdds = (bet['total_odds'] as num?)?.toDouble() ?? 1;
    final payout = (bet['potential_payout'] as num?)?.toInt() ?? 0;
    final actualPayout = (bet['actual_payout'] as num?)?.toInt();
    final isVirtual = (bet['is_virtual'] as bool?) ?? false;
    final createdAt = DateTime.tryParse(bet['created_at']?.toString() ?? '');
    final selections = (bet['selections'] as List?) ?? const [];
    final sport = _detectSport(selections, isVirtual);
    // 2Up : reglement anticipe (paiement avant la fin du match).
    final via2Up = bet['settled_via_2up'] == true;
    final score2Up = bet['settled_at_score']?.toString();

    // ── Live tracking : evaluation par selection + verdict combine ──
    // Preserve exactement le comportement de la v1.
    final List<BetLiveStatus> liveStatuses = [];
    bool anyLive = false;
    if (status == BetStatus.pending) {
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
    final combined = (status == BetStatus.pending && anyLive)
        ? BetLiveEval.aggregate(liveStatuses)
        : null;

    // Detect le sport principal (1ere selection) pour le badge competition
    final firstSel = selections.isNotEmpty ? selections.first as Map : null;
    final firstMatchId = firstSel?['match_id']?.toString() ?? '';
    final liveMatch = _liveById[firstMatchId];
    final competition = _detectCompetitionShort(
        firstSel?['match_label']?.toString() ?? '',
        liveMatch, isVirtual);
    final isLiveTicket = anyLive ||
        (firstSel != null && (firstSel['is_live'] as bool? ?? false));
    final showActual = status == BetStatus.won ||
        status == BetStatus.refunded ||
        status == BetStatus.voided ||
        status == BetStatus.cashedOut;
    final displayPayout = showActual
        ? (actualPayout ?? (status == BetStatus.won ? payout : stake))
        : payout;
    final (badgeColor, badgeLabel, badgeIcon) = switch (status) {
      BetStatus.won       => (AppColors.primaryInk, 'Gagné',     AppIcons.checkCircleFilled),
      BetStatus.lost      => (AppColors.neonRed,   'Perdu',     AppIcons.cancel),
      BetStatus.voided    => (AppColors.neonPurple,'Remboursé', AppIcons.blocked),
      BetStatus.refunded  => (AppColors.neonPurple,'Remboursé', AppIcons.card),
      BetStatus.cashedOut => (AppColors.neonBlue,  'Encaissé',  AppIcons.card),
      _                   => (AppColors.neonBlue,  'Accepté',   AppIcons.checkCircleFilled),
    };
    // Label statut : "Gagné via 2Up" si le ticket a ete regle en anticipe.
    final statusLabel =
        (status == BetStatus.won && via2Up) ? 'Gagné · 2Up' : badgeLabel;

    return GestureDetector(
      onTap: () => _openDetail(bet),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ── Ligne 1 : date + badge En direct + icones notif/menu ──
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Row(children: [
                if (createdAt != null)
                  Text(_formatDateLong(createdAt),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      )),
                const SizedBox(width: 8),
                if (isLiveTicket)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.neonRed,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('En direct',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4)),
                  )
                else if (combined != null) _liveTicketBadge(combined),
              ]),
            ),
            Icon(AppIcons.notification,
                size: 18, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Icon(AppIcons.more,
                size: 18, color: AppColors.textMuted),
          ]),
          const SizedBox(height: 6),
          // ── Ligne 2 : badge competition / sport / virtuel ──
          Row(children: [
            _competitionPill(competition, sport, isVirtual),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(3),
              ),
              child: GestureDetector(
                onLongPress: () =>
                    _copyToClipboard(betId, 'Numéro de ticket'),
                child: Text(_shortId(betId),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ),
            if (via2Up) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      width: 0.5),
                ),
                child: Text(
                  (score2Up != null && score2Up.isNotEmpty)
                      ? '2UP · $score2Up'
                      : '2UP',
                  style: TextStyle(
                    color: AppColors.primaryInk,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          // ── Lignes tabulees : Type + Cote, Mise, Gains potentiels ──
          _tableRow(
            label: betType == 'combine'
                ? 'Combiné · ${selections.length}'
                : 'Simple',
            value: totalOdds.toStringAsFixed(2),
            valueBold: true,
          ),
          const SizedBox(height: 4),
          _tableRow(
            label: 'Mise :',
            value: '$stake F',
          ),
          const SizedBox(height: 4),
          // Gains potentiels + badge statut
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(
                showActual && status != BetStatus.lost
                    ? (status == BetStatus.won
                        ? 'Gain réel :'
                        : 'Remboursé :')
                    : 'Gains potentiels :',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(
                status == BetStatus.lost ? '— F' : '$displayPayout F',
                style: TextStyle(
                  color: status == BetStatus.won
                      ? AppColors.primaryInk
                      : (status == BetStatus.lost
                          ? AppColors.textMuted
                          : AppColors.textPrimary),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2)),
            const Spacer(),
            // Badge statut
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(badgeIcon, size: 12, color: badgeColor),
                const SizedBox(width: 4),
                Text(statusLabel,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }

  /// Petite ligne label gauche + value droite (style historique 1xBet).
  Widget _tableRow({required String label, required String value,
      bool valueBold = false}) {
    return Row(children: [
      Text(label,
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700)),
      const Spacer(),
      Text(value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: valueBold ? 14 : 13,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2)),
    ]);
  }

  /// Badge competition style 1XCHAMPIONS (bleu) + icone sport.
  Widget _competitionPill(String label, DisplaySport sport, bool isVirtual) {
    final color = isVirtual ? AppColors.neonPurple : AppColors.neonBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(sport.icon, size: 10, color: Colors.white),
        const SizedBox(width: 4),
        Text(label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5)),
      ]),
    );
  }

  String _detectCompetitionShort(String matchLabel, BettingMatch? live, bool isVirtual) {
    if (isVirtual) return 'FLASH';
    if (live != null && live.league.isNotEmpty) {
      // Tronque pour rester sur 1 ligne
      final l = live.league.toUpperCase();
      return l.length > 20 ? l.substring(0, 20) : l;
    }
    final lower = matchLabel.toLowerCase();
    if (lower.contains('nba')) return 'NBA';
    if (lower.contains('coupe du monde') || lower.contains('world cup')) {
      return 'WORLD CUP';
    }
    if (lower.contains('champions')) return 'CHAMPIONS';
    return 'FOOTBALL';
  }

  /// Format "29.04.2025 (20:38)" comme dans le screenshot 1xBet.
  String _formatDateLong(DateTime dt) {
    final l = dt.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final yy = l.year.toString();
    final hh = l.hour.toString().padLeft(2, '0');
    final mn = l.minute.toString().padLeft(2, '0');
    return '$dd.$mm.$yy ($hh:$mn)';
  }

  void _openDetail(Map<String, dynamic> bet) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BetTicketDetailScreen(
        bet: bet,
        liveById: _liveById,
      ),
    ));
  }

  // ignore: unused_element
  Widget _selectionRow(Map sel, {BetLiveStatus liveStatus = BetLiveStatus.unknown}) {
    final status = sel['selection_status']?.toString() ?? 'pending';
    final (icon, iconColor) = switch (status) {
      'won'  => (AppIcons.checkCircleFilled, AppColors.primaryInk),
      'lost' => (AppIcons.cancel, AppColors.neonRed),
      'void' => (AppIcons.blocked, AppColors.textMuted),
      _      => (AppIcons.clock, AppColors.neonYellow),
    };
    final odds = (sel['odds'] as num?)?.toDouble();
    final showLive = status == 'pending' &&
        liveStatus != BetLiveStatus.unknown;
    final matchId = sel['match_id']?.toString() ?? '';
    final live = showLive ? _liveById[matchId] : null;
    final matchLabel = sel['match_label']?.toString() ?? '';
    final marketLabel = sel['market_label']?.toString() ?? '';
    final isLive = (sel['is_live'] as bool?) ?? false;

    // Parse "Home vs Away" pour afficher proprement
    final teams = _parseTeams(matchLabel);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Icone statut
        Container(
          margin: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 8),
        // Bloc texte (equipes + market + live)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ligne 1 : equipes (mises en valeur)
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    letterSpacing: -0.1, height: 1.2,
                  ),
                  children: [
                    TextSpan(text: teams.home,
                        style: TextStyle(color: AppColors.textPrimary)),
                    TextSpan(text: '  vs  ',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        )),
                    TextSpan(text: teams.away,
                        style: TextStyle(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              // Ligne 2 : market_label + badge live si applicable
              Row(children: [
                Flexible(
                  child: Text(marketLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                if (isLive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.neonRed,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                          color: Colors.white, fontSize: 8,
                          fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  ),
                ],
              ]),
              if (showLive && live != null) _liveLineSelection(live, liveStatus),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Cote a droite (proeminente)
        if (odds != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('×${odds.toStringAsFixed(2)}',
                style: TextStyle(
                  color: iconColor,
                  fontSize: 12, fontWeight: FontWeight.w900,
                  letterSpacing: -0.1)),
          ),
      ]),
    );
  }

  /// Parse "Home vs Away" / "Home - Away" / "Home VS Away" -> (home, away)
  ({String home, String away}) _parseTeams(String label) {
    final patterns = [
      RegExp(r'\s+vs\.?\s+', caseSensitive: false),
      RegExp(r'\s+-\s+'),
      RegExp(r'\s+contre\s+', caseSensitive: false),
    ];
    for (final p in patterns) {
      final parts = label.split(p);
      if (parts.length == 2) {
        return (home: parts[0].trim(), away: parts[1].trim());
      }
    }
    return (home: label, away: '');
  }

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
              color: AppColors.neonRed, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text("LIVE$minute  $score",
            style: TextStyle(
              color: AppColors.neonRed,
              fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
        const SizedBox(width: 8),
        if (label.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: col.withValues(alpha: 0.55), width: 0.5),
            ),
            child: Text(label,
                style: TextStyle(
                  color: col, fontSize: 9,
                  fontWeight: FontWeight.w900, letterSpacing: 0.4)),
          ),
      ]),
    );
  }

  Widget _liveTicketBadge(CombinedLiveStatus c) {
    final Color col;
    final String label;
    if (c.isBust) {
      col = AppColors.neonRed;
      label = 'LIVE · PERDU';
    } else if (c.winning) {
      col = AppColors.primaryInk;
      label = c.hasUnknown ? 'LIVE · OK' : 'LIVE · GAGNÉ';
    } else {
      col = AppColors.neonRed;
      label = 'LIVE · DERRIÈRE';
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
            color: col, fontSize: 9,
            fontWeight: FontWeight.w900, letterSpacing: 0.4)),
    );
  }

  (Color, String) _liveStatusVisual(BetLiveStatus s) {
    switch (s) {
      case BetLiveStatus.winning: return (AppColors.primaryInk, 'TU MÈNES');
      case BetLiveStatus.locked:  return (AppColors.primaryInk, 'ACQUIS');
      case BetLiveStatus.losing:  return (AppColors.neonRed,   'EN RETARD');
      case BetLiveStatus.busted:  return (AppColors.neonRed,   'PERDU LIVE');
      case BetLiveStatus.unknown: return (AppColors.textMuted, '');
    }
  }

  String _shortId(String id) {
    if (id.isEmpty) return '——';
    // 8 derniers chars en MAJUSCULE -> lisible et copiable
    final s = id.replaceAll('-', '');
    return '#${s.substring(s.length - 8).toUpperCase()}';
  }

  String _fmtDateShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  Future<void> _copyToClipboard(String text, String label) async {
    // Note : on n'importe pas services.dart - le SnackBar suffit pour info
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.bgElevated,
        duration: const Duration(milliseconds: 1200),
        content: Text('$label : $text',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
      ),
    );
  }

  Widget _emptyView() {
    final hasFilters = _filterStatus != null ||
        _filterDateFrom != null || _filterMinPayout != null ||
        _searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(AppIcons.receipt,
              size: 56, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(hasFilters ? 'Aucun ticket trouvé' : 'Aucun pari',
              style: TextStyle(
                color: AppColors.textPrimary, fontSize: 15,
                fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              hasFilters
                  ? 'Essaie d\'élargir les filtres'
                  : 'Place ton premier pari dans l\'onglet Paris.',
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
          Icon(AppIcons.warning, size: 56, color: AppColors.neonRed),
          const SizedBox(height: 12),
          Text('Erreur',
              style: TextStyle(
                color: AppColors.textPrimary, fontSize: 15,
                fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _load(reset: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Réessayer',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ]),
      ),
    );
  }
}

class _BetsPage {
  final List<dynamic> items;
  final int total;
  final bool hasMore;
  const _BetsPage({
    required this.items,
    required this.total,
    required this.hasMore,
  });
}

// ============================================================
// BettingScreen — Onglet "Paris" (theme Plugbet)
// ============================================================
// Layout :
//   Header     : "Paris" + badge live
//   Tabs sport : Football / Basket
//   Searchbar  : "Grands évènements"
//   Chips      : Tous | Live | Favoris
//   Liste      : matchs groupes par ligue (sections collapsibles)
//   Pill       : panier flottant en bas (apparait des 1 selection)
//
// Polling : 10s sur live uniquement (cf onResume).
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart';
import '../services/team_logo_service.dart';
import '../services/virtual_match_service.dart';
import '../state/bet_slip_controller.dart';
import '../widgets/betting_match_card.dart';
import '../widgets/bet_slip.dart';
import 'betting_match_detail_screen.dart';
import 'virtual_matches_screen.dart';
import 'bets_history_screen.dart';
import '../utils/market_labels.dart';

class BettingScreen extends StatefulWidget {
  const BettingScreen({super.key});

  @override
  State<BettingScreen> createState() => _BettingScreenState();
}

enum _Filter { tous, live, favoris }

class _BettingScreenState extends State<BettingScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _svc = StatpalService.instance;
  final _searchCtrl = TextEditingController();
  late final TabController _sportTab;

  // Caches locaux : on garde matchs par sport.
  final Map<Sport, List<BettingMatch>> _live = {};
  final Map<Sport, List<BettingMatch>> _today = {};
  final Set<String> _favorites = {};
  final Set<String> _collapsedLeagues = {};       // leagues fermees
  final Set<String> _prefetchedLeagueIds = {};    // odds fetched OK
  final Set<String> _loadingLeagueIds = {};       // fetch en cours

  _Filter _filter = _Filter.tous;
  String _query = '';
  // Date selectionnee dans le calendrier horizontal. null = "Tous les jours"
  // (cf bouton CDM qui veut voir toutes les dates qui contiennent 'world').
  DateTime? _selectedDate = _dateOnly(DateTime.now());
  static const int _daysAhead = 14;

  static DateTime _dateOnly(DateTime dt) {
    final l = dt.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  static String _formatDateFr(DateTime d) {
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    final today = _dateOnly(DateTime.now());
    if (d == today) return 'aujourd\'hui';
    if (d == today.add(const Duration(days: 1))) return 'demain';
    return 'le ${d.day} ${months[d.month - 1]}';
  }
  // Plus de loader local : le splash a deja prefetch matchs + cotes + logos
  // dans les caches singleton (StatpalService + TeamLogoService).
  // Au mount, la 1ere lecture est un cache-hit instantane.
  String? _error;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  static const _pollInterval = Duration(seconds: 10);
  // Coup d'envoi Coupe du Monde 2026 : 11 juin 2026, 20h locale (USA)
  // Approximation UTC : 20h ET = 00h UTC le 12 juin
  static final DateTime _worldCupKickoff =
      DateTime.utc(2026, 6, 12, 0, 0, 0);

  Sport get _sport => Sport.values[_sportTab.index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sportTab = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_sportTab.indexIsChanging) {
          setState(() {});
          _loadCurrentSport();
        }
      });
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    // Tick countdown CDM toutes les secondes (rebuild leger du banner)
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Lance le service de matchs virtuels en background : on l'utilise
    // pour le compteur live de la card d'entree + l'ecran dedie.
    VirtualMatchService.instance.start();
    _initialLoad();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _searchCtrl.dispose();
    _sportTab.dispose();
    VirtualMatchService.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLive();
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
    }
  }

  /// Charge initial : tout passe par le cache prechauffe au splash.
  /// AUCUN loader local affiche ; si cache vide (cas edge : splash skipped),
  /// l'ecran montre un empty-state pendant que les fetchs arrivent en BG.
  Future<void> _initialLoad() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        _svc.getLiveMatches(sport: _sport),
        _svc.getTodayMatches(sport: _sport),
      ]);
      if (!mounted) return;
      setState(() {
        _live[_sport] = results[0];
        _today[_sport] = results[1];
      });
      // Cotes + logos en background (cache splash -> hit immediat la plupart
      // du temps, sinon arrive progressivement via setState).
      unawaited(_prefetchOdds(_sport));
      _prefetchLogos();
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// Lance la resolution des logos en background pour tous les matchs charges.
  /// Les widgets BetTeamCrest se rebuild automatiquement via listener du service.
  void _prefetchLogos() {
    final allMatches = [
      ...(_live[_sport] ?? const <BettingMatch>[]),
      ...(_today[_sport] ?? const <BettingMatch>[]),
    ];
    final seen = <String>{};
    final logoSvc = TeamLogoService.instance;
    for (final m in allMatches) {
      if (seen.add('${m.sport.name}:${m.homeName}')) {
        logoSvc.prefetch(m.homeName, m.sport);
      }
      if (seen.add('${m.sport.name}:${m.awayName}')) {
        logoSvc.prefetch(m.awayName, m.sport);
      }
    }
  }

  Future<void> _loadCurrentSport({bool showSpinner = false}) async {
    // Aucun spinner local : le splash a deja chauffe les caches des 2 sports.
    // Le parametre est conserve pour compat mais ignore.
    try {
      final results = await Future.wait([
        _svc.getLiveMatches(sport: _sport),
        _svc.getTodayMatches(sport: _sport),
      ]);
      if (!mounted) return;
      setState(() {
        _live[_sport] = results[0];
        _today[_sport] = results[1];
        _error = null;
      });
      unawaited(_prefetchOdds(_sport));
      _prefetchLogos();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// Charge les cotes (prematch + live) et enrichit les matchs.
  /// - Prematch : 1 appel par ligue, limite a 15 ligues (les plus chargees)
  /// - Live     : 1 seul appel /{sport}/odds/live -> tous les matchs en cours
  Future<void> _prefetchOdds(Sport sport) async {
    // NBA / basketball : les cotes sont DEJA embarquees dans la reponse
    // /nba/odds parsee par _fetchDaily. Aucun prefetch supplementaire.
    if (sport == Sport.basketball) return;

    // ── 1) LIVE : 1 seul appel, applique a tous les matchs live ──
    unawaited(_prefetchLiveOdds(sport));

    // ── 2) PREMATCH : par ligue (15 plus grosses) - EN PARALLELE ──
    // Auparavant : sequentiel (lent : N*latence). Maintenant : Future.wait
    // -> wall-clock = max(latences) au lieu de sum(latences).
    final upcoming = [..._today[sport] ?? const <BettingMatch>[]];
    final byLeague = <String, List<int>>{};
    for (var i = 0; i < upcoming.length; i++) {
      final lid = upcoming[i].leagueId;
      if (lid != null && lid.isNotEmpty) {
        byLeague.putIfAbsent(lid, () => []).add(i);
      }
    }
    final entries = byLeague.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final toFetch = entries.take(15).toList();
    if (toFetch.isEmpty) return;

    setState(() {
      for (final e in toFetch) {
        _loadingLeagueIds.add(e.key);
      }
    });

    // Fetch toutes les ligues en parallele, applique au fur et a mesure
    // que chaque promesse se resout (UI reactive)
    await Future.wait(toFetch.map((entry) async {
      try {
        final oddsMap = await _svc.getLeagueOdds(entry.key, sport: sport);
        if (!mounted || _sport != sport) return;
        setState(() {
          _loadingLeagueIds.remove(entry.key);
          _prefetchedLeagueIds.add(entry.key);
          final list = _today[sport];
          if (list == null) return;
          final updated = [...list];
          for (final idx in entry.value) {
            final m = updated[idx];
            final odds = oddsMap[m.id];
            if (odds != null) updated[idx] = m.copyWith(odds: odds);
          }
          _today[sport] = updated;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _loadingLeagueIds.remove(entry.key));
      }
    }));
  }

  /// Prefetch des cotes pour une ligue specifique (a la demande quand
  /// l'utilisateur scrolle vers une section pas encore chargee).
  Future<void> _prefetchLeagueOddsLazy(String leagueId) async {
    if (_prefetchedLeagueIds.contains(leagueId)) return;
    if (_loadingLeagueIds.contains(leagueId)) return;
    setState(() => _loadingLeagueIds.add(leagueId));
    try {
      final oddsMap = await _svc.getLeagueOdds(leagueId, sport: _sport);
      if (!mounted) return;
      setState(() {
        _loadingLeagueIds.remove(leagueId);
        _prefetchedLeagueIds.add(leagueId);
        final list = _today[_sport];
        if (list == null) return;
        final updated = [
          for (final m in list)
            (m.leagueId == leagueId && oddsMap[m.id] != null)
                ? m.copyWith(odds: oddsMap[m.id]!)
                : m,
        ];
        _today[_sport] = updated;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLeagueIds.remove(leagueId));
    }
  }

  /// 1 appel API /{sport}/odds/live -> Map<matchId, MatchOdds>.
  /// Enrichit tous les matchs live en une passe.
  Future<void> _prefetchLiveOdds(Sport sport) async {
    final oddsMap = await _svc.getLiveOdds(sport: sport);
    if (oddsMap.isEmpty) return;
    if (!mounted || _sport != sport) return;
    setState(() {
      final list = _live[sport];
      if (list == null) return;
      final updated = [
        for (final m in list)
          oddsMap[m.id] != null ? m.copyWith(odds: oddsMap[m.id]) : m,
      ];
      _live[sport] = updated;
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshLive());
  }

  Future<void> _refreshLive() async {
    try {
      final live = await _svc.getLiveMatches(sport: _sport);
      if (!mounted) return;
      setState(() => _live[_sport] = live);
      // Soccer : re-prefetch live odds (endpoint dedie /odds/live)
      // NBA : odds deja inclus dans /nba/livescores parsing -> skip
      if (_sport != Sport.basketball) {
        unawaited(_prefetchLiveOdds(_sport));
      }
    } catch (_) {/* silencieux */}
  }

  void _toggleFavorite(BettingMatch m) {
    setState(() {
      if (_favorites.contains(m.id)) {
        _favorites.remove(m.id);
      } else {
        _favorites.add(m.id);
      }
    });
  }

  // Le label est genere via MarketLabels.selectionLabel(...) - sport-aware.

  double? _oddsValue(MatchOdds? o, String code) {
    if (o == null) return null;
    switch (code) {
      case 'home': return o.home;
      case 'draw': return o.draw;
      case 'away': return o.away;
    }
    return null;
  }

  BetSelection? _buildSelection(BettingMatch m, String market) {
    final value = _oddsValue(m.odds, market);
    if (value == null) return null;
    return BetSelection(
      matchId: m.id,
      matchLabel: '${m.homeName} vs ${m.awayName}',
      marketCode: market,
      marketLabel: MarketLabels.selectionLabel(
        market, m.sport,
        homeName: m.homeName, awayName: m.awayName,
      ),
      odds: value,
      kickoff: m.startTime,
      isLive: m.isLive,
    );
  }

  /// Tap simple sur une cote -> pari simple immediat.
  void _onTapOdds(BettingMatch m, String market) {
    final sel = _buildSelection(m, market);
    if (sel == null) return;
    showSingleBetSheet(context, sel);
  }

  /// Long press sur une cote -> ajout au combine (haptic feedback).
  void _onLongPressOdds(BettingMatch m, String market) {
    final sel = _buildSelection(m, market);
    if (sel == null) return;
    HapticFeedback.mediumImpact();
    BetSlipController.instance.toggle(sel);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.bgElevated,
        duration: const Duration(milliseconds: 1200),
        content: Text(
          'Ajouté au combiné — ${sel.marketLabel}',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
      ),
    );
  }

  /// Tap sur le corps de la card -> ecran detail avec tous les marches.
  void _onOpenDetail(BettingMatch m) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => BettingMatchDetailScreen(match: m)),
    );
  }

  /// Liste filtree + groupee par ligue. Cle = nom ligue.
  Map<String, List<BettingMatch>> _grouped() {
    final list = [...(_live[_sport] ?? const <BettingMatch>[]), ...(_today[_sport] ?? const <BettingMatch>[])];
    Iterable<BettingMatch> filtered = list;

    // FILTRE GLOBAL : on n'affiche que les matchs avec au moins 1X2 dispo.
    // Les matchs sans bookmaker prematch sont masques (zero interet de parier).
    // Exception Favoris : on garde meme sans cotes (le user les a etoiles).
    filtered = filtered.where((m) {
      final hasOdds = m.odds != null &&
          (m.odds!.home != null ||
           m.odds!.draw != null ||
           m.odds!.away != null);
      if (_filter == _Filter.favoris) {
        return _favorites.contains(m.id);
      }
      if (!hasOdds) return false;
      if (_filter == _Filter.live) return m.isLive;

      if (_selectedDate != null) {
        final d = _dateOnly(m.startTime);
        if (d != _selectedDate) return false;
      }
      return true;
    });

    if (_query.isNotEmpty) {
      filtered = filtered.where((m) =>
          m.homeName.toLowerCase().contains(_query) ||
          m.awayName.toLowerCase().contains(_query) ||
          m.league.toLowerCase().contains(_query));
    }

    final groups = <String, List<BettingMatch>>{};
    for (final m in filtered) {
      groups.putIfAbsent(m.league, () => []).add(m);
    }
    // Tri : live d'abord (presence d'au moins 1 live dans la ligue), puis A-Z.
    final entries = groups.entries.toList()
      ..sort((a, b) {
        final aLive = a.value.any((m) => m.isLive) ? 0 : 1;
        final bLive = b.value.any((m) => m.isLive) ? 0 : 1;
        if (aLive != bLive) return aLive - bLive;
        return a.key.compareTo(b.key);
      });
    return Map.fromEntries(entries);
  }

  /// Nombre de matchs LIVE avec cotes (les seuls visibles dans le filtre Live).
  int get _liveCount {
    final list = _live[_sport] ?? const <BettingMatch>[];
    return list.where((m) =>
        m.odds != null &&
        (m.odds!.home != null || m.odds!.draw != null || m.odds!.away != null)).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Stack(children: [
          _body(),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: BetSlipPill(
              onTap: () => showBetSlipSheet(context),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    // Plus de loader local : le splash a deja chauffe les caches.
    // Si erreur ET aucune donnee -> error view, sinon on affiche ce qu'on a
    // (potentiellement vide quelques ms le temps que le cache resolve).
    final hasAnyData = (_live[_sport]?.isNotEmpty ?? false) ||
        (_today[_sport]?.isNotEmpty ?? false);
    if (_error != null && !hasAnyData) {
      return _errorView();
    }

    final grouped = _grouped();
    return RefreshIndicator(
      color: AppColors.neonGreen,
      backgroundColor: AppColors.bgCard,
      onRefresh: _loadCurrentSport,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _promoBanner()),
        SliverToBoxAdapter(child: _virtualEntryCard()),
        SliverToBoxAdapter(child: _sportTabBar()),
        SliverToBoxAdapter(child: _dateStrip()),
        SliverToBoxAdapter(child: _searchBar()),
        SliverToBoxAdapter(child: _filtersRow()),
        if (grouped.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _emptyView())
        else
          for (final entry in grouped.entries)
            _leagueSection(entry.key, entry.value),
        const SliverToBoxAdapter(child: SizedBox(height: 90)),
      ]),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(children: [
        Icon(Icons.bolt_rounded, color: AppColors.neonYellow, size: 24),
        const SizedBox(width: 8),
        Text('Paris',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            )),
        const Spacer(),
        if (_liveCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neonRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.neonRed.withValues(alpha: 0.4),
                  width: 0.6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                    color: AppColors.neonRed, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('$_liveCount live',
                  style: TextStyle(
                    color: AppColors.neonRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  )),
            ]),
          ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BetsHistoryScreen())),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.divider.withValues(alpha: 0.5),
                  width: 0.5),
            ),
            child: Icon(Icons.receipt_long_rounded,
                size: 18, color: AppColors.textPrimary),
          ),
        ),
      ]),
    );
  }

  /// Banner promo CDM 2026 avec countdown live.
  /// Disparait apres le coup d'envoi (J-0).
  Widget _promoBanner() {
    final now = DateTime.now().toUtc();
    final remaining = _worldCupKickoff.difference(now);
    if (remaining.isNegative) {
      // CDM commencee -> banner "EN COURS"
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: _liveCupBanner(),
      );
    }
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.neonGreen.withValues(alpha: 0.18),
              AppColors.neonYellow.withValues(alpha: 0.10),
              AppColors.bgCard,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.neonGreen.withValues(alpha: 0.4),
              width: 0.8),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonGreen.withValues(alpha: 0.12),
              blurRadius: 10, offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('🏆',
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('COUPE DU MONDE 2026',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  )),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.neonYellow.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                    color: AppColors.neonYellow.withValues(alpha: 0.5),
                    width: 0.5),
              ),
              child: Text('J-$days',
                  style: TextStyle(
                    color: AppColors.neonYellow,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  )),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _countCell('$days', 'jours'),
            const SizedBox(width: 6),
            _countCell(hh, 'h'),
            const SizedBox(width: 6),
            _countCell(mm, 'min'),
            const SizedBox(width: 6),
            _countCell(ss, 'sec'),
          ]),
          const SizedBox(height: 10),
          Text(
            '🇺🇸 États-Unis · 🇨🇦 Canada · 🇲🇽 Mexique',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              // Cherche large : 'world' matche "World: Friendly International"
              // (matchs prepa CDM aujourd'hui) ET "World Cup 2026" (post 11 juin).
              _searchCtrl.text = 'world';
              // Reset date pour voir TOUS les jours (CDM = +9 jours)
              setState(() => _selectedDate = null);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.neonGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.search_rounded,
                    size: 14, color: Colors.black),
                const SizedBox(width: 6),
                const Text('Matchs internationaux + CDM',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    )),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _countCell(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgDark.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.4), width: 0.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(value,
              style: TextStyle(
                color: AppColors.neonGreen,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              )),
          Text(label,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              )),
        ]),
      ),
    );
  }

  Widget _liveCupBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.neonRed.withValues(alpha: 0.2),
            AppColors.bgCard,
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.neonRed.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
              color: AppColors.neonRed, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '🏆 COUPE DU MONDE 2026 — EN COURS',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
        InkWell(
          onTap: () => _searchCtrl.text = 'world cup',
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.neonRed,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Parier',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                )),
          ),
        ),
      ]),
    );
  }

  /// Card d'entree vers les matchs virtuels. Style violet/neon pour
  /// se distinguer nettement des matchs reels en dessous.
  Widget _virtualEntryCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VirtualMatchesScreen()),
          ),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedBuilder(
            animation: VirtualMatchService.instance,
            builder: (context, _) {
              final all = VirtualMatchService.instance.matches;
              final liveN = all.where((m) => m.isLive).length;
              final upcomingN =
                  all.where((m) => m.state == VirtualState.upcoming).length;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.neonPurple.withValues(alpha: 0.22),
                      AppColors.neonBlue.withValues(alpha: 0.10),
                      AppColors.bgCard,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.neonPurple.withValues(alpha: 0.45),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonPurple.withValues(alpha: 0.10),
                      blurRadius: 10, offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.neonPurple.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.neonPurple.withValues(alpha: 0.5),
                          width: 0.6),
                    ),
                    child: Icon(Icons.flash_on_rounded,
                        color: AppColors.neonPurple, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.neonPurple,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('VIRTUEL',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                )),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('Matchs simulés',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                )),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          if (liveN > 0) ...[
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.neonRed,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('$liveN en cours',
                                style: TextStyle(
                                  color: AppColors.neonRed,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                )),
                            const SizedBox(width: 10),
                          ],
                          if (upcomingN > 0) ...[
                            Container(
                              width: 6, height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.neonYellow,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('$upcomingN à venir',
                                style: TextStyle(
                                  color: AppColors.neonYellow,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                )),
                          ],
                          if (liveN == 0 && upcomingN == 0)
                            Text('Pariez 24/7 · Résultat en 30s',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                )),
                        ]),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.neonPurple, size: 24),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sportTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Row(children: [
          _sportTabChip(Sport.soccer, Icons.sports_soccer, 'Football'),
          _sportTabChip(Sport.basketball, Icons.sports_basketball, 'Basket'),
        ]),
      ),
    );
  }

  Widget _sportTabChip(Sport s, IconData icon, String label) {
    final active = _sport == s;
    return Expanded(
      child: InkWell(
        onTap: () => _sportTab.index = s.index,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.neonGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16, color: active ? Colors.black : AppColors.textMuted),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    color: active ? Colors.black : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  /// Calendrier horizontal style Sofascore : 14 jours navigables.
  /// Format compact : "Lun 9" sur 2 lignes, badge special CDM 11 juin.
  Widget _dateStrip() {
    final today = _dateOnly(DateTime.now());
    // Genere dates aujourd'hui + 14 jours suivants
    final dates = List.generate(_daysAhead + 1, (i) => today.add(Duration(days: i)));
    final cdmKickoffLocal = _worldCupKickoff.toLocal();
    final cdmDate = DateTime(cdmKickoffLocal.year, cdmKickoffLocal.month, cdmKickoffLocal.day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(children: [
            Icon(Icons.calendar_month_rounded,
                size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text('Calendrier',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                )),
            const Spacer(),
            if (_selectedDate != null)
              InkWell(
                onTap: () => setState(() => _selectedDate = null),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('Tous',
                      style: TextStyle(
                        color: AppColors.neonGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                        decorationColor:
                            AppColors.neonGreen.withValues(alpha: 0.5),
                      )),
                ),
              ),
          ]),
        ),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: dates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final d = dates[i];
              return _dateChip(d, today, cdmDate);
            },
          ),
        ),
      ]),
    );
  }

  Widget _dateChip(DateTime date, DateTime today, DateTime cdmDate) {
    final isSelected = _selectedDate != null &&
        _selectedDate!.year == date.year &&
        _selectedDate!.month == date.month &&
        _selectedDate!.day == date.day;
    final isToday = date == today;
    final isCdm = date == cdmDate;
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
    // StatPal v2 ne renvoie que today (offset=0). Les autres dates sont
    // marquees "futur" -> selection autorisee mais affiche un message clair
    // dans l'empty view.
    final isFuture = date.isAfter(today);

    const dayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final dayLabel = isToday ? 'Auj.' : dayShort[date.weekday - 1];

    final Color bg;
    final Color fg;
    final Color borderColor;
    if (isSelected) {
      bg = AppColors.neonGreen;
      fg = Colors.black;
      borderColor = AppColors.neonGreen;
    } else if (isCdm) {
      bg = AppColors.neonYellow.withValues(alpha: 0.12);
      fg = AppColors.neonYellow;
      borderColor = AppColors.neonYellow.withValues(alpha: 0.5);
    } else if (isFuture) {
      bg = AppColors.bgElevated.withValues(alpha: 0.5);
      fg = AppColors.textMuted;
      borderColor = AppColors.divider.withValues(alpha: 0.3);
    } else {
      bg = AppColors.bgElevated;
      fg = isWeekend
          ? AppColors.textPrimary
          : AppColors.textPrimary.withValues(alpha: 0.85);
      borderColor = AppColors.divider.withValues(alpha: 0.5);
    }

    return InkWell(
      onTap: () => setState(() => _selectedDate = date),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 54,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: borderColor, width: isSelected ? 1.2 : 0.5),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.neonGreen.withValues(alpha: 0.4),
                    blurRadius: 8, offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Stack(children: [
          if (isCdm && !isSelected)
            Positioned(
              top: 2, right: 4,
              child: Text('🏆', style: TextStyle(fontSize: 10)),
            )
          else if (isFuture && !isSelected)
            Positioned(
              top: 3, right: 4,
              child: Icon(Icons.lock_outline_rounded,
                  size: 9, color: AppColors.textMuted),
            ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dayLabel,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.75),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    )),
                const SizedBox(height: 2),
                Text('${date.day}',
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    )),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Row(children: [
          const SizedBox(width: 12),
          Icon(Icons.search, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              cursorColor: AppColors.neonGreen,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Recherche équipe ou ligue',
                hintStyle: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: AppColors.textMuted),
              onPressed: () => _searchCtrl.clear(),
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          const SizedBox(width: 6),
        ]),
      ),
    );
  }

  Widget _filtersRow() {
    final chips = [
      (_Filter.tous,    Icons.apps,           'Tous'),
      (_Filter.live,    Icons.flash_on,       'Live'),
      (_Filter.favoris, Icons.star_rounded,   'Favoris'),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (filter, icon, label) = chips[i];
          final active = _filter == filter;
          return InkWell(
            onTap: () => setState(() => _filter = filter),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.neonGreen.withValues(alpha: 0.18)
                    : AppColors.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? AppColors.neonGreen
                      : AppColors.divider.withValues(alpha: 0.5),
                  width: active ? 1 : 0.5,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon,
                    size: 13,
                    color: active
                        ? AppColors.neonGreen
                        : AppColors.textMuted),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                      color: active
                          ? AppColors.neonGreen
                          : AppColors.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    )),
              ]),
            ),
          );
        },
      ),
    );
  }

  SliverMainAxisGroup _leagueSection(String league, List<BettingMatch> ms) {
    final isCollapsed = _collapsedLeagues.contains(league);
    final hasLive = ms.any((m) => m.isLive);

    // Lazy prefetch : declenche en post-frame pour eviter setState
    // pendant le build. Couvre les ligues hors top 15 (init).
    final leagueId = ms
        .firstWhere(
          (m) => m.leagueId != null && m.leagueId!.isNotEmpty,
          orElse: () => ms.first,
        )
        .leagueId;
    if (leagueId != null && leagueId.isNotEmpty &&
        !_prefetchedLeagueIds.contains(leagueId) &&
        !_loadingLeagueIds.contains(leagueId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prefetchLeagueOddsLazy(leagueId);
      });
    }

    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
        child: InkWell(
          onTap: () => setState(() {
            if (isCollapsed) {
              _collapsedLeagues.remove(league);
            } else {
              _collapsedLeagues.add(league);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(children: [
              Icon(
                isCollapsed
                    ? Icons.keyboard_arrow_right_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              if (hasLive) ...[
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.neonRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(league.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    )),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${ms.length}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    )),
              ),
            ]),
          ),
        ),
      ),
      if (!isCollapsed)
        SliverList.builder(
          itemCount: ms.length,
          itemBuilder: (_, i) {
            final m = ms[i];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AnimatedBuilder(
                animation: BetSlipController.instance,
                builder: (context, _) {
                  final selectedMarket =
                      BetSlipController.instance.marketFor(m.id);
                  final lid = m.leagueId;
                  final isOddsLoading = lid != null &&
                      _loadingLeagueIds.contains(lid);
                  return BettingMatchCard(
                    match: m,
                    isFavorite: _favorites.contains(m.id),
                    selectedMarket: selectedMarket,
                    oddsLoading: isOddsLoading,
                    onToggleFavorite: () => _toggleFavorite(m),
                    onTapCard: () => _onOpenDetail(m),
                    onTapOdds: (mk) => _onTapOdds(m, mk),
                    onLongPressOdds: (mk) => _onLongPressOdds(m, mk),
                  );
                },
              ),
            );
          },
        ),
    ]);
  }

  Widget _emptyView() {
    String msg;
    // Cas special : la recherche 'world' (bouton CDM) n'a rien renvoye.
    final isWorldSearch = _query == 'world' || _query == 'world cup' ||
        _query == 'coupe du monde';
    if (isWorldSearch) {
      final remaining = _worldCupKickoff.difference(DateTime.now().toUtc());
      final days = remaining.inDays;
      if (remaining.isNegative) {
        msg = 'Aucun match international avec cotes en ce moment.\n'
              'La Coupe du Monde est en cours, reviens dans la journée.';
      } else if (days > 0) {
        msg = 'Pas encore de matchs Coupe du Monde dans StatPal.\n'
              'Coup d\'envoi dans $days jours (11 juin 2026).\n\n'
              'Aujourd\'hui, regarde aussi les matchs amicaux\n'
              'internationaux préparatoires (World: Friendly).';
      } else {
        msg = 'Coupe du Monde 2026 démarre dans quelques heures.\n'
              'Les cotes vont apparaître peu avant le coup d\'envoi.';
      }
    } else if (_filter == _Filter.favoris) {
      msg = 'Aucun favori. Étoile un match pour l\'ajouter ici.';
    } else if (_filter == _Filter.live) {
      msg = 'Aucun match en direct avec cotes pour le moment.';
    } else if (_query.isNotEmpty) {
      msg = 'Aucun match ne correspond à "$_query".';
    } else if (_sport == Sport.basketball) {
      msg = 'Aucun match basket disponible. Hors saison NBA peut-être ?';
    } else if (_selectedDate != null) {
      final today = _dateOnly(DateTime.now());
      final isFuture = _selectedDate!.isAfter(today);
      if (isFuture) {
        msg = '🔒 Les matchs ${_formatDateFr(_selectedDate!)} ne sont pas\n'
              'encore disponibles dans StatPal.\n\n'
              'Les cotes seront ajoutées progressivement\n'
              'à l\'approche de la date.';
      } else {
        msg = 'Aucun match avec cotes ${_formatDateFr(_selectedDate!)}.';
      }
    } else {
      msg = 'Aucun match avec cotes aujourd\'hui.\n'
            'Reviens demain ou attends la Coupe du Monde 2026 (11 juin).';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
              _sport == Sport.basketball
                  ? Icons.sports_basketball
                  : Icons.sports_soccer,
              size: 56,
              color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              )),
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
          Text('Erreur de chargement',
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
            onPressed: _initialLoad,
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

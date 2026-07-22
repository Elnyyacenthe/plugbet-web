// ============================================================
// BettingScreen — Onglet "Paris" (theme Plugbet)
// ============================================================
// Layout :
//   Header     : "Paris" + badge live
//   Tabs sport : Football / Basket / NFL / MLB / Tennis
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
import '../theme/app_icons.dart';
import '../theme/app_reliefs.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_theme.dart';
import '../services/statpal_service.dart';
import '../services/team_logo_service.dart';
import '../services/providers/sports_data.dart';
import '../services/the_odds_api_mapper.dart' show canonicalSportName;
import '../services/virtual_match_service.dart';
import '../state/bet_slip_controller.dart';
import '../widgets/betting_match_card.dart';
import '../widgets/bet_slip.dart';
import 'betting_match_detail_screen.dart';
import 'virtual_matches_screen.dart';
import 'bets_history_screen.dart';
import '../utils/market_labels.dart';
import '../utils/bet_slip_feedback.dart';
import 'package:provider/provider.dart';
import '../providers/promo_provider.dart';
import '../models/promo_item.dart';
import '../games/games_catalog.dart';
import '../widgets/section_rail.dart';
import '../widgets/plugbet_wordmark.dart';
import 'support_screen.dart';
import 'promotions/promotions_screen.dart';
import 'promotions/promo_detail_screen.dart';

class BettingScreen extends StatefulWidget {
  const BettingScreen({super.key});

  @override
  State<BettingScreen> createState() => _BettingScreenState();
}

enum _Filter { tous, live, favoris }

class _CategoryTab {
  final IconData icon;
  final String label;
  const _CategoryTab(this.icon, this.label);
}

class _SportTabItem {
  final Sport sport;
  final IconData icon;
  final String label;
  final double width;
  const _SportTabItem(this.sport, this.icon, this.label, this.width);
}

/// Teaser E-Sport (onglet "À venir") : discipline bientôt disponible aux paris.
class _EsportTeaser {
  final String name;
  final String genre;
  final String emoji;
  final Color color;
  const _EsportTeaser(this.name, this.genre, this.emoji, this.color);
}

class _BettingScreenState extends State<BettingScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _heroCtrl = PageController();
  late final TabController _sportTab;
  late final AnimationController _livePulseCtrl;

  // Caches locaux : on garde matchs par sport.
  final Map<Sport, List<BettingMatch>> _live = {};
  final Map<Sport, List<BettingMatch>> _today = {};
  final Set<String> _favorites = {};
  final Set<String> _collapsedLeagues = {}; // leagues fermees
  final Set<String> _prefetchedLeagueIds = {}; // odds fetched OK
  final Set<String> _loadingLeagueIds = {}; // fetch en cours

  _Filter _filter = _Filter.tous;
  // Categorie active de la topbar : 0=Top, 1=Sports, 2=Jeux, 3=Casino,
  // 4=A venir. La navigation est INTERNE (on change juste le corps).
  int _category = 0;
  // Section Casino : recherche + filtre.
  final _casinoSearchCtrl = TextEditingController();
  String _casinoQuery = '';
  GameCategory? _casinoTag;
  String _query = '';
  int _heroIndex = 0;
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
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
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
  static final DateTime _worldCupKickoff = DateTime.utc(2026, 6, 12, 0, 0, 0);

  // Onglets = NOMS des sports (pas des championnats). L'ordre suit les sports
  // renvoyes par The Odds API et attendus par le grand public.
  static const List<_SportTabItem> _sportTabs = [
    _SportTabItem(Sport.soccer, AppIcons.football, 'Football', 116),
    _SportTabItem(Sport.basketball, AppIcons.basketball, 'Basketball', 132),
    _SportTabItem(Sport.americanFootball, Icons.sports_football_rounded,
        'Football Américain', 188),
    _SportTabItem(Sport.baseball, Icons.sports_baseball_rounded, 'Baseball', 122),
    _SportTabItem(
        Sport.handball, Icons.sports_handball_rounded, 'Handball', 124),
    _SportTabItem(
        Sport.iceHockey, Icons.sports_hockey_rounded, 'Hockey sur glace', 168),
    _SportTabItem(Sport.rugby, Icons.sports_rugby_rounded, 'Rugby', 104),
    _SportTabItem(Sport.tennis, AppIcons.tennis, 'Tennis', 108),
  ];

  Sport get _sport => _sportTabs[_sportTab.index].sport;

  // E-Sports "bientôt disponibles" affichés dans l'onglet "À venir".
  static const List<_EsportTeaser> _esports = [
    _EsportTeaser('League of Legends', 'MOBA', '🐉', Color(0xFF1FB6A6)),
    _EsportTeaser('Counter-Strike 2', 'FPS', '🔫', Color(0xFFF0A030)),
    _EsportTeaser('Dota 2', 'MOBA', '⚔️', Color(0xFFE0473E)),
    _EsportTeaser('Valorant', 'FPS tactique', '🎯', Color(0xFFFF4655)),
    _EsportTeaser('EA Sports FC', 'Football', '⚽', Color(0xFF2ECC71)),
    _EsportTeaser('Rocket League', 'Voiture-foot', '🚀', Color(0xFF3B82F6)),
    _EsportTeaser('Call of Duty', 'FPS', '🎖️', Color(0xFF8B9A46)),
    _EsportTeaser('Overwatch 2', 'Hero FPS', '🛡️', Color(0xFFF48C25)),
    _EsportTeaser('Fortnite', 'Battle Royale', '🏝️', Color(0xFF9B5DE5)),
    _EsportTeaser('Mobile Legends', 'MOBA', '📱', Color(0xFF5B6EE1)),
    _EsportTeaser('PUBG Mobile', 'Battle Royale', '🪂', Color(0xFFEAB308)),
    _EsportTeaser('Rainbow Six Siege', 'FPS tactique', '💥', Color(0xFF64748B)),
  ];

  static IconData _sportIconFor(Sport sport) {
    switch (sport) {
      case Sport.soccer:
        return AppIcons.football;
      case Sport.basketball:
        return AppIcons.basketball;
      case Sport.americanFootball:
        return Icons.sports_football_rounded;
      case Sport.baseball:
        return Icons.sports_baseball_rounded;
      case Sport.tennis:
        return AppIcons.tennis;
      case Sport.iceHockey:
        return Icons.sports_hockey_rounded;
      case Sport.rugby:
        return Icons.sports_rugby_rounded;
      case Sport.handball:
        return Icons.sports_handball_rounded;
    }
  }

  static String _sportEmptyName(Sport sport) {
    switch (sport) {
      case Sport.soccer:
        return 'football';
      case Sport.basketball:
        return 'basketball';
      case Sport.americanFootball:
        return 'football américain';
      case Sport.baseball:
        return 'baseball';
      case Sport.tennis:
        return 'tennis';
      case Sport.iceHockey:
        return 'hockey sur glace';
      case Sport.rugby:
        return 'rugby';
      case Sport.handball:
        return 'handball';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _livePulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.35,
      upperBound: 1,
    )..repeat(reverse: true);
    _sportTab = TabController(length: _sportTabs.length, vsync: this)
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
    _heroCtrl.dispose();
    _casinoSearchCtrl.dispose();
    _sportTab.dispose();
    _livePulseCtrl.dispose();
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
      // The Odds API : getUpcomingMatches renvoie deja les cotes inline.
      final results = await Future.wait([
        SportsData.active.getUpcomingMatches(sport: _sport),
        SportsData.active.getLiveMatches(sport: _sport),
      ]);
      if (!mounted) return;
      setState(() => _today[_sport] = results[0]);
      _applyLiveScores(
          results[1]); // fusionne les scores live dans _today + _live
      _prefetchLogos();
      _startPolling();
      // ── REFRESH AUTO apres 6s ──
      // Au cold start, getTodayMatches peut retourner du cache disque ou
      // une partie incomplete (ex: WC 2026 fetched en BG via warmupFull).
      // On relance un refresh apres que le warmup ait pu finir pour
      // garantir que la WC + les featured leagues apparaissent.
      _scheduleBackgroundRefresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// Force un refresh des matchs apres delai, pour ramasser ce que le
  /// warmupFull a fetch en arriere-plan (notamment la Coupe du monde).
  void _scheduleBackgroundRefresh() {
    Future.delayed(const Duration(seconds: 6), () async {
      if (!mounted) return;
      try {
        final list = await SportsData.active.getUpcomingMatches(sport: _sport);
        if (!mounted) return;
        // Ne replace que si on a strictement PLUS de matchs (sinon, on
        // suppose que rien n'a change et on evite un setState inutile).
        final current = _today[_sport] ?? const <BettingMatch>[];
        if (list.length > current.length) {
          setState(() => _today[_sport] = list);
        }
      } catch (_) {/* silencieux */}
    });
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
        SportsData.active.getUpcomingMatches(sport: _sport),
        SportsData.active.getLiveMatches(sport: _sport),
      ]);
      if (!mounted) return;
      setState(() {
        _today[_sport] = results[0];
        _error = null;
      });
      _applyLiveScores(results[1]);
      _prefetchLogos();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  /// Fusionne les scores live (/scores The Odds API, sans cotes) dans les
  /// matchs de _today (qui portent les cotes) : marque isLive + score, et
  /// reconstruit _live a partir des matchs ainsi enrichis (avec cotes).
  void _applyLiveScores(List<BettingMatch> scores) {
    if (!mounted) return;
    final byId = {for (final s in scores) s.id: s};
    setState(() {
      final today = [...?_today[_sport]];
      final live = <BettingMatch>[];
      for (var i = 0; i < today.length; i++) {
        final sc = byId[today[i].id];
        if (sc != null) {
          today[i] = today[i].copyWith(
            isLive: true,
            homeScore: sc.homeScore,
            awayScore: sc.awayScore,
          );
          live.add(today[i]);
        }
      }
      _today[_sport] = today;
      _live[_sport] = live;
    });
  }

  // ── Cotes : desormais INLINE via The Odds API (getUpcomingMatches) ──
  // Les anciennes methodes de prefetch StatPal par ligue sont neutralisees
  // (conservees en no-op car appelees au scroll / changement de sport).
  // ignore: unused_element
  Future<void> _prefetchOdds(Sport sport) async {/* cotes deja inline */}

  Future<void> _prefetchLeagueOddsLazy(String leagueId) async {
    // Cotes deja presentes sur les matchs : plus de fetch par ligue.
    _prefetchedLeagueIds.add(leagueId);
  }

  // ignore: unused_element
  Future<void> _prefetchLiveOdds(Sport sport) async {/* cotes deja inline */}

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refreshLive());
  }

  Future<void> _refreshLive() async {
    try {
      final scores = await SportsData.active.getLiveMatches(sport: _sport);
      if (!mounted) return;
      _applyLiveScores(scores); // fusionne scores -> _today (cotes) + _live
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
      case 'home':
        return o.home;
      case 'draw':
        return o.draw;
      case 'away':
        return o.away;
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
        market,
        m.sport,
        homeName: m.homeName,
        awayName: m.awayName,
      ),
      odds: value,
      kickoff: m.startTime,
      isLive: m.isLive,
      // 2Up : sport canonique + sport_key (detecteur) + eligibilite (indice UI)
      sport: canonicalSportName(m.sport),
      leagueKey: m.leagueId,
      sportName: m.sport.name,
      twoUpEligible: SportsData.active.supports2Up(m.sport) &&
          !m.isLive &&
          (market == 'home' || market == 'away'),
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
    final r = BetSlipController.instance.toggle(sel);
    BetSlipFeedback.show(context, r, sel);
  }

  /// Tap sur le corps de la card -> ecran detail avec tous les marches.
  void _onOpenDetail(BettingMatch m) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BettingMatchDetailScreen(match: m)),
    );
  }

  /// Liste filtree + groupee par ligue. Cle = nom ligue.
  Map<String, List<BettingMatch>> _grouped() {
    final list = [
      ...(_live[_sport] ?? const <BettingMatch>[]),
      ...(_today[_sport] ?? const <BettingMatch>[])
    ];
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
        // Tolerance timezone : si le match est tard dans la journee UTC,
        // il peut apparaitre J ou J+1 selon le fuseau. On accepte les 2.
        final dLocal = _dateOnly(m.startTime);
        final dLocalPlus1 = dLocal.add(const Duration(days: 1));
        if (dLocal != _selectedDate && dLocalPlus1 != _selectedDate) {
          return false;
        }
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
    return list
        .where((m) =>
            m.odds != null &&
            (m.odds!.home != null ||
                m.odds!.draw != null ||
                m.odds!.away != null))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Sports garde le fond thémé ; les autres sections (Top, Jeux,
      // Casino, À venir) adoptent le chrome sombre bleu-nuit.
      backgroundColor:
          _category == 1 ? AppColors.bettingBackground : AppColors.bgDark,
      body: SafeArea(
        child: Stack(
          children: [
            _body(),
            _betSlipFloatingBar(),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    return RefreshIndicator(
      color: AppColors.primaryInk,
      backgroundColor: AppColors.bettingSurface,
      onRefresh: _loadCurrentSport,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _header()),
        SliverToBoxAdapter(child: _categoryBar()),
        ..._sectionSlivers(),
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ]),
    );
  }

  /// Corps variable selon la catégorie active de la topbar. Aucune
  /// navigation vers un autre écran : on garde header + barre du bas.
  List<Widget> _sectionSlivers() {
    switch (_category) {
      case 1:
        return _sportsbookSlivers();
      case 2:
        return _jeuxSlivers();
      case 3:
        return _casinoSlivers();
      case 4:
        return _aVenirSlivers();
      case 0:
      default:
        return _topSlivers();
    }
  }

  void _openGameEntry(GameEntry g) {
    Navigator.push(context, MaterialPageRoute(builder: g.builder));
  }

  void _openPromotions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PromotionsScreen()),
    );
  }

  // Ouvre le détail de CETTE promo précise (corrige le bug : avant, toutes
  // les cartes ouvraient la page globale des promotions).
  void _openPromoDetail(PromoItem p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PromoDetailScreen(promoId: p.id)),
    );
  }

  // ── SPORTS : paris réels uniquement (sans le carousel d'affiches) ──
  List<Widget> _sportsbookSlivers() {
    final hasAnyData = (_live[_sport]?.isNotEmpty ?? false) ||
        (_today[_sport]?.isNotEmpty ?? false);
    if (_error != null && !hasAnyData) {
      return [SliverFillRemaining(hasScrollBody: false, child: _errorView())];
    }
    final grouped = _grouped();
    return [
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
    ];
  }

  // ── TOP : hub de découverte (rails scrollables + assistance) ──
  List<Widget> _topSlivers() {
    final promos = context.watch<PromoProvider>().promotions;
    final jeux = kGamesCatalog
        .where((g) =>
            !g.tags.contains(GameCategory.casino) &&
            !g.tags.contains(GameCategory.fantasy))
        .toList();
    final casino = kCasinoGames;
    final fantasy = kGamesCatalog
        .where((g) => g.tags.contains(GameCategory.fantasy))
        .toList();
    final leagues = _grouped().keys.toList();

    return [
      // Hero : compte à rebours CDM + promo (réutilise l'existant).
      SliverToBoxAdapter(child: _promoBanner()),
      if (promos.isNotEmpty)
        SliverToBoxAdapter(
          child: SectionRail(
            title: 'Promotions',
            onSeeAll: _openPromotions,
            children: [
              for (final p in promos)
                MiniPoster(
                  imageAsset: p.imageUrl.isEmpty ? null : p.imageUrl,
                  title: p.title,
                  subtitle: p.highlightedReward,
                  fallbackIcon: Icons.card_giftcard_rounded,
                  badge: p.badgeLabel ?? 'PROMO',
                  onTap: () => _openPromoDetail(p),
                ),
            ],
          ),
        ),
      if (fantasy.isNotEmpty)
        SliverToBoxAdapter(
          child: SectionRail(
            title: 'Fantasy',
            onSeeAll: () => _openGameEntry(fantasy.first),
            children: [
              for (final g in fantasy)
                MiniPoster(
                  imageAsset: g.imageAsset,
                  title: g.title,
                  subtitle: g.subtitle,
                  fallbackIcon: g.icon,
                  badge: 'FANTASY',
                  onTap: () => _openGameEntry(g),
                ),
            ],
          ),
        ),
      SliverToBoxAdapter(
        child: SectionRail(
          title: 'Jeux',
          onSeeAll: () => setState(() => _category = 2),
          children: [
            for (final g in jeux)
              MiniPoster(
                imageAsset: g.imageAsset,
                title: g.title,
                subtitle: g.subtitle,
                fallbackIcon: g.icon,
                badge: g.hot ? 'HOT' : null,
                onTap: () => _openGameEntry(g),
              ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: SectionRail(
          title: 'Casino',
          onSeeAll: () => setState(() => _category = 3),
          children: [
            for (final g in casino)
              MiniPoster(
                imageAsset: g.imageAsset,
                title: g.title,
                subtitle: g.subtitle,
                fallbackIcon: g.icon,
                badge: g.hot ? 'HOT' : null,
                onTap: () => _openGameEntry(g),
              ),
          ],
        ),
      ),
      if (leagues.isNotEmpty)
        SliverToBoxAdapter(
          child: SectionRail(
            title: 'Championnats à venir',
            onSeeAll: () => setState(() => _category = 1),
            children: [
              for (final lg in leagues.take(10))
                MiniPoster(
                  imageAsset: null,
                  title: lg,
                  fallbackIcon: AppIcons.trophy,
                  onTap: () => setState(() => _category = 1),
                ),
            ],
          ),
        ),
      SliverToBoxAdapter(child: _assistanceBlock()),
    ];
  }

  // ── JEUX : grille complète, chrome conservé ──
  List<Widget> _jeuxSlivers() {
    return [
      SliverToBoxAdapter(child: _sectionTitle('Tous les jeux')),
      _gamesGridSliver(kGamesCatalog),
    ];
  }

  // ── CASINO : recherche + filtres + grille ──
  List<Widget> _casinoSlivers() {
    final q = _casinoQuery.toLowerCase();
    final games = kCasinoGames.where((g) {
      final byTag = _casinoTag == null || g.tags.contains(_casinoTag);
      final byQ =
          q.isEmpty || '${g.title} ${g.subtitle}'.toLowerCase().contains(q);
      return byTag && byQ;
    }).toList();
    return [
      SliverToBoxAdapter(child: _sectionTitle('Casino')),
      SliverToBoxAdapter(child: _casinoSearch()),
      SliverToBoxAdapter(child: _casinoFilters()),
      if (games.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text('Aucun jeu casino trouvé.',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          ),
        )
      else
        _gamesGridSliver(games),
    ];
  }

  // ── À VENIR : jeux bientôt disponibles ──
  List<Widget> _aVenirSlivers() {
    return [
      SliverToBoxAdapter(child: _sectionTitle('Bientôt disponibles')),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Ces sections arrivent très bientôt sur Plugbet. Reste connecté !',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
        ),
      ),
      // ── E-Sports (teasers "bientôt") ──
      SliverToBoxAdapter(child: _sectionTitle('E-Sports')),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'Parie bientôt sur tes jeux préférés — les plus grandes compétitions '
            'e-sport arrivent sur Plugbet.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.45,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _esportCard(_esports[i]),
            childCount: _esports.length,
          ),
        ),
      ),
    ];
  }

  Widget _esportCard(_EsportTeaser e) {
    return GestureDetector(
      onTap: () => _showEsportComingSoon(e.name),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              e.color.withValues(alpha: 0.30),
              e.color.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: e.color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(e.emoji, style: const TextStyle(fontSize: 30)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: e.color.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('BIENTÔT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      )),
                ),
              ],
            ),
            const Spacer(),
            Text(e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                )),
            const SizedBox(height: 2),
            Text(e.genre,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  void _showEsportComingSoon(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎮 $name arrive bientôt sur Plugbet !'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Helpers de sections ──────────────────────────────────────

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        t,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.4,
        ),
      ),
    );
  }

  Widget _gamesGridSliver(List<GameEntry> games) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.74,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            final g = games[i];
            return MiniPoster(
              imageAsset: g.imageAsset,
              title: g.title,
              fallbackIcon: g.icon,
              badge: g.hot ? 'HOT' : null,
              width: null,
              onTap: () => _openGameEntry(g),
            );
          },
          childCount: games.length,
        ),
      ),
    );
  }

  Widget _casinoSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(AppIcons.search, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _casinoSearchCtrl,
                onChanged: (v) => setState(() => _casinoQuery = v.trim()),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                cursorColor: kPlugbetGreen,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: 'Rechercher un jeu casino',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                ),
              ),
            ),
            if (_casinoQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _casinoSearchCtrl.clear();
                  setState(() => _casinoQuery = '');
                },
                child: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _casinoFilters() {
    const chips = <(String, GameCategory?)>[
      ('Tous', null),
      ('Multijoueur', GameCategory.multiplayer),
      ('Arcade', GameCategory.arcade),
    ];
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _casinoChip(c.$1, c.$2),
            ),
        ],
      ),
    );
  }

  Widget _casinoChip(String label, GameCategory? tag) {
    final active = _casinoTag == tag;
    return GestureDetector(
      onTap: () => setState(() => _casinoTag = tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? kPlugbetGreen : AppColors.bgCard,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? kPlugbetGreen : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _assistanceBlock() {
    const legal =
        'Vos paris et paiements sont traités par Ennovative Gaming Sarl, '
        'qui est autorisé et réglementé par le Ministère de l\'Administration '
        'Territoriale du Cameroun.\n\n'
        'Licence n° 000975/A/MINAT/SG/DAP/SDLP/SJ/\n\n'
        'Vous devez être âgé d\'au moins 21 ans pour parier.\n'
        'Les paris créent une dépendance et peuvent être psychologiquement '
        'néfastes.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportScreen()),
              ),
              icon: const Icon(AppIcons.support, size: 20, color: Colors.black),
              label: const Text(
                'Assistance & Support',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPlugbetGreen,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            legal,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Header sombre (bleu-nuit, identique a la barre du bas) : logo
  /// « PLUGBET » centre (PLUG blanc + BET vert), pastille live a gauche
  /// et cloche de notifications a droite.
  Widget _header() {
    return Container(
      color: AppColors.bgDark,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Logo image (adaptatif clair/sombre) centre.
              const Center(child: PlugbetLogoImage(height: 30)),
              // Pastille live a gauche.
              Align(
                alignment: Alignment.centerLeft,
                child: _LivePill(
                  count: _liveCount,
                  pulse: _livePulseCtrl,
                ),
              ),
              // Cloche a droite.
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BetsHistoryScreen()),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Icon(
                      AppIcons.notification,
                      size: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Barre de categories (sous le header) ─────────────────────
  // Top / Sports restent sur le sportsbook (categories residentes) ;
  // Jeux & Casino ouvrent l'ecran Jeux ; A venir ouvre les matchs
  // virtuels. L'item actif porte un soulignement + texte vert.
  Widget _categoryBar() {
    const cats = <_CategoryTab>[
      _CategoryTab(AppIcons.flame, 'Top'),
      _CategoryTab(AppIcons.trophy, 'Sports'),
      _CategoryTab(AppIcons.games, 'Jeux'),
      _CategoryTab(AppIcons.cards, 'Casino'),
      _CategoryTab(AppIcons.calendar, 'À venir'),
    ];

    const underlineW = 24.0;
    const barHeight = 60.0;

    return Container(
      color: AppColors.bgDark,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemW = constraints.maxWidth / cats.length;
          return SizedBox(
            height: barHeight,
            child: Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < cats.length; i++)
                      Expanded(child: _categoryItem(cats[i], i)),
                  ],
                ),
                // Soulignement unique qui GLISSE de l'ancienne à la
                // nouvelle position lors du changement de catégorie.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: itemW * _category + (itemW - underlineW) / 2,
                  bottom: 8,
                  child: Container(
                    width: underlineW,
                    height: 3,
                    decoration: BoxDecoration(
                      color: kPlugbetGreen,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _categoryItem(_CategoryTab cat, int index) {
    final active = _category == index;
    final color = active ? kPlugbetGreen : AppColors.textMuted;

    return InkWell(
      // Navigation INTERNE : on change juste la section affichée, le
      // header et la barre du bas restent en place.
      onTap: () => setState(() => _category = index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(cat.icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(
            cat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Carousel principal : compte a rebours CDM + promo statique.
  Widget _promoBanner() {
    final now = DateTime.now().toUtc();
    final remaining = _worldCupKickoff.difference(now);
    final positive = remaining.isNegative ? Duration.zero : remaining;
    final days = positive.inDays;
    final hh = positive.inHours.remainder(24).toString().padLeft(2, '0');
    final mm = positive.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = positive.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: PageView(
            controller: _heroCtrl,
            onPageChanged: (index) => setState(() => _heroIndex = index),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _worldCupCountdownSlide(days.toString(), hh, mm, ss),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _downloadPromoSlide(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 9),
        _heroDots(2),
      ],
    );
  }

  Widget _countCell(String value, String label) {
    return Container(
      width: 45,
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.bettingImageScrim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.bettingOnImage.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: AppColors.bettingOnImage,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.bettingOnImageMuted,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _worldCupCountdownSlide(String days, String hh, String mm, String ss) {
    return _ImageBannerFrame(
      asset: 'assets/images/afficheCoupeDuMonde.png',
      alignment: Alignment.centerRight,
      child: Stack(
        children: [
          Positioned(
            top: 14,
            left: 14,
            child: _ImageBadge(
              label: 'EN DIRECT',
              background: AppColors.bettingYellow,
              foreground: AppColors.onPrimary,
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: _OutlineImageBadge(
              label: 'LIVE',
              color: AppColors.bettingOrange,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'La Coupe du Monde',
                  style: TextStyle(
                    color: AppColors.bettingOnImage,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'États-Unis · Canada · Mexique',
                  style: TextStyle(
                    color: AppColors.bettingOnImageMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _countCell(days, 'Jours'),
                    _countSeparator(),
                    _countCell(hh, 'Hrs'),
                    _countSeparator(),
                    _countCell(mm, 'Min'),
                    _countSeparator(),
                    _countCell(ss, 'Sec'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countSeparator() {
    return Text(
      ':',
      style: TextStyle(
        color: AppColors.bettingOnImageMuted,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _downloadPromoSlide() {
    return const _ImageBannerFrame(
      asset: 'assets/images/AffichePrincipal.png',
      fit: BoxFit.fill,
      overlay: false,
      child: SizedBox.shrink(),
    );
  }

  Widget _heroDots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: _heroIndex == i ? 24 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: _heroIndex == i
                  ? AppColors.primary
                  : AppColors.bettingInactive.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (i != count - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  /// Bannière secondaire EA Sports. Elle garde l'entrée vers les matchs
  /// virtuels déjà branchée, sans toucher au service.
  Widget _virtualEntryCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Material(
        color: AppColors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VirtualMatchesScreen()),
          ),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedBuilder(
            animation: VirtualMatchService.instance,
            builder: (context, _) {
              final liveN = VirtualMatchService.instance.matches
                  .where((m) => m.isLive)
                  .length;
              return SizedBox(
                height: 110,
                child: _ImageBannerFrame(
                  asset: 'assets/images/afficheEASports.png',
                  radius: 14,
                  borderColor: AppColors.bettingViolet,
                  fit: BoxFit.fill,
                  overlay: false,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _EaLiveCountBadge(
                          count: liveN,
                          pulse: _livePulseCtrl,
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _PlayImageButton(
                          color: AppColors.bettingViolet,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sportTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.bettingSurfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.bettingBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.bettingSoftShadow,
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _sportTabs.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => _sportSwitchOption(_sportTabs[i], i),
        ),
      ),
    );
  }

  Widget _sportSwitchOption(_SportTabItem item, int index) {
    final active = _sport == item.sport;
    final fg = active
        ? AppSurfaces.inkOn(AppColors.primary)
        : AppColors.bettingTextSecondary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: item.width,
      decoration: BoxDecoration(
        color: active ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: () {
          if (_sportTab.index != index) _sportTab.animateTo(index);
        },
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(item.label,
                  style: TextStyle(
                    color: active ? fg : AppColors.bettingTextSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
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
    final dates =
        List.generate(_daysAhead + 1, (i) => today.add(Duration(days: i)));
    final cdmKickoffLocal = _worldCupKickoff.toLocal();
    final cdmDate = DateTime(
        cdmKickoffLocal.year, cdmKickoffLocal.month, cdmKickoffLocal.day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Icon(
              AppIcons.calendar,
              size: 15,
              color: AppColors.bettingTextSecondary,
            ),
            const SizedBox(width: 6),
            Text('CALENDRIER',
                style: TextStyle(
                  color: AppColors.bettingTextSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                )),
            const Spacer(),
            if (_selectedDate != null)
              InkWell(
                onTap: () => setState(() => _selectedDate = today),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text('Tous',
                      style: TextStyle(
                        color: AppColors.primaryInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                        decorationColor:
                            AppColors.primaryInk.withValues(alpha: 0.5),
                      )),
                ),
              ),
          ]),
        ),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: dates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
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
    const dayShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final dayLabel = isToday ? 'Auj.' : dayShort[date.weekday - 1];

    final Color fg;
    final Color borderColor;
    final Color background;
    if (isSelected) {
      background = AppColors.primary;
      fg = AppSurfaces.inkOn(AppColors.primary);
      borderColor = AppColors.primary;
    } else if (isCdm) {
      background = AppSurfaces.tint(
        AppColors.bettingSurfaceElevated,
        AppColors.bettingYellow,
        0.12,
      );
      fg = AppColors.bettingYellow;
      borderColor = AppColors.bettingYellow.withValues(alpha: 0.45);
    } else {
      background = AppColors.bettingSurfaceElevated;
      fg = AppColors.bettingTextSecondary;
      borderColor = AppColors.bettingBorder;
    }

    return InkWell(
      onTap: () => setState(() => _selectedDate = date),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 60,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected ? 1.2 : 1),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.22)
                  : AppColors.bettingSoftShadow,
              blurRadius: isSelected ? 13 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(children: [
          Positioned(
            top: 5,
            right: 6,
            child: Icon(
              isCdm ? AppIcons.trophy : AppIcons.lock,
              size: 10,
              color: isSelected
                  ? AppSurfaces.inkOn(AppColors.primary).withValues(alpha: 0.82)
                  : (isCdm
                      ? AppColors.bettingYellow
                      : AppColors.bettingInactive),
            ),
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
                    )),
                const SizedBox(height: 3),
                Text('${date.day}',
                    style: TextStyle(
                      color: fg,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.bettingSurfaceElevated,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: AppColors.bettingBorder),
          boxShadow: [
            BoxShadow(
              color: AppColors.bettingSoftShadow,
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(children: [
          const SizedBox(width: 14),
          Icon(
            AppIcons.search,
            size: 18,
            color: AppColors.bettingTextSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              cursorColor: AppColors.primaryInk,
              style: TextStyle(
                color: AppColors.bettingTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Rechercher une équipe ou une ligue',
                hintStyle: TextStyle(
                  color: AppColors.bettingTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              icon: Icon(
                AppIcons.close,
                size: 16,
                color: AppColors.bettingTextSecondary,
              ),
              onPressed: () => _searchCtrl.clear(),
              splashRadius: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          const SizedBox(width: 8),
        ]),
      ),
    );
  }

  Widget _filtersRow() {
    final chips = [
      (_Filter.tous, AppIcons.grid, 'Tous'),
      (_Filter.live, AppIcons.bets, 'Live'),
      (_Filter.favoris, AppIcons.starFilled, 'Favoris'),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final (filter, icon, label) = chips[i];
          final active = _filter == filter;
          final fg =
              active ? AppColors.primaryInk : AppColors.bettingTextSecondary;
          return InkWell(
            onTap: () => setState(() => _filter = filter),
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.bettingSurfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      active ? AppColors.primaryInk : AppColors.bettingBorder,
                  width: active ? 1.1 : 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.bettingSoftShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
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
    if (leagueId != null &&
        leagueId.isNotEmpty &&
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
                isCollapsed ? AppIcons.chevronRight : AppIcons.chevronDown,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              if (hasLive) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow:
                        AppSurfaces.glowOnly(AppColors.primary, strength: 0.7),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(league.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.bettingTextSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    )),
              ),
              // Compteur gravé : il compte, il ne s'impose pas.
              InsetPanel(
                radius: 6,
                depth: 0.6,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                child: Text('${ms.length}',
                    style: TextStyle(
                      color: AppColors.bettingTextPrimary,
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
                  final isOddsLoading =
                      lid != null && _loadingLeagueIds.contains(lid);
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

  Widget _betSlipFloatingBar() {
    return AnimatedBuilder(
      animation: BetSlipController.instance,
      builder: (context, _) {
        final ctrl = BetSlipController.instance;
        if (ctrl.count == 0) return const SizedBox.shrink();
        final odds = ctrl.combinedOdds.toStringAsFixed(2);
        final label = ctrl.count == 1 ? 'Pari simple' : 'Pari combiné';

        return Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: SafeArea(
            top: false,
            child: Material(
              color: AppColors.transparent,
              child: InkWell(
                onTap: () => showBetSlipSheet(context),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.bettingOnImage,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${ctrl.count}',
                            style: TextStyle(
                              color: AppColors.primaryInk,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                color: AppSurfaces.inkOn(AppColors.primary),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Cote totale ×$odds',
                              style: TextStyle(
                                color: AppSurfaces.inkOn(AppColors.primary)
                                    .withValues(alpha: 0.72),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bettingOnImage,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Parier',
                              style: TextStyle(
                                color: AppColors.primaryInk,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              AppIcons.forward,
                              size: 13,
                              color: AppColors.primaryInk,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyView() {
    String msg;
    // Cas special : la recherche 'world' (bouton CDM) n'a rien renvoye.
    final isWorldSearch = _query == 'world' ||
        _query == 'world cup' ||
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
    } else if (_sport != Sport.soccer) {
      msg = 'Aucun match ${_sportEmptyName(_sport)} disponible pour le moment.';
    } else if (_selectedDate != null) {
      final today = _dateOnly(DateTime.now());
      final isFuture = _selectedDate!.isAfter(today);
      if (isFuture) {
        msg = 'Les matchs ${_formatDateFr(_selectedDate!)} ne sont pas\n'
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
          Icon(_sportIconFor(_sport), size: 56, color: AppColors.textMuted),
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
          Icon(AppIcons.warning, size: 56, color: AppColors.neonRed),
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
          ReliefButton(
            label: 'Réessayer',
            icon: AppIcons.refresh,
            onPressed: _initialLoad,
            height: 44,
          ),
        ]),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  final int count;
  final Animation<double> pulse;

  const _LivePill({
    required this.count,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primaryInk.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: pulse,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: AppSurfaces.glowOnly(
                  AppColors.primary,
                  strength: 0.65,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count LIVE',
            style: TextStyle(
              color: AppColors.primaryInk,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EaLiveCountBadge extends StatelessWidget {
  final int count;
  final Animation<double> pulse;

  const _EaLiveCountBadge({
    required this.count,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.bettingImageScrim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryInk.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: pulse,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: AppSurfaces.glowOnly(
                  AppColors.primary,
                  strength: 0.65,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count LIVE',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayImageButton extends StatelessWidget {
  final Color color;

  const _PlayImageButton({
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Jouer',
            style: TextStyle(
              color: AppColors.bettingOnImage,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Icon(
            AppIcons.forward,
            size: 13,
            color: AppColors.bettingOnImage,
          ),
        ],
      ),
    );
  }
}

class _ImageBannerFrame extends StatelessWidget {
  final String asset;
  final Widget child;
  final double radius;
  final Color? borderColor;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final bool overlay;

  const _ImageBannerFrame({
    required this.asset,
    required this.child,
    this.radius = 18,
    this.borderColor,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.overlay = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        color: AppColors.bettingSurfaceElevated,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? AppColors.bettingBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.bettingSoftShadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1.2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              asset,
              fit: fit,
              alignment: alignment,
              errorBuilder: (_, __, ___) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.bettingViolet.withValues(alpha: 0.75),
                      AppColors.primaryInk.withValues(alpha: 0.52),
                      AppColors.bettingImageOverlayStrong,
                    ],
                  ),
                ),
              ),
            ),
            if (overlay)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.46, 1],
                      colors: [
                        AppColors.bettingImageOverlaySoft,
                        AppColors.bettingImageOverlaySoft,
                        AppColors.bettingImageOverlayStrong,
                      ],
                    ),
                  ),
                ),
              ),
            Positioned.fill(child: child),
          ],
        ),
      ),
    );
  }
}

class _ImageBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _ImageBadge({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _OutlineImageBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _OutlineImageBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bettingImageScrim,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.88)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

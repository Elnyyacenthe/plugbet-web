// ============================================================
// Plugbet – Ecran d'accueil
// Carousel horizontal top + ligues triees par popularite
// Chaque ligue = scroll horizontal de matchs
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/matches_provider.dart';
import '../providers/notification_provider.dart';
import '../models/football_models.dart';
import '../widgets/carousel_card.dart';
import '../widgets/loading_shimmer.dart';
import '../widgets/home/league_row.dart';
import '../widgets/home/finished_section.dart';
import 'match_detail_screen.dart';

// ============================================================
// Classement de popularite des ligues
// Les ligues connues sont triees en premier, le reste apres
// ============================================================
const _leaguePopularity = <String, int>{
  // Coupes continentales
  'UEFA Champions League': 1,
  'Champions League': 1,
  'UEFA Europa League': 2,
  'Europa League': 2,
  'UEFA Europa Conference League': 3,
  'Europa Conference League': 3,
  'Copa Libertadores': 4,
  'AFC Champions League': 5,
  'CAF Champions League': 6,
  // Top 5 europeens
  'Premier League': 10,
  'La Liga': 11,
  'Serie A': 12,
  'Bundesliga': 13,
  'Ligue 1': 14,
  // Autres ligues majeures
  'Primeira Liga': 20,
  'Liga Portugal': 20,
  'Eredivisie': 21,
  'Super Lig': 22,
  'Saudi Pro League': 23,
  'MLS': 24,
  'Serie A (Brazil)': 25,
  'Championship': 26,
  'Liga MX': 27,
  // Coupes nationales
  'FA Cup': 30,
  'Copa del Rey': 31,
  'Coupe de France': 32,
  'DFB Pokal': 33,
  'Coppa Italia': 34,
  'EFL Cup': 35,
  // Internationaux
  'World Cup': 0,
  'European Championship': 0,
  'EURO': 0,
  'Copa America': 1,
  'Africa Cup of Nations': 2,
  'Asian Cup': 3,
  'FIFA World Cup Qualification': 5,
};

int _getLeagueRank(String name) {
  // Chercher correspondance exacte ou partielle
  for (final entry in _leaguePopularity.entries) {
    if (name == entry.key || name.contains(entry.key) || entry.key.contains(name)) {
      return entry.value;
    }
  }
  return 100; // Ligues inconnues en dernier
}

class HomeScreen extends StatefulWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;

  const HomeScreen({super.key, this.scaffoldKey});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// Filtre par jour
enum _DayFilter { live, today, yesterday, tomorrow }

class _HomeScreenState extends State<HomeScreen> {
  _DayFilter _selectedFilter = _DayFilter.today;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Memoization cache pour éviter recalculs couteux sur chaque rebuild
  List<FootballMatch> _cachedAllMatches = [];
  _DayFilter _cachedFilter = _DayFilter.today;
  String _cachedSearch = '';
  List<FootballMatch> _cachedFiltered = [];
  List<FootballMatch> _cachedTopMatches = [];
  List<MapEntry<Competition, List<FootballMatch>>> _cachedLeagues = [];
  List<MapEntry<Competition, List<FootballMatch>>> _cachedFinished = [];

  // Progressive loading par priorité: LIVE → UPCOMING → FINISHED
  int _loadingStage = 1; // 1=LIVE, 2=LIVE+UPCOMING, 3=TOUS
  Timer? _stage2Timer;
  Timer? _stage3Timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<MatchesProvider>();
      if (provider.allMatches.isEmpty) {
        provider.loadMatches();
      }

      // Chargement progressif par étapes
      // Étape 1: LIVE (immédiat)
      // Étape 2: LIVE + UPCOMING (après 500ms)
      _stage2Timer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _loadingStage = 2);
      });

      // Étape 3: TOUS (après 1500ms)
      _stage3Timer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _loadingStage = 3);
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _stage2Timer?.cancel();
    _stage3Timer?.cancel();
    super.dispose();
  }

  void _navigateToDetail(int matchId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(matchId: matchId),
      ),
    );
  }

  void _showNotificationPanel(BuildContext context, NotificationProvider notifProv) {
    notifProv.markAllRead();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: notifProv,
        child: const _NotificationPanel(),
      ),
    );
  }

  /// Filtre les matchs selon le tab selectionne + recherche
  List<FootballMatch> _filterByDay(List<FootballMatch> all) {
    List<FootballMatch> filtered;
    final now = DateTime.now();

    switch (_selectedFilter) {
      case _DayFilter.live:
        filtered = all.where((m) => m.status.isLive).toList();
      case _DayFilter.today:
        // Filtrer par la date d'aujourd'hui (jour + mois + année)
        filtered = all.where((m) =>
          m.dateTime.day == now.day &&
          m.dateTime.month == now.month &&
          m.dateTime.year == now.year
        ).toList();
      case _DayFilter.yesterday:
        final yesterday = now.subtract(const Duration(days: 1));
        filtered = all.where((m) =>
          m.dateTime.day == yesterday.day &&
          m.dateTime.month == yesterday.month &&
          m.dateTime.year == yesterday.year
        ).toList();
      case _DayFilter.tomorrow:
        final tomorrow = now.add(const Duration(days: 1));
        filtered = all.where((m) =>
          m.dateTime.day == tomorrow.day &&
          m.dateTime.month == tomorrow.month &&
          m.dateTime.year == tomorrow.year
        ).toList();
    }

    // Appliquer le filtre de recherche
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((m) {
        return m.homeTeam.name.toLowerCase().contains(q) ||
            m.awayTeam.name.toLowerCase().contains(q) ||
            m.homeTeam.shortName.toLowerCase().contains(q) ||
            m.awayTeam.shortName.toLowerCase().contains(q) ||
            (m.homeTeam.tla?.toLowerCase().contains(q) ?? false) ||
            (m.awayTeam.tla?.toLowerCase().contains(q) ?? false) ||
            m.competition.name.toLowerCase().contains(q);
      }).toList();
    }

    return filtered;
  }

  /// Matchs les plus attendus (live + grosses ligues a venir)
  List<FootballMatch> _getTopMatches(List<FootballMatch> filtered) {
    final live = filtered.where((m) => m.status.isLive).toList();
    final upcoming = filtered
        .where((m) => m.status.isUpcoming)
        .toList()
      ..sort((a, b) {
        final ra = _getLeagueRank(a.competition.name);
        final rb = _getLeagueRank(b.competition.name);
        if (ra != rb) return ra.compareTo(rb);
        return a.dateTime.compareTo(b.dateTime);
      });
    return [...live, ...upcoming].take(10).toList();
  }

  /// Groupe les matchs non-termines par ligue, triees par popularite
  List<MapEntry<Competition, List<FootballMatch>>> _leagueGroups(List<FootballMatch> filtered) {
    final matches = filtered
        .where((m) => m.status != MatchStatus.finished)
        .toList();
    return _groupSorted(matches);
  }

  /// Groupe les matchs termines par ligue, triees par popularite
  List<MapEntry<Competition, List<FootballMatch>>> _finishedGroups(List<FootballMatch> filtered) {
    final matches = filtered
        .where((m) => m.status == MatchStatus.finished)
        .toList();
    return _groupSorted(matches);
  }

  List<MapEntry<Competition, List<FootballMatch>>> _groupSorted(List<FootballMatch> matches) {
    final map = <int, (Competition, List<FootballMatch>)>{};
    for (final match in matches) {
      final comp = match.competition;
      if (map.containsKey(comp.id)) {
        map[comp.id]!.$2.add(match);
      } else {
        map[comp.id] = (comp, [match]);
      }
    }
    for (final entry in map.values) {
      entry.$2.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    final list = map.values
        .map((e) => MapEntry(e.$1, e.$2))
        .toList();
    // Tri par popularite puis par nombre de matchs
    list.sort((a, b) {
      final ra = _getLeagueRank(a.key.name);
      final rb = _getLeagueRank(b.key.name);
      if (ra != rb) return ra.compareTo(rb);
      return b.value.length.compareTo(a.value.length);
    });
    return list;
  }

  /// Recalcule les listes filtrées seulement si les dépendances ont changé
  void _updateCacheIfNeeded(List<FootballMatch> allMatches) {
    final needsUpdate = _cachedAllMatches != allMatches ||
        _cachedFilter != _selectedFilter ||
        _cachedSearch != _searchQuery;

    if (!needsUpdate) return;

    // Mise à jour du cache
    _cachedAllMatches = allMatches;
    _cachedFilter = _selectedFilter;
    _cachedSearch = _searchQuery;

    _cachedFiltered = _filterByDay(allMatches);
    _cachedTopMatches = _getTopMatches(_cachedFiltered);
    _cachedLeagues = _leagueGroups(_cachedFiltered);
    _cachedFinished = _finishedGroups(_cachedFiltered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Consumer<MatchesProvider>(
            builder: (context, provider, _) {
              if (provider.state == LoadingState.loading &&
                  provider.allMatches.isEmpty) {
                return const LoadingShimmer();
              }

              if ((provider.state == LoadingState.error ||
                      provider.state == LoadingState.offline) &&
                  provider.allMatches.isEmpty) {
                return _buildErrorView(provider);
              }

              if (provider.state == LoadingState.loaded &&
                  provider.allMatches.isEmpty) {
                return _buildEmptyView(provider);
              }

              // Progressive loading par priorité: filtrer selon l'étape
              List<FootballMatch> matchesToProcess;
              switch (_loadingStage) {
                case 1: // Étape 1: LIVE uniquement (priorité max)
                  matchesToProcess = provider.allMatches
                      .where((m) => m.status.isLive)
                      .toList();
                  break;
                case 2: // Étape 2: LIVE + UPCOMING
                  matchesToProcess = provider.allMatches
                      .where((m) => m.status.isLive || m.status.isUpcoming)
                      .toList();
                  break;
                default: // Étape 3: TOUS
                  matchesToProcess = provider.allMatches;
              }

              _updateCacheIfNeeded(matchesToProcess);

              // Utiliser les résultats du cache (déjà filtrés par priorité)
              final leaguesToShow = _cachedLeagues;
              final finishedToShow = _cachedFinished;

              return RefreshIndicator(
                color: AppColors.neonGreen,
                backgroundColor: AppColors.bgCard,
                onRefresh: provider.refreshMatches,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // En-tete
                    SliverToBoxAdapter(child: _buildHeader(provider)),

                    // Carousel top : matchs les plus attendus
                    if (_cachedTopMatches.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _buildTopCarousel(_cachedTopMatches),
                      ),

                    // Sections par ligue (lazy — seules les visibles sont construites)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final entry = leaguesToShow[index];
                          return LeagueRow(
                            key: ValueKey(entry.key.id),
                            competition: entry.key,
                            matches: entry.value,
                            onMatchTap: _navigateToDetail,
                          );
                        },
                        childCount: leaguesToShow.length,
                        // Ameliore la detection de reordering/changement
                        findChildIndexCallback: (key) {
                          if (key is ValueKey<int>) {
                            return leaguesToShow
                                .indexWhere((e) => e.key.id == key.value);
                          }
                          return null;
                        },
                      ),
                    ),

                    // Section termines repliable
                    if (finishedToShow.isNotEmpty)
                      SliverToBoxAdapter(
                        child: FinishedSection(
                          groups: finishedToShow,
                          onMatchTap: _navigateToDetail,
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER + DAY TABS
  // ============================================================
  Widget _buildHeader(MatchesProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(6, 8, 16, 0),
          child: Row(
            children: [
              // Bouton hamburger pour le drawer
              IconButton(
                icon: Icon(Icons.menu_rounded, color: AppColors.textPrimary, size: 24),
                onPressed: () {
                  widget.scaffoldKey?.currentState?.openDrawer();
                },
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [AppColors.textPrimary, AppColors.neonGreen],
                      stops: [0.6, 1.0],
                    ).createShader(bounds),
                    child: Text(
                      'Plugbet',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)!.homeTabLive,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.neonGreen.withValues(alpha: 0.7),
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (provider.state == LoadingState.offline)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.neonOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 14,
                        color: AppColors.neonOrange,
                      ),
                      SizedBox(width: 4),
                      Text(
                        provider.lastUpdateAgo,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.neonOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              // Cloche de notifications
              Consumer<NotificationProvider>(
                builder: (context, notifProv, _) => Stack(
                  children: [
                    IconButton(
                      icon: Icon(
                        notifProv.hasUnread
                            ? Icons.notifications_rounded
                            : Icons.notifications_none_rounded,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                      onPressed: () => _showNotificationPanel(context, notifProv),
                      tooltip: 'Notifications',
                    ),
                    if (notifProv.hasUnread)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.neonRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Barre de recherche
        _buildSearchBar(),
        // Day tabs
        _buildDayTabs(provider),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: TextField(
          controller: _searchController,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Equipe, competition...',
            hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close, size: 16),
                    color: AppColors.textMuted,
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
      ),
    );
  }

  Widget _buildDayTabs(MatchesProvider provider) {
    final t = AppLocalizations.of(context)!;
    final liveCount = provider.allMatches.where((m) => m.status.isLive).length;
    final tabs = <(_DayFilter, String, int?)>[
      (_DayFilter.live, t.homeTabLive, liveCount > 0 ? liveCount : null),
      (_DayFilter.yesterday, t.homeTabYesterday, null),
      (_DayFilter.today, t.homeTabToday, null),
      (_DayFilter.tomorrow, t.homeTabTomorrow, null),
    ];

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final (filter, label, badge) = tabs[index];
          final isSelected = _selectedFilter == filter;
          final isLiveTab = filter == _DayFilter.live;

          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = filter),
            child: Container(
              margin: EdgeInsets.only(right: 8),
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isLiveTab ? AppColors.neonRed.withValues(alpha: 0.2) : AppColors.neonGreen.withValues(alpha: 0.15))
                    : AppColors.bgCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? (isLiveTab ? AppColors.neonRed.withValues(alpha: 0.5) : AppColors.neonGreen.withValues(alpha: 0.4))
                      : AppColors.divider,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLiveTab) ...[
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: liveCount > 0 ? AppColors.neonRed : AppColors.textMuted,
                      ),
                    ),
                    SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? (isLiveTab ? AppColors.neonRed : AppColors.neonGreen)
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (badge != null) ...[
                    SizedBox(width: 6),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.neonRed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // CAROUSEL TOP – Matchs les plus attendus
  // ============================================================
  Widget _buildTopCarousel(List<FootballMatch> matches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: Row(
            children: [
              Icon(Icons.local_fire_department, size: 16, color: AppColors.neonOrange),
              SizedBox(width: 6),
              Text(
                'A LA UNE',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.neonOrange,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: MediaQuery.of(context).size.width < 360 ? 140 : 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              return CarouselCard(
                match: matches[index],
                onTap: () => _navigateToDetail(matches[index].id),
              );
            },
          ),
        ),
      ],
    );
  }

  // ============================================================
  // VUES VIDE / ERREUR
  // ============================================================
  Widget _buildEmptyView(MatchesProvider provider) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer, size: 64,
                color: AppColors.textMuted.withValues(alpha: 0.4)),
            SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.matchNoMatches,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              'Revenez plus tard ou tirez vers le bas\npour actualiser.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: provider.refreshMatches,
              icon: Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context)!.commonRefresh),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(MatchesProvider provider) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64,
                color: AppColors.textMuted.withValues(alpha: 0.5)),
            SizedBox(height: 16),
            Text(
              provider.errorMessage ?? AppLocalizations.of(context)!.commonError,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: provider.refreshMatches,
              icon: Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context)!.commonRetry),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Panneau de notifications (BottomSheet)
// ============================================================
class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel();

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    return 'Il y a ${diff.inDays} j';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, notifProv, _) {
        final notifications = notifProv.notifications;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: EdgeInsets.only(top: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.notifications_rounded, size: 18, color: AppColors.neonBlue),
                    SizedBox(width: 8),
                    Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (notifications.isNotEmpty)
                      TextButton(
                        onPressed: notifProv.clear,
                        child: Text(
                          'Tout effacer',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.divider),
              // Liste
              if (notifications.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 48, color: AppColors.textMuted),
                      SizedBox(height: 12),
                      Text(
                        'Aucune notification',
                        style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1, indent: 60, color: AppColors.divider,
                    ),
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      return Dismissible(
                        key: Key(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.only(right: 20),
                          color: AppColors.neonRed.withValues(alpha: 0.15),
                          child: Icon(Icons.delete_outline, color: AppColors.neonRed, size: 20),
                        ),
                        onDismissed: (_) => notifProv.dismiss(n.id),
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: n.color.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(n.icon, color: n.color, size: 18),
                          ),
                          title: Text(
                            n.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            n.body,
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          trailing: Text(
                            _timeAgo(n.time),
                            style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }
}

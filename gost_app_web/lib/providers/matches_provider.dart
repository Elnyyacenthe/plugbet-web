import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/football_models.dart';
import '../services/api_sports_service.dart';
import '../services/api_football_service.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import '../utils/logger.dart';

const _logProvider = Logger('PROVIDER');
const _logSmart = Logger('SMART');
const _logLifecycle = Logger('LIFECYCLE');
const _logRefresh = Logger('REFRESH');

enum LoadingState { idle, loading, loaded, error, offline }

class MatchesProvider extends ChangeNotifier {
  final ApiSportsService _apiSportsService;
  final ApiFootballService _apiService;
  final HiveService _hiveService;
  final SupabaseService _supabaseService;

  // --- État ---
  LoadingState _state = LoadingState.idle;
  LoadingState get state => _state;

  List<FootballMatch> _allMatches = [];
  List<FootballMatch> get allMatches => _allMatches;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DateTime? _lastFetch;
  DateTime? get lastFetch => _lastFetch;

  String _activeSource = '';
  String get activeSource => _activeSource;

  // --- Smart Polling ---
  Timer? _smartTimer;
  Timer? _bgGraceTimer;
  bool _isAppInForeground = true;
  bool _isGameActive = false;
  int _consecutiveLiveFailures = 0;
  DateTime? _lastSupabaseUpsert;
  String _pollReason = 'idle';

  // Lineups désactivées pour optimisation performances
  final Set<int> _lineupsFetched = {};

  MatchesProvider({
    required ApiSportsService apiSportsService,
    required ApiFootballService apiService,
    required HiveService hiveService,
    required SupabaseService supabaseService,
  })  : _apiSportsService = apiSportsService,
        _apiService = apiService,
        _hiveService = hiveService,
        _supabaseService = supabaseService {
    // Charger la clé API sauvegardée
    final savedKey = _hiveService.getApiSportsKey();
    if (savedKey != null && savedKey.isNotEmpty) {
      _apiSportsService.setApiKey(savedKey);
    }
    // Lancer le chargement immédiatement à la création du provider
    // Le cache s'affiche instantanément, l'API charge en arrière-plan
    loadMatches();
  }

  // ============================================================
  // GETTERS FILTRÉS
  // ============================================================

  List<FootballMatch> get liveMatches =>
      _allMatches.where((m) => m.status.isLive).toList();

  List<FootballMatch> get upcomingMatches {
    final upcoming = _allMatches.where((m) => m.status.isUpcoming).toList();
    upcoming.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return upcoming;
  }

  List<FootballMatch> get finishedMatches {
    final finished =
        _allMatches.where((m) => m.status == MatchStatus.finished).toList();
    finished.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return finished;
  }

  List<FootballMatch> get carouselMatches {
    final live = liveMatches;
    final upcoming = upcomingMatches;
    final combined = [...live, ...upcoming];
    return combined.take(8).toList();
  }

  Map<String, List<FootballMatch>> get matchesByCompetition {
    final map = <String, List<FootballMatch>>{};
    for (final match in _allMatches) {
      final key = match.competition.name;
      map.putIfAbsent(key, () => []);
      map[key]!.add(match);
    }
    for (final key in map.keys) {
      map[key]!.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    return map;
  }

  List<FootballMatch> getFavoriteMatches(List<int> favoriteTeamIds) {
    if (favoriteTeamIds.isEmpty) return [];
    return _allMatches
        .where((m) =>
            favoriteTeamIds.contains(m.homeTeam.id) ||
            favoriteTeamIds.contains(m.awayTeam.id))
        .toList();
  }

  // ============================================================
  // SYSTEME DE PRIORITE (standard + user-based)
  // ============================================================

  /// Classement statique des ligues (plus petit = plus important)
  static const _leaguePriority = <String, int>{
    'World Cup': 100,
    'European Championship': 99,
    'EURO': 99,
    'Copa America': 98,
    'Africa Cup of Nations': 97,
    'UEFA Champions League': 96,
    'Champions League': 96,
    'UEFA Europa League': 94,
    'Europa League': 94,
    'Premier League': 92,
    'La Liga': 90,
    'Serie A': 88,
    'Bundesliga': 88,
    'Ligue 1': 85,
    'Primeira Liga': 70,
    'Liga Portugal': 70,
    'Eredivisie': 68,
    'Championship': 65,
    'Saudi Pro League': 60,
    'MLS': 58,
    'FA Cup': 75,
    'Copa del Rey': 73,
    'Coupe de France': 70,
    'DFB Pokal': 70,
    'Coppa Italia': 70,
  };

  /// Grandes equipes (bonus supplementaire)
  static const _bigTeams = <String>{
    'Real Madrid',
    'FC Barcelona',
    'Manchester City',
    'Manchester United',
    'Liverpool',
    'Arsenal',
    'Chelsea',
    'Bayern Munich',
    'Bayern München',
    'Paris Saint-Germain',
    'PSG',
    'Juventus',
    'Inter',
    'AC Milan',
    'Borussia Dortmund',
    'Atletico Madrid',
    'Napoli',
    'Tottenham',
    'Newcastle',
    'Benfica',
    'Porto',
    'Ajax',
    'Al Hilal',
    'Al Nassr',
    'Flamengo',
    'Boca Juniors',
    'River Plate',
  };

  /// Calcule le score de priorite d'un match (plus haut = plus important)
  int calculatePriority(FootballMatch match) {
    int score = 0;

    // 1. LIVE = priorite absolue
    if (match.status.isLive) score += 150;

    // 2. Bonus ligue
    for (final entry in _leaguePriority.entries) {
      if (match.competition.name.contains(entry.key) ||
          entry.key.contains(match.competition.name)) {
        score += entry.value;
        break;
      }
    }

    // 3. Bonus grandes equipes
    final homeName = match.homeTeam.name;
    final awayName = match.awayTeam.name;
    for (final team in _bigTeams) {
      if (homeName.contains(team) || team.contains(homeName)) score += 20;
      if (awayName.contains(team) || team.contains(awayName)) score += 20;
    }

    // 4. Score serre / buts marques (matchs live)
    if (match.status.isLive) {
      final h = match.score.homeFullTime ?? 0;
      final a = match.score.awayFullTime ?? 0;
      score += (h + a) * 5; // Plus de buts = plus interessant
      if ((h - a).abs() <= 1) score += 15; // Score serre
    }

    // 5. Match imminent (dans les 30 prochaines minutes)
    if (match.status.isUpcoming) {
      final minutesUntil = match.dateTime.difference(DateTime.now()).inMinutes;
      if (minutesUntil >= 0 && minutesUntil <= 30) {
        score += 50;
      } else if (minutesUntil > 30 && minutesUntil <= 60) {
        score += 25;
      }
    }

    // 6. Bonus favoris
    final favIds = _hiveService.getFavoriteTeamIds();
    if (favIds.contains(match.homeTeam.id) ||
        favIds.contains(match.awayTeam.id)) {
      score += 100;
    }

    // 7. Bonus historique recherche (user-based)
    final searchHistory = _hiveService.getSearchHistory();
    for (final entry in searchHistory.entries) {
      final term = entry.key;
      final count = entry.value;
      if (homeName.toLowerCase().contains(term) ||
          awayName.toLowerCase().contains(term) ||
          match.competition.name.toLowerCase().contains(term)) {
        score += (count * 3).clamp(0, 50); // Max +50 par historique
      }
    }

    return score;
  }

  /// Retourne les matchs tries par priorite (plus haut score en premier)
  List<FootballMatch> getPrioritizedMatches() {
    final list = List<FootballMatch>.from(_allMatches);
    list.sort((a, b) => calculatePriority(b).compareTo(calculatePriority(a)));
    return list;
  }

  // ============================================================
  // CHARGEMENT INITIAL – Cache d'abord, puis API en arrière-plan
  // Chaîne : apifootball.com → football-data.org → cache → erreur
  // ============================================================
  Future<void> loadMatches() async {
    _errorMessage = null;
    final sw = Stopwatch()..start();
    _logProvider.info('══════ loadMatches() START ══════');

    // 1. Afficher le cache immédiatement (startup instantané)
    final cached = _hiveService.getCachedMatches();
    if (cached.isNotEmpty && _allMatches.isEmpty) {
      _logProvider.info('Cache instant: ${cached.length} matchs');
      _allMatches = cached;
      _lastFetch = _hiveService.getLastUpdateTime();
      _state = LoadingState.loaded;
      _activeSource = 'Cache';
      notifyListeners();
    } else if (_allMatches.isEmpty) {
      _state = LoadingState.loading;
      notifyListeners();
    }

    // 2. Laisser le UI se construire avec le cache AVANT de lancer le réseau
    // Sur Huawei CAN-L11, le premier build de 25 matchs prend ~3s
    // Sans ce délai → "Skipped 185 frames" → ANR → crash
    await Future.delayed(const Duration(milliseconds: 800));

    // 3. apifootball.com DESACTIVE (plan expire — a reactiver quand on paye)
    // Source unique: football-data.org
    List<FootballMatch> freshMatches = [];
    {
      try {
        _logProvider.info('Tentative football-data.org...');
        freshMatches = await _apiService.fetchTodayMatches();
        if (freshMatches.isNotEmpty) {
          _activeSource = 'football-data.org';
          _logProvider.info('football-data.org: ${freshMatches.length} matchs');
        }
      } catch (e) {
        _logProvider.info('football-data.org échoué: $e');
      }
    }

    // 4. Appliquer les résultats
    if (freshMatches.isNotEmpty) {
      _allMatches = freshMatches;
      _lastFetch = DateTime.now();
      _state = LoadingState.loaded;
      _hiveService.cacheMatches(freshMatches);
      // Upsert Supabase seulement toutes les 5 min (pas chaque poll)
      final now = DateTime.now();
      if (_lastSupabaseUpsert == null || now.difference(_lastSupabaseUpsert!).inMinutes >= 5) {
        _lastSupabaseUpsert = now;
        _supabaseService.upsertMatches(freshMatches).catchError((e) {
          _logProvider.info('Erreur upsertMatches: $e');
        });
      }
    } else if (_allMatches.isEmpty) {
      // Dernière chance : cache
      final fallbackCache = _hiveService.getCachedMatches();
      if (fallbackCache.isNotEmpty) {
        _allMatches = fallbackCache;
        _lastFetch = _hiveService.getLastUpdateTime();
        _state = LoadingState.offline;
        _activeSource = 'Cache (hors ligne)';
        _errorMessage = 'Mode hors ligne – données en cache';
      } else {
        _state = LoadingState.error;
        _errorMessage =
            'Impossible de charger les matchs. Vérifiez votre connexion.';
      }
    }

    _logProvider.info('══════ loadMatches() FIN en ${sw.elapsedMilliseconds}ms | ${_allMatches.length} matchs | source: $_activeSource ══════');
    notifyListeners();
    _startSmartPolling();
  }

  // ============================================================
  // SMART POLLING – Intervalles dynamiques selon proximité des matchs
  // ============================================================

  void _startSmartPolling() {
    _stopPolling();
    _scheduleNextPoll();
  }

  void _stopPolling() {
    _smartTimer?.cancel();
    _smartTimer = null;
  }

  /// Calcule l'intervalle optimal selon l'état des matchs
  Duration _calculateInterval() {
    final hasLive = _allMatches.any((m) => m.status.isLive);

    // 1. Matchs en direct → polling 15s (4 req/min, respecte le rate limit de 6s)
    if (hasLive) {
      _pollReason = 'live';
      return Duration(seconds: _isAppInForeground ? 15 : 60);
    }

    // 2. Pas de matchs live → vérifier le prochain match upcoming
    final now = DateTime.now();
    DateTime? nextKickoff;
    for (final m in _allMatches) {
      if (m.status.isUpcoming && m.dateTime.isAfter(now)) {
        if (nextKickoff == null || m.dateTime.isBefore(nextKickoff)) {
          nextKickoff = m.dateTime;
        }
      }
    }

    if (nextKickoff == null) {
      // Aucun match upcoming → polling très lent
      _pollReason = 'no-matches-soon';
      return const Duration(hours: 2);
    }

    final minutesUntil = nextKickoff.difference(now).inMinutes;

    if (minutesUntil <= 30) {
      // Match imminent → polling actif
      _pollReason = 'pre-match-imminent';
      return const Duration(seconds: 60);
    } else if (minutesUntil <= 120) {
      // Match dans 30min-2h → lineups arrivent bientôt
      _pollReason = 'pre-match-lineups';
      return const Duration(minutes: 10);
    } else if (minutesUntil <= 360) {
      // Match dans 2h-6h → vérifier les changements de programme
      _pollReason = 'routine-near';
      return const Duration(minutes: 30);
    } else {
      // Match dans > 6h → rien d'urgent
      _pollReason = 'routine-distant';
      return const Duration(hours: 2);
    }
  }

  /// Programme le prochain poll avec l'intervalle optimal
  /// Appelé depuis les écrans de jeu pour suspendre le polling
  void pausePolling() {
    _isGameActive = true;
    _stopPolling();
  }

  /// Appelé quand on quitte un jeu pour reprendre le polling
  void resumePolling() {
    _isGameActive = false;
    _startSmartPolling();
  }

  void _scheduleNextPoll() {
    _smartTimer?.cancel();
    if (_isGameActive) return; // ne pas poller pendant un jeu
    final interval = _calculateInterval();
    _logSmart.info('Prochain poll dans ${interval.inSeconds}s (raison: $_pollReason)');
    _smartTimer = Timer(interval, () => _executePoll());
  }

  bool _pollRunning = false;

  /// Exécute un cycle de polling puis re-planifie (avec guard anti-concurrence)
  Future<void> _executePoll() async {
    if (_pollRunning) {
      _logSmart.info('Poll déjà en cours, skip');
      return;
    }
    _pollRunning = true;
    try {
      final hasLive = _allMatches.any((m) => m.status.isLive);
      final freshMatches = await _fetchFromApi(live: hasLive);

      if (freshMatches.isNotEmpty) {
        _consecutiveLiveFailures = 0;
        if (hasLive) {
          _mergeFreshMatches(freshMatches);
        } else {
          _allMatches = freshMatches;
          await _hiveService.cacheMatches(freshMatches);
        }
        _lastFetch = DateTime.now();
        _state = LoadingState.loaded;

        // Pré-charger les lineups si un match est à < 1h
        await _prefetchLineups();

        notifyListeners();
      } else {
        _consecutiveLiveFailures++;
        _logSmart.info('Aucune donnée ($_consecutiveLiveFailures échecs)');
      }
    } catch (e) {
      _consecutiveLiveFailures++;
      _logSmart.info('Erreur: $e ($_consecutiveLiveFailures échecs)');
    } finally {
      _pollRunning = false;
      // Toujours re-planifier le prochain poll
      _scheduleNextPoll();
    }
  }

  /// Fetch depuis football-data.org uniquement
  /// (apifootball.com desactive tant que le plan n'est pas paye)
  Future<List<FootballMatch>> _fetchFromApi({required bool live}) async {
    List<FootballMatch> matches = [];
    try {
      matches = (live && _consecutiveLiveFailures < 2)
          ? await _apiService.fetchLiveMatches()
          : await _apiService.fetchTodayMatches();
    } catch (e) {
      _logSmart.info('football-data.org échoué: $e');
    }
    return matches;
  }

  /// Pré-charge les lineups pour les matchs à < 1h du coup d'envoi
  Future<void> _prefetchLineups() async {
    final now = DateTime.now();
    for (final match in _allMatches) {
      if (!match.status.isUpcoming) continue;
      final minutesUntil = match.dateTime.difference(now).inMinutes;
      if (minutesUntil > 0 &&
          minutesUntil <= 60 &&
          !_lineupsFetched.contains(match.id)) {
        _logProvider.info('Lineups pre-chargement match ${match.id} (dans ${minutesUntil}min)');
        // Lineups désactivées pour optimisation performances
        _lineupsFetched.add(match.id);
      }
    }
  }

  void _mergeFreshMatches(List<FootballMatch> freshMatches) {
    for (final fresh in freshMatches) {
      final idx = _allMatches.indexWhere((m) => m.id == fresh.id);
      if (idx >= 0) {
        final old = _allMatches[idx];
        final scoreChanged =
            old.score.homeFullTime != fresh.score.homeFullTime ||
                old.score.awayFullTime != fresh.score.awayFullTime;
        if (scoreChanged) {
          _supabaseService.upsertMatch(fresh);
        }
        _allMatches[idx] = fresh;
      } else {
        _allMatches.add(fresh);
      }
      _hiveService.updateCachedMatch(fresh);
    }
  }

  // ============================================================
  // LIFECYCLE DE L'APP
  // Huawei EMUI tue les timers en background → on re-sync
  // automatiquement et complètement au retour foreground
  // ============================================================
  void setAppForeground(bool isForeground) {
    final wasInBackground = !_isAppInForeground;
    _isAppInForeground = isForeground;
    _bgGraceTimer?.cancel();

    if (isForeground) {
      _logLifecycle.info('Foreground (était bg: $wasInBackground)');
      if (wasInBackground) {
        // Huawei/EMUI peut avoir tué nos timers → tout relancer
        _stopPolling();
        // Re-fetch seulement si dernier fetch > 30s (éviter burst)
        final sinceLastFetch = _lastFetch != null
            ? DateTime.now().difference(_lastFetch!).inSeconds
            : 999;
        if (sinceLastFetch > 30) {
          loadMatches();
        } else {
          _logLifecycle.info('Skip reload (fetched ${sinceLastFetch}s ago)');
          _startSmartPolling();
        }
      } else {
        _executePoll();
        if (_smartTimer == null || !_smartTimer!.isActive) {
          _startSmartPolling();
        }
      }
    } else {
      _logLifecycle.info('Background → smart polling continue');
      // Garder le polling actif tant que possible
      // Huawei peut tuer après quelques minutes, c'est OK :
      // on re-sync tout au retour foreground
      _bgGraceTimer = Timer(const Duration(hours: 1), () {
        _logLifecycle.info('Background prolongé → arrêt polling');
        _stopPolling();
      });
    }
  }

  Future<void> refreshMatches() async {
    _logRefresh.info('Rafraîchissement manuel');
    await _executePoll();
  }

  FootballMatch? getMatchById(int matchId) {
    try {
      return _allMatches.firstWhere((m) => m.id == matchId);
    } catch (e) {
      return _hiveService.getCachedMatch(matchId);
    }
  }

  /// Charge le détail complet d'un match (événements + stats)
  Future<FootballMatch?> fetchMatchDetail(int matchId) async {
    // Essayer apifootball.com d'abord
    if (_apiSportsService.hasApiKey) {
      try {
        final detail = await _apiSportsService.fetchMatchDetail(matchId);
        if (detail != null) return detail;
      } catch (_) {}
    }
    return _apiService.fetchMatchDetail(matchId);
  }

  /// Détail complet d'un match (événements + stats + compositions)
  Future<MatchDetailData?> fetchMatchDetailFull(int matchId) async {
    if (_apiSportsService.hasApiKey) {
      try {
        final detail = await _apiSportsService.fetchMatchDetailFull(matchId);
        if (detail != null) return detail;
      } catch (_) {}
    }
    return _apiService.fetchMatchDetailFull(matchId);
  }

  Future<Map<String, Lineup>?> fetchLineups(int matchId) =>
      _apiService.fetchLineups(matchId);

  String get lastUpdateAgo {
    if (_lastFetch == null) return 'Jamais';
    final diff = DateTime.now().difference(_lastFetch!);
    if (diff.inSeconds < 60) return 'Il y a ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    return 'Il y a ${diff.inHours}h';
  }

  // ============================================================
  // REALTIME SUPABASE
  // ============================================================
  void listenToRealtimeUpdates() {
    _supabaseService.subscribeToMatchUpdates((payload) {
      final matchId = payload['id'] as int?;
      if (matchId == null) return;

      final idx = _allMatches.indexWhere((m) => m.id == matchId);
      if (idx >= 0) {
        final old = _allMatches[idx];
        _allMatches[idx] = old.copyWith(
          score: Score(
            homeFullTime: payload['home_score'] as int?,
            awayFullTime: payload['away_score'] as int?,
          ),
          statusStr: payload['status'] as String?,
          minute: payload['minute'] as int?,
        );
        notifyListeners();
      }
    });
  }

  /// Met à jour la clé API apifootball.com
  Future<void> updateApiSportsKey(String key) async {
    _apiSportsService.setApiKey(key);
    await _hiveService.saveApiSportsKey(key);
    // Recharger les matchs avec la nouvelle clé
    await loadMatches();
  }

  @override
  void dispose() {
    _stopPolling();
    _bgGraceTimer?.cancel();
    _supabaseService.unsubscribeFromMatchUpdates();
    super.dispose();
  }
}

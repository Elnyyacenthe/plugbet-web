// ============================================================
// Plugbet – Service Hive (cache local + favoris)
// ============================================================

import 'package:hive_flutter/hive_flutter.dart';
import '../models/football_models.dart';

class HiveService {
  // Singleton
  static final HiveService _instance = HiveService._internal();
  factory HiveService() => _instance;
  HiveService._internal();

  static const String matchesBoxName = 'matches_cache';
  static const String favoritesBoxName = 'favorites';
  static const String settingsBoxName = 'settings';

  late Box<FootballMatch> _matchesBox;
  late Box<int> _favoritesBox; // Stocke les IDs des équipes favorites
  late Box<dynamic> _settingsBox;

  // --- Initialisation globale (appelée dans main.dart) ---
  static Future<void> initHive() async {
    await Hive.initFlutter();

    // Enregistrer les adaptateurs
    Hive.registerAdapter(CompetitionAdapter());
    Hive.registerAdapter(TeamAdapter());
    Hive.registerAdapter(ScoreAdapter());
    Hive.registerAdapter(FootballMatchAdapter());
    Hive.registerAdapter(MatchEventAdapter());
    Hive.registerAdapter(MatchStatsAdapter());
    Hive.registerAdapter(PlayerAdapter());
    Hive.registerAdapter(LineupAdapter());
  }

  /// Ouvre toutes les boxes nécessaires
  Future<void> openBoxes() async {
    _matchesBox = await Hive.openBox<FootballMatch>(matchesBoxName);
    _favoritesBox = await Hive.openBox<int>(favoritesBoxName);
    _settingsBox = await Hive.openBox(settingsBoxName);
  }

  // ============================================================
  // CACHE DES MATCHS
  // ============================================================

  /// Sauvegarder une liste de matchs dans le cache
  Future<void> cacheMatches(List<FootballMatch> matches) async {
    // Limiter à 50 matchs en cache
    final matchesToCache = matches.take(50).toList();
    await _matchesBox.clear();
    for (final match in matchesToCache) {
      await _matchesBox.put(match.id, match);
    }
  }

  /// Mettre à jour un seul match dans le cache
  Future<void> updateCachedMatch(FootballMatch match) async {
    await _matchesBox.put(match.id, match);
  }

  /// Récupérer tous les matchs du cache
  List<FootballMatch> getCachedMatches() {
    return _matchesBox.values.toList();
  }

  /// Récupérer un match spécifique du cache
  FootballMatch? getCachedMatch(int matchId) {
    return _matchesBox.get(matchId);
  }

  /// Dernière mise à jour (timestamp du plus récent match en cache)
  DateTime? getLastUpdateTime() {
    if (_matchesBox.isEmpty) return null;
    final matches = _matchesBox.values.toList();
    matches.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return matches.first.lastUpdated;
  }

  // ============================================================
  // FAVORIS (IDs d'équipes)
  // ============================================================

  /// Ajouter une équipe aux favoris
  Future<void> addFavoriteTeam(int teamId) async {
    if (!_favoritesBox.values.contains(teamId)) {
      await _favoritesBox.add(teamId);
    }
  }

  /// Supprimer une équipe des favoris
  Future<void> removeFavoriteTeam(int teamId) async {
    final key = _favoritesBox.keys.firstWhere(
      (k) => _favoritesBox.get(k) == teamId,
      orElse: () => null,
    );
    if (key != null) {
      await _favoritesBox.delete(key);
    }
  }

  /// Vérifier si une équipe est en favori
  bool isFavoriteTeam(int teamId) {
    return _favoritesBox.values.contains(teamId);
  }

  /// Récupérer tous les IDs d'équipes favorites
  List<int> getFavoriteTeamIds() {
    return _favoritesBox.values.toList();
  }

  /// Basculer le statut favori d'une équipe
  Future<bool> toggleFavoriteTeam(int teamId) async {
    if (isFavoriteTeam(teamId)) {
      await removeFavoriteTeam(teamId);
      return false;
    } else {
      await addFavoriteTeam(teamId);
      return true;
    }
  }

  // ============================================================
  // HISTORIQUE DE RECHERCHES (priorité dynamique)
  // ============================================================

  /// Incrémente le compteur de recherche pour un terme
  Future<void> trackSearch(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return;
    final map = getSearchHistory();
    map[q] = (map[q] ?? 0) + 1;
    await _settingsBox.put('search_history', map);
  }

  /// Incrémente le compteur quand un match est vu en détail (+5)
  Future<void> trackMatchView(String teamName) async {
    final q = teamName.trim().toLowerCase();
    if (q.isEmpty) return;
    final map = getSearchHistory();
    map[q] = (map[q] ?? 0) + 5;
    await _settingsBox.put('search_history', map);
  }

  /// Récupère l'historique {terme: compteur}
  Map<String, int> getSearchHistory() {
    final raw = _settingsBox.get('search_history');
    if (raw == null) return {};
    if (raw is Map) {
      return Map<String, int>.from(
        raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      );
    }
    return {};
  }

  /// Efface l'historique de recherches
  Future<void> clearSearchHistory() async {
    await _settingsBox.delete('search_history');
  }

  /// Efface tout le cache
  Future<void> clearAllCache() async {
    await _matchesBox.clear();
    await _settingsBox.delete('search_history');
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  /// Sauvegarder un paramètre
  Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  /// Lire un paramètre
  T? getSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue) as T?;
  }

  /// Clé API-Football v3
  String? getApiSportsKey() {
    return _settingsBox.get('api_sports_key') as String?;
  }

  Future<void> saveApiSportsKey(String key) async {
    await _settingsBox.put('api_sports_key', key);
  }

  /// Fermer toutes les boxes
  Future<void> closeAll() async {
    await _matchesBox.close();
    await _favoritesBox.close();
    await _settingsBox.close();
  }
}

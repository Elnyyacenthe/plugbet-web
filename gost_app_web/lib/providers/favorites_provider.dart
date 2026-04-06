// ============================================================
// Plugbet – Provider des favoris
// Stockage local Hive + sync optionnelle Supabase
// ============================================================

import 'package:flutter/foundation.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';

class FavoritesProvider extends ChangeNotifier {
  final HiveService _hiveService;
  final SupabaseService _supabaseService;

  List<int> _favoriteTeamIds = [];
  List<int> get favoriteTeamIds => _favoriteTeamIds;

  FavoritesProvider({
    required HiveService hiveService,
    required SupabaseService supabaseService,
  })  : _hiveService = hiveService,
        _supabaseService = supabaseService;

  /// Charger les favoris depuis Hive (+ sync Supabase si connecté)
  Future<void> loadFavorites() async {
    // Charger d'abord depuis Hive (instantané)
    _favoriteTeamIds = _hiveService.getFavoriteTeamIds();
    notifyListeners();

    // Puis sync depuis Supabase si connecté
    if (_supabaseService.currentUserId != null) {
      try {
        final remoteFavorites = await _supabaseService.fetchFavoriteTeamIds();
        if (remoteFavorites.isNotEmpty) {
          // Fusionner : garder tous les favoris locaux + distants
          final merged = <int>{..._favoriteTeamIds, ...remoteFavorites}.toList();
          _favoriteTeamIds = merged;

          // Mettre à jour Hive avec la fusion
          for (final id in merged) {
            if (!_hiveService.isFavoriteTeam(id)) {
              await _hiveService.addFavoriteTeam(id);
            }
          }
          notifyListeners();
        }
      } catch (e) {
        // Silencieux, on garde les favoris locaux
      }
    }
  }

  /// Basculer le statut favori d'une équipe
  Future<void> toggleFavorite(int teamId) async {
    final isNowFavorite = await _hiveService.toggleFavoriteTeam(teamId);

    if (isNowFavorite) {
      _favoriteTeamIds.add(teamId);
      _supabaseService.addFavoriteTeam(teamId);
    } else {
      _favoriteTeamIds.remove(teamId);
      _supabaseService.removeFavoriteTeam(teamId);
    }
    notifyListeners();
  }

  /// Vérifier si une équipe est en favori
  bool isFavorite(int teamId) => _favoriteTeamIds.contains(teamId);
}

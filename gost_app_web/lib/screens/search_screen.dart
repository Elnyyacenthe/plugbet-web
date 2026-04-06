// ============================================================
// Plugbet – Ecran de recherche
// Rechercher des matchs par nom d'equipe ou competition
// Tracking de l'historique pour priorite dynamique
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/football_models.dart';
import '../providers/matches_provider.dart';
import '../services/hive_service.dart';
import '../widgets/match_card.dart';
import 'match_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  final HiveService hiveService;

  const SearchScreen({super.key, required this.hiveService});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FootballMatch> _filterMatches(List<FootballMatch> all) {
    if (_query.isEmpty) return [];
    final q = _query.toLowerCase();
    return all.where((m) {
      return m.homeTeam.name.toLowerCase().contains(q) ||
          m.awayTeam.name.toLowerCase().contains(q) ||
          m.homeTeam.shortName.toLowerCase().contains(q) ||
          m.awayTeam.shortName.toLowerCase().contains(q) ||
          (m.homeTeam.tla?.toLowerCase().contains(q) ?? false) ||
          (m.awayTeam.tla?.toLowerCase().contains(q) ?? false) ||
          m.competition.name.toLowerCase().contains(q);
    }).toList();
  }

  void _onSearchSubmitted(String value) {
    if (value.trim().isNotEmpty) {
      widget.hiveService.trackSearch(value.trim());
    }
  }

  void _navigateToDetail(FootballMatch match) {
    // Tracker la vue detail (+5 pour chaque equipe)
    widget.hiveService.trackMatchView(match.homeTeam.name);
    widget.hiveService.trackMatchView(match.awayTeam.name);
    widget.hiveService.trackSearch(match.competition.name);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MatchDetailScreen(matchId: match.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tete
              Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Rechercher',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -1,
                  ),
                ),
              ),

              // Barre de recherche
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider, width: 0.5),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Equipe, competition...',
                      hintStyle: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 15,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: AppColors.textMuted,
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close, size: 18),
                              color: AppColors.textMuted,
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                    onSubmitted: _onSearchSubmitted,
                  ),
                ),
              ),

              // Resultats
              Expanded(
                child: Consumer<MatchesProvider>(
                  builder: (context, provider, _) {
                    final results = _filterMatches(provider.allMatches);

                    if (_query.isEmpty) {
                      return _buildInitialState();
                    }

                    if (results.isEmpty) {
                      return _buildNoResultsState();
                    }

                    return ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final match = results[index];
                        return MatchCard(
                          match: match,
                          onTap: () => _navigateToDetail(match),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: 48,
            color: AppColors.textMuted.withValues(alpha: 0.3),
          ),
          SizedBox(height: 12),
          Text(
            'Recherchez une equipe ou une competition',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: AppColors.textMuted.withValues(alpha: 0.3),
          ),
          SizedBox(height: 12),
          Text(
            'Aucun resultat pour "$_query"',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

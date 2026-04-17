// ============================================================
// Plugbet – Ecran des favoris
// Matchs des equipes favorites + gestion des favoris
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/matches_provider.dart';
import '../providers/favorites_provider.dart';
import '../widgets/match_card.dart';
import 'match_detail_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(AppLocalizations.of(context)!.favoritesTitle),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tete
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  'Équipes favorites',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -1,
                  ),
                ),
              ),

              // Contenu
              Expanded(
                child: Consumer2<MatchesProvider, FavoritesProvider>(
                  builder: (context, matchesProvider, favProvider, _) {
                    final favoriteIds = favProvider.favoriteTeamIds;

                    if (favoriteIds.isEmpty) {
                      return _buildEmptyState();
                    }

                    final favoriteMatches =
                        matchesProvider.getFavoriteMatches(favoriteIds);

                    if (favoriteMatches.isEmpty) {
                      return _buildNoMatchesState();
                    }

                    return ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: favoriteMatches.length,
                      itemBuilder: (context, index) {
                        final match = favoriteMatches[index];
                        return MatchCard(
                          match: match,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    MatchDetailScreen(matchId: match.id),
                              ),
                            );
                          },
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_outline_rounded,
              size: 64,
              color: AppColors.neonYellow.withValues(alpha: 0.3),
            ),
            SizedBox(height: 16),
            Text(
              'Aucun favori pour le moment',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Appuyez sur l\'etoile dans la page de detail\n'
              'd\'un match pour ajouter une equipe en favori.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchesState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_soccer,
              size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.4),
            ),
            SizedBox(height: 16),
            Text(
              'Pas de matchs aujourd\'hui',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Vos equipes favorites ne jouent pas aujourd\'hui.\nRevenez demain !',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

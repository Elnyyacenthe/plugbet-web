// ============================================================
// Constantes du hub Jeux — catalogue + paramètres + JS injection
// ============================================================
// Phase 1 : catalogue HARDCODÉ. Une source de vérité ici, pourra
// basculer vers une table Supabase `games_catalog` plus tard sans
// toucher au reste du code.
// ============================================================

import '../models/game_category.dart';
import '../models/game_model.dart';

// ── Bornes / défauts globaux ────────────────────────────────
const int kGameEntryPriceMin = 0;
const int kGameEntryPriceMax = 1000;
const int kGameSessionDefaultMinutes = 5;
const int kGameSessionMaxMinutes = 30;

/// Préfixe des request_id envoyés au wallet (idempotence du débit).
const String kGameSessionRequestPrefix = 'games_hub_session';

// ── Grille (responsive) ─────────────────────────────────────
const double kGameCardMinWidth = 160;
const double kGameCardAspectRatio = 0.78;

// ── JS injection par défaut Poki ────────────────────────────
const String kPokiHideUiInjection = r"""
(function() {
  try {
    var killSelectors = [
      'header', '.site-header', '#site-header',
      'aside', '.sidebar', '.layout__sidebar',
      '.ad', '[id*="ad-"]', '[class*="ad-"]',
      'footer', '.site-footer'
    ];
    killSelectors.forEach(function(sel) {
      document.querySelectorAll(sel).forEach(function(el) {
        el.style.display = 'none';
      });
    });
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement('meta');
      meta.name = 'viewport';
      document.head.appendChild(meta);
    }
    meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
    document.documentElement.style.background = '#000';
    document.body.style.margin = '0';
    document.body.style.background = '#000';
  } catch(e) { /* silencieux */ }
})();
""";

// ── Catalogue initial ───────────────────────────────────────
const List<GameModel> kInitialGamesCatalog = [
  GameModel(
    id: 'penalty_shooters_2',
    slug: 'penalty-shooters-2',
    title: 'Penalty Shooters 2',
    description: 'Tirs au but : enchaîne les penaltys, deviens champion.',
    category: GameCategory.sport,
    provider: GameProvider.poki,
    embedUrl: 'https://poki.com/fr/g/penalty-shooters-2',
    thumbnailAsset: 'assets/games/penalty_shooters_2.jpg',
    entryPriceCoins: 50,
    sessionDurationMinutes: 5,
    featured: true,
    tags: ['sport', 'football', 'penalty'],
  ),
];

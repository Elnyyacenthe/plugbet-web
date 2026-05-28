// ============================================================
// Catégories de jeux — enum + métadonnées d'affichage
// ============================================================
// Switch exhaustif côté UI (filtres, icônes), évite les magic strings.
// ============================================================

import 'package:flutter/material.dart';

enum GameCategory {
  sport,
  arcade,
  action,
  puzzle,
  racing,
  casual;

  String get label {
    switch (this) {
      case GameCategory.sport:  return 'Sport';
      case GameCategory.arcade: return 'Arcade';
      case GameCategory.action: return 'Action';
      case GameCategory.puzzle: return 'Réflexion';
      case GameCategory.racing: return 'Course';
      case GameCategory.casual: return 'Détente';
    }
  }

  IconData get icon {
    switch (this) {
      case GameCategory.sport:  return Icons.sports_soccer_rounded;
      case GameCategory.arcade: return Icons.videogame_asset_rounded;
      case GameCategory.action: return Icons.bolt_rounded;
      case GameCategory.puzzle: return Icons.extension_rounded;
      case GameCategory.racing: return Icons.directions_car_rounded;
      case GameCategory.casual: return Icons.celebration_rounded;
    }
  }

  String toJson() => name;

  static GameCategory fromJson(String raw) =>
      GameCategory.values.firstWhere(
        (c) => c.name == raw,
        orElse: () => GameCategory.casual,
      );
}

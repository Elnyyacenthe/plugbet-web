// ============================================================
// Plugbet – Lecture centralisée des réglages de jeu depuis Hive
// ============================================================

import 'hive_service.dart';

/// Accès rapide aux réglages de jeu stockés dans Hive.
/// Tous les jeux lisent ces valeurs pour adapter leur comportement.
class GameSettings {
  static final GameSettings instance = GameSettings._();
  GameSettings._();

  HiveService? _hive;
  HiveService get _h {
    _hive ??= HiveService();
    return _hive!;
  }

  // ─── Difficulté IA ─────────────────────────────────────────
  /// 'Facile', 'Moyen', 'Difficile'
  String get aiDifficulty => _h.getSetting<String>('ai_difficulty') ?? 'Moyen';

  /// Probabilité que l'IA fasse le meilleur coup (0.0 - 1.0)
  double get aiBestMoveChance {
    switch (aiDifficulty) {
      case 'Facile':    return 0.25;
      case 'Difficile': return 0.85;
      default:          return 0.55; // Moyen
    }
  }

  // ─── Gameplay ──────────────────────────────────────────────
  bool get undoEnabled => _h.getSetting<bool>('undo_enabled') ?? true;
  bool get hintsEnabled => _h.getSetting<bool>('hints_enabled') ?? false;
  int  get defaultBet => _h.getSetting<int>('default_bet') ?? 100;
  bool get trainingMode => _h.getSetting<bool>('training_mode') ?? false;

  // ─── Vibration ─────────────────────────────────────────────
  bool get vibrationEnabled => _h.getSetting<bool>('game_vibration') ?? true;
  bool get vibrationOnEvents => _h.getSetting<bool>('vibration_events') ?? true;

  // ─── Chat en jeu ───────────────────────────────────────────
  bool get inGameChat => _h.getSetting<bool>('in_game_chat') ?? true;
}

// ============================================================
// GamesHubProvider — catalogue + filtre + session active
// ============================================================
// Source de vérité unique côté client. State minimal Phase 2 :
// catalogue constant, catégorie sélectionnée, session active +
// timer de countdown. Pas de persistance (mémoire seule).
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../constants/games_constants.dart';
import '../models/game_category.dart';
import '../models/game_model.dart';
import '../services/games_hub_service.dart';

class ActiveGameSession {
  final GameModel game;
  final String sessionId;
  final DateTime startedAt;
  final DateTime expiresAt;
  const ActiveGameSession({
    required this.game,
    required this.sessionId,
    required this.startedAt,
    required this.expiresAt,
  });

  Duration get remaining {
    final r = expiresAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class GamesHubProvider extends ChangeNotifier {
  final List<GameModel> _all = kInitialGamesCatalog;
  GameCategory? _selectedCategory;
  ActiveGameSession? _active;
  Timer? _tick;
  bool _starting = false;

  // ── Getters ───────────────────────────────────────────────
  List<GameModel> get all => _all.where((g) => g.isEnabled).toList();

  List<GameModel> get filtered {
    final list = all;
    final cat = _selectedCategory;
    if (cat == null) return list;
    return list.where((g) => g.category == cat).toList();
  }

  Set<GameCategory> get availableCategories =>
      all.map((g) => g.category).toSet();

  GameCategory? get selectedCategory => _selectedCategory;
  ActiveGameSession? get activeSession => _active;
  bool get hasActiveSession => _active != null;
  bool get isStartingSession => _starting;

  // ── Actions ───────────────────────────────────────────────
  void selectCategory(GameCategory? cat) {
    if (_selectedCategory == cat) return;
    _selectedCategory = cat;
    notifyListeners();
  }

  Future<bool> startSession(GameModel game) async {
    if (_active != null) return false;
    if (_starting) return false;
    _starting = true;
    notifyListeners();
    try {
      final sessionId =
          '$kGameSessionRequestPrefix:${game.id}:${DateTime.now().microsecondsSinceEpoch}';
      final ok = await GamesHubService.instance
          .startSession(game: game, sessionId: sessionId);
      if (!ok) return false;

      final now = DateTime.now();
      _active = ActiveGameSession(
        game: game,
        sessionId: sessionId,
        startedAt: now,
        expiresAt: now.add(Duration(minutes: game.sessionDurationMinutes)),
      );
      _startTick();
      return true;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> endSession({required String reason}) async {
    final s = _active;
    if (s == null) return;
    _stopTick();
    _active = null;
    notifyListeners();
    // ignore: discarded_futures
    GamesHubService.instance
        .endSession(game: s.game, sessionId: s.sessionId, reason: reason);
  }

  // ── Countdown ─────────────────────────────────────────────
  void _startTick() {
    _stopTick();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _active;
      if (s == null) { _stopTick(); return; }
      if (s.isExpired) {
        endSession(reason: 'expired');
        return;
      }
      notifyListeners();
    });
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _stopTick();
    super.dispose();
  }
}

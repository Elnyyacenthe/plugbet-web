// ============================================================
// LIVE SCORE MANAGER - Gestion intelligente des scores en direct
// Polling adaptatif, détection de changements, notifications
// ============================================================

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import '../models/football_models.dart';
import 'api_football_service.dart';

class LiveScoreManager extends ChangeNotifier {
  final ApiFootballService _apiService;

  Timer? _pollTimer;
  final Map<int, FootballMatch> _liveMatches = {};
  final _goalController = StreamController<String>.broadcast();

  // Configuration adaptative
  Duration _pollInterval = const Duration(seconds: 30);
  bool _isAppInForeground = true;
  bool _isTracking = false;

  LiveScoreManager(this._apiService);

  Stream<String> get goalStream => _goalController.stream;
  List<FootballMatch> get liveMatches => _liveMatches.values.toList();
  bool get hasLiveMatches => _liveMatches.isNotEmpty;

  /// Démarrer le suivi en temps réel
  void startLiveTracking() {
    if (_isTracking) return;

    _isTracking = true;
    debugPrint('[LIVE] Démarrage du tracking des scores en direct');

    // Premier fetch immédiat
    _fetchLiveScores();

    // Polling périodique
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (timer) {
      _adjustPollInterval();
      _fetchLiveScores();
    });
  }

  /// Arrêter le suivi
  void stopLiveTracking() {
    _isTracking = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('[LIVE] Arrêt du tracking');
  }

  /// Suspendre temporairement (pendant un jeu)
  void pauseTracking() {
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('[LIVE] Pause tracking (jeu actif)');
  }

  /// Reprendre après un jeu
  void resumeTracking() {
    if (!_isTracking) return;
    debugPrint('[LIVE] Reprise tracking');
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (timer) {
      _adjustPollInterval();
      _fetchLiveScores();
    });
  }

  /// Ajuster l'intervalle de polling selon le contexte
  void _adjustPollInterval() {
    if (!_isAppInForeground) {
      // En background: très lent pour économiser la batterie
      _pollInterval = const Duration(minutes: 3);
    } else if (_liveMatches.isEmpty) {
      // Pas de matchs live: polling normal
      _pollInterval = const Duration(seconds: 60);
    } else {
      // Matchs live en cours: très rapide
      _pollInterval = const Duration(seconds: 15);
    }
  }

  /// Récupérer les scores en direct
  Future<void> _fetchLiveScores() async {
    if (!_isTracking) return;

    try {
      debugPrint('[LIVE] Fetching scores... (interval: ${_pollInterval.inSeconds}s)');

      final newMatches = await _apiService.fetchLiveMatches();

      // Mettre à jour et détecter les changements
      for (var newMatch in newMatches) {
        final oldMatch = _liveMatches[newMatch.id];

        if (oldMatch != null) {
          _detectAndNotifyChanges(oldMatch, newMatch);
        } else {
          // Nouveau match live détecté
          debugPrint('[LIVE] Nouveau match détecté: ${newMatch.homeTeam.shortName} vs ${newMatch.awayTeam.shortName}');
        }

        _liveMatches[newMatch.id] = newMatch;
      }

      // Retirer les matchs terminés
      _liveMatches.removeWhere((id, match) {
        final isStillLive = newMatches.any((m) => m.id == id);
        if (!isStillLive && match.status.isLive) {
          debugPrint('[LIVE] Match terminé: ${match.homeTeam.shortName} vs ${match.awayTeam.shortName}');
        }
        return !isStillLive;
      });

      notifyListeners();
    } catch (e) {
      debugPrint('[LIVE] Erreur lors du fetch: $e');
    }
  }

  /// Détecter les changements et envoyer des notifications
  void _detectAndNotifyChanges(FootballMatch oldMatch, FootballMatch newMatch) {
    final homeScoreOld = oldMatch.score.homeFullTime ?? 0;
    final awayScoreOld = oldMatch.score.awayFullTime ?? 0;
    final homeScoreNew = newMatch.score.homeFullTime ?? 0;
    final awayScoreNew = newMatch.score.awayFullTime ?? 0;

    // Nouveau but domicile
    if (homeScoreNew > homeScoreOld) {
      debugPrint('[LIVE] ⚽ BUT! ${newMatch.homeTeam.shortName} - Score: $homeScoreNew-$awayScoreNew');
      _goalController.add('${newMatch.homeTeam.shortName} marque ! $homeScoreNew-$awayScoreNew');
      _triggerHapticFeedback();
    }

    // Nouveau but extérieur
    if (awayScoreNew > awayScoreOld) {
      debugPrint('[LIVE] ⚽ BUT! ${newMatch.awayTeam.shortName} - Score: $homeScoreNew-$awayScoreNew');
      _goalController.add('${newMatch.awayTeam.shortName} marque ! $homeScoreNew-$awayScoreNew');
      _triggerHapticFeedback();
    }

    // Changement de statut (début de match, mi-temps, fin)
    if (oldMatch.statusStr != newMatch.statusStr) {
      debugPrint('[LIVE] Changement de statut: ${oldMatch.statusStr} → ${newMatch.statusStr}');

      if (newMatch.status == MatchStatus.inPlay && oldMatch.status == MatchStatus.timed) {
        // Coup d'envoi !
        _triggerHapticFeedback(strength: HapticStrength.light);
      } else if (newMatch.status == MatchStatus.paused) {
        // Mi-temps
        _triggerHapticFeedback(strength: HapticStrength.light);
      } else if (newMatch.status == MatchStatus.finished) {
        // Match terminé
        _triggerHapticFeedback(strength: HapticStrength.medium);
      }
    }
  }

  /// Retour haptique pour engagement utilisateur
  void _triggerHapticFeedback({HapticStrength strength = HapticStrength.heavy}) {
    if (!_isAppInForeground) return; // Pas de vibration en background

    switch (strength) {
      case HapticStrength.light:
        HapticFeedback.lightImpact();
        break;
      case HapticStrength.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticStrength.heavy:
        HapticFeedback.heavyImpact();
        break;
    }
  }

  /// Réagir aux changements de cycle de vie de l'app
  void onAppLifecycleChange(AppLifecycleState state) {
    final wasForeground = _isAppInForeground;
    _isAppInForeground = state == AppLifecycleState.resumed;

    if (_isAppInForeground && !wasForeground) {
      // L'app revient en foreground: fetch immédiat
      debugPrint('[LIVE] App en foreground - fetch immédiat');
      _fetchLiveScores();
    }

    _adjustPollInterval();
  }

  /// Forcer un refresh manuel
  Future<void> refresh() async {
    await _fetchLiveScores();
  }

  /// Obtenir un match spécifique avec ses détails
  Future<FootballMatch?> getMatchDetails(int matchId) async {
    try {
      return await _apiService.fetchMatchDetail(matchId);
    } catch (e) {
      debugPrint('[LIVE] Erreur lors du fetch des détails: $e');
      return null;
    }
  }

  @override
  void dispose() {
    stopLiveTracking();
    _goalController.close();
    super.dispose();
  }
}

enum HapticStrength {
  light,
  medium,
  heavy,
}

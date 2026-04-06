// ============================================================
// FANTASY – Moteur de scoring + Auto-substitution
// Calcule les points GW depuis l'API FPL live
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/fpl_models.dart';
import 'fpl_service.dart';
import 'fantasy_service.dart';

class FplScoringService {
  static final FplScoringService instance = FplScoringService._();
  FplScoringService._();

  final _fpl = FplService.instance;
  final _fantasy = FantasyService.instance;

  /// Calcule et met à jour les points du GW pour l'équipe de l'utilisateur.
  /// Gère : captain (x2), vice-captain, bench boost, triple captain, auto-sub.
  Future<ScoringResult?> calculateAndSync({
    required FplBootstrap bootstrap,
  }) async {
    try {
      final gw = bootstrap.currentEvent;
      if (gw == null) return null;

      // 1. Récupérer les données live du GW
      final liveData = await _fpl.fetchLiveGw(gw.id);
      if (liveData == null) return null;

      // 2. Récupérer l'équipe de l'utilisateur
      final team = await _fantasy.getMyTeam();
      if (team == null) return null;
      final teamId = team['id'] as String;
      final picks = await _fantasy.getPicks(teamId);
      if (picks.isEmpty) return null;

      // 3. Récupérer les chips actifs
      final chipsUsed = await _fantasy.getChipsUsed(teamId);
      final isBenchBoost = chipsUsed.contains('bench_boost');
      final isTripleCaptain = chipsUsed.contains('triple_captain');

      // 4. Séparer starters et bench (triés par bench_order)
      final starters = picks.where((p) => p['is_starter'] == true).toList();
      final bench = picks.where((p) => p['is_starter'] != true).toList()
        ..sort((a, b) =>
            (a['bench_order'] as int? ?? 99)
                .compareTo(b['bench_order'] as int? ?? 99));

      // 5. Auto-substitution : remplacer les starters qui n'ont pas joué
      final activeStarters = <Map<String, dynamic>>[];
      final autoSubs = <AutoSub>[];

      for (final starter in starters) {
        final elemId = starter['element_id'] as int;
        final live = liveData[elemId];
        final played = (live?.stats.minutes ?? 0) > 0;

        if (played) {
          activeStarters.add(starter);
        } else {
          // Chercher un remplaçant éligible sur le banc
          Map<String, dynamic>? replacement;
          for (final b in bench) {
            if (activeStarters.any((s) => s['element_id'] == b['element_id'])) continue;
            if (autoSubs.any((s) => s.inElementId == b['element_id'])) continue;
            final bLive = liveData[b['element_id'] as int];
            if ((bLive?.stats.minutes ?? 0) > 0) {
              replacement = b;
              break;
            }
          }

          if (replacement != null) {
            activeStarters.add(replacement);
            autoSubs.add(AutoSub(
              outElementId: elemId,
              inElementId: replacement['element_id'] as int,
            ));
          } else {
            // Pas de remplaçant → le starter reste avec 0 pts
            activeStarters.add(starter);
          }
        }
      }

      // 6. Calculer les points
      int totalPoints = 0;
      final playerPoints = <int, int>{};

      // Points des starters (ou auto-subs)
      for (final s in activeStarters) {
        final elemId = s['element_id'] as int;
        final live = liveData[elemId];
        int pts = live?.stats.totalPoints ?? 0;

        // Captain bonus
        final isCap = s['is_captain'] == true;
        final isVC = s['is_vice_captain'] == true;

        if (isCap) {
          pts *= isTripleCaptain ? 3 : 2;
        } else if (isVC) {
          // VC ne double que si le captain n'a pas joué
          final capPick = starters.firstWhere(
              (p) => p['is_captain'] == true,
              orElse: () => s);
          final capLive = liveData[capPick['element_id'] as int];
          if ((capLive?.stats.minutes ?? 0) == 0) {
            pts *= isTripleCaptain ? 3 : 2;
          }
        }

        playerPoints[elemId] = pts;
        totalPoints += pts;
      }

      // Bench Boost : ajouter les points du banc
      if (isBenchBoost) {
        for (final b in bench) {
          final elemId = b['element_id'] as int;
          if (autoSubs.any((s) => s.inElementId == elemId)) continue;
          final live = liveData[elemId];
          final pts = live?.stats.totalPoints ?? 0;
          playerPoints[elemId] = pts;
          totalPoints += pts;
        }
      }

      // 7. Sauvegarder dans Supabase
      await _fantasy.updateTeamPoints(teamId, totalPoints);

      debugPrint('[SCORING] GW${gw.id}: $totalPoints pts (${autoSubs.length} auto-subs, '
          'benchBoost=$isBenchBoost, tripleCap=$isTripleCaptain)');

      return ScoringResult(
        gameweek: gw.id,
        totalPoints: totalPoints,
        playerPoints: playerPoints,
        autoSubs: autoSubs,
        isBenchBoost: isBenchBoost,
        isTripleCaptain: isTripleCaptain,
      );
    } catch (e) {
      debugPrint('[SCORING] Error: $e');
      return null;
    }
  }
}

// ─── Result models ────────────────────────────────────────

class ScoringResult {
  final int gameweek;
  final int totalPoints;
  final Map<int, int> playerPoints; // elementId → points
  final List<AutoSub> autoSubs;
  final bool isBenchBoost;
  final bool isTripleCaptain;

  const ScoringResult({
    required this.gameweek,
    required this.totalPoints,
    required this.playerPoints,
    required this.autoSubs,
    required this.isBenchBoost,
    required this.isTripleCaptain,
  });
}

class AutoSub {
  final int outElementId;
  final int inElementId;
  const AutoSub({required this.outElementId, required this.inElementId});
}

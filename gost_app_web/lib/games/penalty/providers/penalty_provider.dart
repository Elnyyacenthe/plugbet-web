// ============================================================
// PenaltyProvider — state du round courant + historique des tirs
// ============================================================
// Source de vérité unique côté client. Encapsule les appels service +
// les flags de UI (loading start/shoot/abandon). Mémoire seule (un
// round actif à la fois ; le serveur est autoritatif).
// ============================================================

import 'package:flutter/foundation.dart';
import '../models/penalty_models.dart';
import '../services/penalty_service.dart';

class PenaltyProvider extends ChangeNotifier {
  final PenaltyService _svc = PenaltyService.instance;

  PenaltyRound? _round;
  final List<PenaltyShotResult> _shots = [];
  bool _starting = false;
  bool _shooting = false;
  bool _abandoning = false;
  String? _error;

  // ── Getters ───────────────────────────────────────────────
  PenaltyRound? get round => _round;
  List<PenaltyShotResult> get shots => List.unmodifiable(_shots);
  bool get hasActiveRound =>
      _round != null && _round!.status == PenaltyRoundStatus.active;
  bool get isStarting => _starting;
  bool get isShooting => _shooting;
  bool get isAbandoning => _abandoning;
  String? get error => _error;

  int get nextShotIndex => (_round?.shotsTaken ?? 0) + 1;

  PenaltyShotResult? get lastShot => _shots.isEmpty ? null : _shots.last;

  // ── Actions ───────────────────────────────────────────────

  /// Démarre un nouveau round. Le service débite la mise côté serveur.
  /// Renvoie true si OK ; sinon `error` contient le message.
  Future<bool> startRound({required int betAmount, int totalShots = 5}) async {
    if (_starting || hasActiveRound) return false;
    _starting = true;
    _error = null;
    _shots.clear();
    notifyListeners();
    try {
      _round = await _svc.startRound(
        betAmount: betAmount,
        totalShots: totalShots,
      );
      return true;
    } catch (e) {
      _error = _formatError(e);
      _round = null;
      return false;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  /// Tire un coup. Renvoie le résultat (ou null si erreur).
  Future<PenaltyShotResult?> takeShot(PenaltyDirection direction) async {
    final r = _round;
    if (r == null || !hasActiveRound) return null;
    if (_shooting) return null;
    _shooting = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _svc.takeShot(
        roundId: r.id,
        shotIndex: nextShotIndex,
        playerDirection: direction,
      );
      // Anti double-shot : ignore les retours idempotents qui correspondent
      // déjà à un tir présent dans l'historique.
      if (!res.idempotent ||
          !_shots.any((s) => s.shotIndex == res.shotIndex)) {
        _shots.add(res);
      }
      // MAJ du round avec les compteurs serveur.
      _round = r.copyWith(
        goals: res.goalsSoFar,
        misses: res.missesSoFar,
        status: res.roundFinished ? res.roundStatus : r.status,
      );
      return res;
    } catch (e) {
      _error = _formatError(e);
      return null;
    } finally {
      _shooting = false;
      notifyListeners();
    }
  }

  /// Abandonne le round actif (sortie volontaire = mise perdue).
  Future<void> abandonRound() async {
    final r = _round;
    if (r == null || !hasActiveRound) return;
    if (_abandoning) return;
    _abandoning = true;
    notifyListeners();
    try {
      await _svc.abandonRound(r.id);
      _round = r.copyWith(status: PenaltyRoundStatus.abandoned);
    } finally {
      _abandoning = false;
      notifyListeners();
    }
  }

  /// Nettoie le state pour un nouveau round (après fin / abandon / retour
  /// à l'écran de mise).
  void reset() {
    _round = null;
    _shots.clear();
    _error = null;
    notifyListeners();
  }

  String _formatError(Object e) {
    final s = e.toString();
    if (s.contains('INSUFFICIENT_FUNDS')) return 'Solde insuffisant';
    if (s.contains('INVALID_BET_RANGE')) return 'Mise hors limites (10–1000)';
    if (s.contains('INVALID_SHOTS_RANGE')) return 'Nombre de tirs invalide';
    if (s.contains('ROUND_NOT_FOUND')) return 'Round introuvable';
    if (s.contains('NOT_OWNER')) return 'Round non autorisé';
    if (s.contains('OUT_OF_ORDER_SHOT')) return 'Tir hors séquence';
    if (s.contains('NOT_AUTH')) return 'Non authentifié';
    return s;
  }
}

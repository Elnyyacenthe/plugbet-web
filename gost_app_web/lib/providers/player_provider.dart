// ============================================================
// PlayerProvider – État joueur (XP, Rang, Stats, Historique)
// ============================================================

import 'package:flutter/material.dart';
import '../models/player_models.dart';
import '../services/player_service.dart';

class PlayerProvider extends ChangeNotifier {
  final PlayerService _service = PlayerService.instance;

  // ── Getters ───────────────────────────────────────────────

  int get xp => _service.getXp();
  PlayerRank get rank => _service.getRank();
  double get progress => rankProgress(xp);
  int get winStreak => _service.getWinStreak();
  int get bestWinStreak => _service.getBestWinStreak();

  GameTypeStats get totalStats => _service.getTotalStats();
  GameTypeStats statsFor(String gameType) => _service.getGameStats(gameType);

  List<GameHistoryEntry> get history => _service.getHistory();
  Set<String> get unlockedAchievements => _service.getUnlockedAchievements();
  int get achievementCount => unlockedAchievements.length;

  int get dailyStreak => _service.getDailyStreak();
  bool get canClaimDaily => _service.canClaimToday();

  // ── Actions ───────────────────────────────────────────────

  /// Enregistre un résultat de partie et notifie les listeners
  Future<int> recordGameResult({
    required String gameType,
    required String result,
    int coinsChange = 0,
    int? opponentRankTier,
    String? opponentName,
    int? score,
    bool isPractice = false,
  }) async {
    final xpGained = await _service.recordGameResult(
      gameType: gameType,
      result: result,
      coinsChange: coinsChange,
      opponentRankTier: opponentRankTier,
      opponentName: opponentName,
      score: score,
      isPractice: isPractice,
    );
    // Sync au serveur
    _service.syncTotalWins();
    notifyListeners();
    return xpGained;
  }

  /// Réclamer la récompense quotidienne
  Future<int> claimDailyReward() async {
    final coins = await _service.claimDailyReward();
    notifyListeners();
    return coins;
  }

  /// Vérifier les achievements liés aux coins
  Future<void> checkCoinAchievements(int coins) async {
    await _service.checkCoinAchievements(coins);
    notifyListeners();
  }

  /// Forcer le refresh UI
  void refresh() => notifyListeners();

  // ── Leaderboard ───────────────────────────────────────────

  Future<List<LeaderboardEntry>> fetchLeaderboard({String? gameType}) =>
      _service.fetchLeaderboard(gameType: gameType);

  // ── Friends ───────────────────────────────────────────────

  Future<List<FriendModel>> getFriends() => _service.getFriends();

  Future<List<FriendRequest>> getPendingRequests() =>
      _service.getPendingRequests();

  Future<bool> sendFriendRequest(String toUserId) =>
      _service.sendFriendRequest(toUserId);

  Future<bool> acceptFriendRequest(String requestId, String fromId) async {
    final ok = await _service.acceptFriendRequest(requestId, fromId);
    if (ok) notifyListeners();
    return ok;
  }

  Future<bool> declineFriendRequest(String requestId) async {
    final ok = await _service.declineFriendRequest(requestId);
    if (ok) notifyListeners();
    return ok;
  }
}

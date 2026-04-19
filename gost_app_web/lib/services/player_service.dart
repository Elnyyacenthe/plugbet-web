// ============================================================
// PlayerService – XP, Rang, Stats, Historique, Achievements
// Stockage local Hive + sync Supabase
// ============================================================

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player_models.dart';
import '../utils/logger.dart';
import 'hive_service.dart';

const _logBoard = Logger('LEADERBOARD');
const _logFriends = Logger('FRIENDS');

class PlayerService {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  HiveService get _hive => HiveService();
  SupabaseClient get _sb => Supabase.instance.client;
  String? get _userId => _sb.auth.currentUser?.id;

  // ── XP & Rang ─────────────────────────────────────────────

  int getXp() => _hive.getSetting<int>('player_xp') ?? 0;

  PlayerRank getRank() => rankFromXp(getXp());

  Future<int> addXp(int amount) async {
    final current = getXp();
    final newXp = current + amount;
    await _hive.saveSetting('player_xp', newXp);
    // Sync Supabase (best effort)
    _syncXpToSupabase(newXp);
    // Check rank achievements
    _checkRankAchievements(newXp);
    return newXp;
  }

  void _syncXpToSupabase(int xp) {
    if (_userId == null) return;
    try {
      _sb.from('user_profiles').update({
        'xp': xp,
        'rank': rankFromXp(xp).label,
      }).eq('id', _userId!).then((_) {});
    } catch (_) {}
  }

  // ── Stats par jeu ─────────────────────────────────────────

  GameTypeStats getGameStats(String gameType) {
    final raw = _hive.getSetting<String>('stats_$gameType');
    if (raw == null) return const GameTypeStats();
    try {
      return GameTypeStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const GameTypeStats();
    }
  }

  Future<void> _saveGameStats(String gameType, GameTypeStats stats) async {
    await _hive.saveSetting('stats_$gameType', jsonEncode(stats.toJson()));
  }

  /// Total toutes les stats combinées
  GameTypeStats getTotalStats() {
    int wins = 0, losses = 0, draws = 0, coinsWon = 0, coinsLost = 0, gamesPlayed = 0;
    for (final g in ['checkers', 'solitaire', 'cora', 'ludo']) {
      final s = getGameStats(g);
      wins += s.wins;
      losses += s.losses;
      draws += s.draws;
      coinsWon += s.coinsWon;
      coinsLost += s.coinsLost;
      gamesPlayed += s.gamesPlayed;
    }
    return GameTypeStats(
      wins: wins,
      losses: losses,
      draws: draws,
      coinsWon: coinsWon,
      coinsLost: coinsLost,
      gamesPlayed: gamesPlayed,
    );
  }

  // ── Win Streak ────────────────────────────────────────────

  int getWinStreak() => _hive.getSetting<int>('win_streak') ?? 0;
  int getBestWinStreak() => _hive.getSetting<int>('best_win_streak') ?? 0;

  Future<void> _updateStreak(bool isWin) async {
    if (isWin) {
      final streak = getWinStreak() + 1;
      await _hive.saveSetting('win_streak', streak);
      final best = getBestWinStreak();
      if (streak > best) {
        await _hive.saveSetting('best_win_streak', streak);
      }
      // Check streak achievements
      if (streak >= 3) await unlockAchievement('streak_3');
      if (streak >= 5) await unlockAchievement('streak_5');
      if (streak >= 10) await unlockAchievement('streak_10');
    } else {
      await _hive.saveSetting('win_streak', 0);
    }
  }

  // ── Enregistrer un résultat de partie ─────────────────────

  /// Appel principal après chaque fin de partie
  /// Retourne l'XP gagné
  Future<int> recordGameResult({
    required String gameType,
    required String result, // 'win', 'loss', 'draw'
    int coinsChange = 0,
    int? opponentRankTier, // tier de rang adverse (0=bronze...5=maître)
    String? opponentName,
    int? score,
    bool isPractice = false,
  }) async {
    // 1) Calculer XP
    int xp = 0;
    if (result == 'win') {
      xp = isPractice ? 5 : 30;
      // Bonus si adversaire de rang supérieur
      if (opponentRankTier != null) {
        final myTier = getRank().tier;
        final diff = opponentRankTier - myTier;
        if (diff > 0) {
          xp += (diff * 10).clamp(0, 60);
        }
      }
    } else if (result == 'loss') {
      // Moins d'XP en perte, plus si adversaire fort
      xp = isPractice ? 2 : 5;
      if (opponentRankTier != null) {
        final myTier = getRank().tier;
        final diff = opponentRankTier - myTier;
        if (diff > 0) xp += (diff * 5).clamp(0, 30);
      }
    } else {
      xp = isPractice ? 3 : 10;
    }

    // 2) Appliquer XP
    await addXp(xp);

    // 3) Update stats par jeu
    final stats = getGameStats(gameType);
    await _saveGameStats(
      gameType,
      stats.copyWith(
        wins: stats.wins + (result == 'win' ? 1 : 0),
        losses: stats.losses + (result == 'loss' ? 1 : 0),
        draws: stats.draws + (result == 'draw' ? 1 : 0),
        coinsWon: stats.coinsWon + (coinsChange > 0 ? coinsChange : 0),
        coinsLost: stats.coinsLost + (coinsChange < 0 ? coinsChange.abs() : 0),
        bestScore: score != null && score > stats.bestScore ? score : stats.bestScore,
        gamesPlayed: stats.gamesPlayed + 1,
      ),
    );

    // 4) Update streak
    await _updateStreak(result == 'win');

    // 5) Ajouter à l'historique
    await addHistory(GameHistoryEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      gameType: gameType,
      date: DateTime.now(),
      result: result,
      coinsChange: coinsChange,
      xpGained: xp,
      opponentName: opponentName,
      score: score,
    ));

    // 6) Check achievements
    await _checkAllAchievements(gameType, coinsChange);

    return xp;
  }

  // ── Historique ────────────────────────────────────────────

  List<GameHistoryEntry> getHistory() {
    final raw = _hive.getSetting<String>('game_history');
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => GameHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addHistory(GameHistoryEntry entry) async {
    final list = getHistory();
    list.insert(0, entry);
    // Garder max 50 entrées
    final trimmed = list.take(50).toList();
    await _hive.saveSetting(
      'game_history',
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  // ── Achievements ──────────────────────────────────────────

  Set<String> getUnlockedAchievements() {
    final raw = _hive.getSetting<String>('achievements');
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  Future<bool> unlockAchievement(String id) async {
    final set = getUnlockedAchievements();
    if (set.contains(id)) return false;
    set.add(id);
    await _hive.saveSetting(
      'achievements',
      jsonEncode(set.toList()),
    );
    return true;
  }

  void _checkRankAchievements(int xp) {
    final rank = rankFromXp(xp);
    if (rank.tier >= PlayerRank.argent.tier) unlockAchievement('rank_argent');
    if (rank.tier >= PlayerRank.or_.tier) unlockAchievement('rank_or');
    if (rank.tier >= PlayerRank.diamant.tier) unlockAchievement('rank_diamant');
  }

  Future<void> _checkAllAchievements(String gameType, int currentCoins) async {
    final total = getTotalStats();
    final gameStats = getGameStats(gameType);

    // Victoires globales
    if (total.wins >= 1) await unlockAchievement('first_win');
    if (total.wins >= 10) await unlockAchievement('wins_10');
    if (total.wins >= 50) await unlockAchievement('wins_50');
    if (total.wins >= 100) await unlockAchievement('wins_100');

    // Jeux joués
    if (total.gamesPlayed >= 10) await unlockAchievement('games_10');
    if (total.gamesPlayed >= 50) await unlockAchievement('games_50');
    if (total.gamesPlayed >= 100) await unlockAchievement('games_100');

    // Par jeu
    if (gameType == 'checkers' && gameStats.wins >= 10) {
      await unlockAchievement('checkers_10');
    }
    if (gameType == 'solitaire' && gameStats.wins >= 10) {
      await unlockAchievement('solitaire_10');
    }
    if (gameType == 'cora' && gameStats.wins >= 10) {
      await unlockAchievement('cora_10');
    }

    // Coins (vérifier via le solde actuel passé)
    if (currentCoins >= 5000) await unlockAchievement('rich_5k');
    if (currentCoins >= 10000) await unlockAchievement('rich_10k');
  }

  /// Vérifier le bonus de coins
  Future<void> checkCoinAchievements(int coins) async {
    if (coins >= 5000) await unlockAchievement('rich_5k');
    if (coins >= 10000) await unlockAchievement('rich_10k');
  }

  // ── Daily Rewards ─────────────────────────────────────────

  int getDailyStreak() => _hive.getSetting<int>('daily_streak') ?? 0;

  String? getLastClaimDate() => _hive.getSetting<String>('daily_last_claim');

  bool canClaimToday() {
    final last = getLastClaimDate();
    if (last == null) return true;
    final lastDate = DateTime.tryParse(last);
    if (lastDate == null) return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(lastDate.year, lastDate.month, lastDate.day);
    return today.isAfter(lastDay);
  }

  /// Retourne les coins gagnés, ou 0 si déjà réclamé
  Future<int> claimDailyReward() async {
    if (!canClaimToday()) return 0;

    final last = getLastClaimDate();
    int streak = getDailyStreak();

    if (last != null) {
      final lastDate = DateTime.tryParse(last);
      if (lastDate != null) {
        final now = DateTime.now();
        final yesterday = DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 1));
        final lastDay =
            DateTime(lastDate.year, lastDate.month, lastDate.day);
        if (lastDay.isBefore(yesterday)) {
          // Streak cassé
          streak = 0;
        }
      }
    }

    // Jour dans le cycle (0-6)
    final dayIndex = streak % dailyRewardCoins.length;
    final coins = dailyRewardCoins[dayIndex];

    // Sauvegarder
    await _hive.saveSetting('daily_streak', streak + 1);
    await _hive.saveSetting(
        'daily_last_claim', DateTime.now().toIso8601String());

    // Check achievement
    if (streak + 1 >= 7) await unlockAchievement('daily_7');

    return coins;
  }

  // ── Leaderboard ───────────────────────────────────────────

  Future<List<LeaderboardEntry>> fetchLeaderboard({String? gameType}) async {
    try {
      // Essayer avec xp + total_wins (si colonnes existent)
      try {
        final data = await _sb
            .from('user_profiles')
            .select('id, username, coins, xp, total_wins')
            .order('xp', ascending: false)
            .limit(50);

        if (data.isNotEmpty) {
          return data.map((row) {
            final xp = (row['xp'] as int?) ?? 0;
            return LeaderboardEntry(
              oddsId: row['id'] as String? ?? '',
              username: row['username'] as String? ?? 'Joueur',
              xp: xp,
              rank: rankFromXp(xp),
              wins: (row['total_wins'] as int?) ?? 0,
              coins: (row['coins'] as int?) ?? 0,
              isCurrentUser: row['id'] == _userId,
            );
          }).toList();
        }
      } catch (e) {
        _logBoard.info('xp query failed: $e');
      }

      // Fallback: utiliser coins comme métrique de classement
      final data = await _sb
          .from('user_profiles')
          .select('id, username, coins')
          .order('coins', ascending: false)
          .limit(50);

      if (data.isNotEmpty) {
        return data.map((row) {
          final coins = (row['coins'] as int?) ?? 0;
          return LeaderboardEntry(
            oddsId: row['id'] as String? ?? '',
            username: row['username'] as String? ?? 'Joueur',
            xp: 0,
            rank: PlayerRank.bronze,
            wins: 0,
            coins: coins,
            isCurrentUser: row['id'] == _userId,
          );
        }).toList();
      }

      return [];
    } catch (e) {
      _logBoard.info('fetchLeaderboard error: $e');
      return [];
    }
  }

  // ── Friends ───────────────────────────────────────────────

  Future<List<FriendModel>> getFriends() async {
    if (_userId == null) return [];
    try {
      // Chercher les amitiés acceptées
      final data = await _sb
          .from('friendships')
          .select('friend_id, user_profiles!friendships_friend_id_fkey(username, xp)')
          .eq('user_id', _userId!)
          .eq('status', 'accepted');

      return (data as List).map((row) {
        final profile = row['user_profiles'] as Map<String, dynamic>? ?? {};
        final xp = (profile['xp'] as int?) ?? 0;
        return FriendModel(
          oddsId: row['friend_id'] as String? ?? '',
          username: profile['username'] as String? ?? 'Joueur',
          xp: xp,
          rank: rankFromXp(xp),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<FriendRequest>> getPendingRequests() async {
    if (_userId == null) return [];
    try {
      final data = await _sb
          .from('friend_requests')
          .select('id, from_id, created_at')
          .eq('to_id', _userId!)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final results = <FriendRequest>[];
      for (final row in (data as List)) {
        final fromId = row['from_id'] as String? ?? '';
        // Charger le profil de l'expéditeur
        String username = 'Joueur';
        int xp = 0;
        try {
          final profile = await _sb
              .from('user_profiles')
              .select('username, xp')
              .eq('id', fromId)
              .maybeSingle();
          if (profile != null) {
            username = profile['username'] as String? ?? 'Joueur';
            xp = (profile['xp'] as int?) ?? 0;
          }
        } catch (_) {}

        results.add(FriendRequest(
          id: row['id'] as String? ?? '',
          fromId: fromId,
          fromUsername: username,
          fromXp: xp,
          sentAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now(),
        ));
      }
      _logFriends.info('${results.length} demandes en attente');
      return results;
    } catch (e) {
      _logFriends.info('getPendingRequests ERROR: $e');
      return [];
    }
  }

  Future<bool> sendFriendRequest(String toUserId) async {
    if (_userId == null) {
      _logFriends.info('sendFriendRequest: userId is null');
      return false;
    }
    try {
      await _sb.from('friend_requests').insert({
        'from_id': _userId,
        'to_id': toUserId,
        'status': 'pending',
      });
      _logFriends.info('Demande envoyée à $toUserId');
      return true;
    } catch (e) {
      _logFriends.info('sendFriendRequest ERROR: $e');
      return false;
    }
  }

  Future<bool> acceptFriendRequest(String requestId, String fromId) async {
    if (_userId == null) return false;
    try {
      // Mettre à jour la requête
      await _sb
          .from('friend_requests')
          .update({'status': 'accepted'})
          .eq('id', requestId);
      // Créer UNE seule relation (la SELECT policy couvre les deux directions)
      await _sb.from('friendships').insert(
        {'user_id': _userId, 'friend_id': fromId, 'status': 'accepted'},
      );
      _logFriends.info('Amitié acceptée: $fromId');
      return true;
    } catch (e) {
      _logFriends.info('acceptFriendRequest ERROR: $e');
      return false;
    }
  }

  Future<bool> declineFriendRequest(String requestId) async {
    try {
      await _sb
          .from('friend_requests')
          .update({'status': 'declined'})
          .eq('id', requestId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sync total wins to Supabase for leaderboard
  Future<void> syncTotalWins() async {
    if (_userId == null) return;
    try {
      final total = getTotalStats();
      await _sb.from('user_profiles').update({
        'total_wins': total.wins,
        'xp': getXp(),
        'rank': getRank().label,
      }).eq('id', _userId!);
    } catch (_) {}
  }
}

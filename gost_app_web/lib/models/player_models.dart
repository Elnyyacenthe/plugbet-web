// ============================================================
// Modèles Joueur – Rang, Stats, Historique, Achievements
// ============================================================

import 'package:flutter/material.dart';

// ── Rangs du joueur ────────────────────────────────────────
enum PlayerRank {
  bronze,
  argent,
  or_,
  platine,
  diamant,
  maitre,
}

extension PlayerRankX on PlayerRank {
  String get label {
    switch (this) {
      case PlayerRank.bronze:
        return 'Bronze';
      case PlayerRank.argent:
        return 'Argent';
      case PlayerRank.or_:
        return 'Or';
      case PlayerRank.platine:
        return 'Platine';
      case PlayerRank.diamant:
        return 'Diamant';
      case PlayerRank.maitre:
        return 'Maître';
    }
  }

  IconData get icon {
    switch (this) {
      case PlayerRank.bronze:
        return Icons.shield_outlined;
      case PlayerRank.argent:
        return Icons.shield;
      case PlayerRank.or_:
        return Icons.workspace_premium;
      case PlayerRank.platine:
        return Icons.military_tech;
      case PlayerRank.diamant:
        return Icons.diamond;
      case PlayerRank.maitre:
        return Icons.emoji_events;
    }
  }

  Color get color {
    switch (this) {
      case PlayerRank.bronze:
        return const Color(0xFFCD7F32);
      case PlayerRank.argent:
        return const Color(0xFFC0C0C0);
      case PlayerRank.or_:
        return const Color(0xFFFFD700);
      case PlayerRank.platine:
        return const Color(0xFF00E5FF);
      case PlayerRank.diamant:
        return const Color(0xFFE040FB);
      case PlayerRank.maitre:
        return const Color(0xFFFF1744);
    }
  }

  /// XP minimum pour atteindre ce rang
  int get minXp {
    switch (this) {
      case PlayerRank.bronze:
        return 0;
      case PlayerRank.argent:
        return 500;
      case PlayerRank.or_:
        return 1500;
      case PlayerRank.platine:
        return 3500;
      case PlayerRank.diamant:
        return 7000;
      case PlayerRank.maitre:
        return 15000;
    }
  }

  /// XP max de ce rang (avant le prochain)
  int get maxXp {
    switch (this) {
      case PlayerRank.bronze:
        return 499;
      case PlayerRank.argent:
        return 1499;
      case PlayerRank.or_:
        return 3499;
      case PlayerRank.platine:
        return 6999;
      case PlayerRank.diamant:
        return 14999;
      case PlayerRank.maitre:
        return 99999;
    }
  }

  /// Rang suivant (null si Maître)
  PlayerRank? get next {
    final vals = PlayerRank.values;
    final idx = vals.indexOf(this);
    return idx < vals.length - 1 ? vals[idx + 1] : null;
  }

  /// Index numérique pour comparaison
  int get tier => PlayerRank.values.indexOf(this);
}

/// Calcule le rang à partir de l'XP total
PlayerRank rankFromXp(int xp) {
  if (xp >= 15000) return PlayerRank.maitre;
  if (xp >= 7000) return PlayerRank.diamant;
  if (xp >= 3500) return PlayerRank.platine;
  if (xp >= 1500) return PlayerRank.or_;
  if (xp >= 500) return PlayerRank.argent;
  return PlayerRank.bronze;
}

/// Progression dans le rang actuel (0.0 → 1.0)
double rankProgress(int xp) {
  final rank = rankFromXp(xp);
  if (rank == PlayerRank.maitre) return 1.0;
  final min = rank.minXp;
  final max = rank.maxXp + 1;
  return ((xp - min) / (max - min)).clamp(0.0, 1.0);
}

// ── Stats par type de jeu ──────────────────────────────────
class GameTypeStats {
  final int wins;
  final int losses;
  final int draws;
  final int coinsWon;
  final int coinsLost;
  final int bestScore;
  final int gamesPlayed;

  const GameTypeStats({
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.coinsWon = 0,
    this.coinsLost = 0,
    this.bestScore = 0,
    this.gamesPlayed = 0,
  });

  double get winRate =>
      gamesPlayed > 0 ? (wins / gamesPlayed * 100) : 0;

  Map<String, dynamic> toJson() => {
        'wins': wins,
        'losses': losses,
        'draws': draws,
        'coinsWon': coinsWon,
        'coinsLost': coinsLost,
        'bestScore': bestScore,
        'gamesPlayed': gamesPlayed,
      };

  factory GameTypeStats.fromJson(Map<String, dynamic> json) => GameTypeStats(
        wins: json['wins'] as int? ?? 0,
        losses: json['losses'] as int? ?? 0,
        draws: json['draws'] as int? ?? 0,
        coinsWon: json['coinsWon'] as int? ?? 0,
        coinsLost: json['coinsLost'] as int? ?? 0,
        bestScore: json['bestScore'] as int? ?? 0,
        gamesPlayed: json['gamesPlayed'] as int? ?? 0,
      );

  GameTypeStats copyWith({
    int? wins,
    int? losses,
    int? draws,
    int? coinsWon,
    int? coinsLost,
    int? bestScore,
    int? gamesPlayed,
  }) =>
      GameTypeStats(
        wins: wins ?? this.wins,
        losses: losses ?? this.losses,
        draws: draws ?? this.draws,
        coinsWon: coinsWon ?? this.coinsWon,
        coinsLost: coinsLost ?? this.coinsLost,
        bestScore: bestScore ?? this.bestScore,
        gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      );
}

// ── Entrée historique de partie ────────────────────────────
class GameHistoryEntry {
  final String id;
  final String gameType; // 'checkers', 'solitaire', 'cora', 'ludo'
  final DateTime date;
  final String result; // 'win', 'loss', 'draw'
  final int coinsChange;
  final int xpGained;
  final String? opponentName;
  final int? score;

  const GameHistoryEntry({
    required this.id,
    required this.gameType,
    required this.date,
    required this.result,
    this.coinsChange = 0,
    this.xpGained = 0,
    this.opponentName,
    this.score,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameType': gameType,
        'date': date.toIso8601String(),
        'result': result,
        'coinsChange': coinsChange,
        'xpGained': xpGained,
        'opponentName': opponentName,
        'score': score,
      };

  factory GameHistoryEntry.fromJson(Map<String, dynamic> json) =>
      GameHistoryEntry(
        id: json['id'] as String? ?? '',
        gameType: json['gameType'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
        result: json['result'] as String? ?? 'loss',
        coinsChange: json['coinsChange'] as int? ?? 0,
        xpGained: json['xpGained'] as int? ?? 0,
        opponentName: json['opponentName'] as String?,
        score: json['score'] as int?,
      );

  String get gameLabel {
    switch (gameType) {
      case 'checkers':
        return 'Dames';
      case 'solitaire':
        return 'Solitaire';
      case 'cora':
        return 'Cora Dice';
      case 'ludo':
        return 'Ludo';
      default:
        return gameType;
    }
  }

  String get gameEmoji {
    switch (gameType) {
      case 'checkers':
        return '♟️';
      case 'solitaire':
        return '🃏';
      case 'cora':
        return '🎲';
      case 'ludo':
        return '🎯';
      default:
        return '🎮';
    }
  }
}

// ── Achievement / Badge ────────────────────────────────────
class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

/// Liste complète des achievements disponibles
const List<Achievement> allAchievements = [
  // Victoires globales
  Achievement(
    id: 'first_win',
    title: 'Première Victoire',
    description: 'Gagner sa première partie',
    icon: Icons.star,
    color: Color(0xFFFFD700),
  ),
  Achievement(
    id: 'wins_10',
    title: 'Victorieux',
    description: 'Gagner 10 parties',
    icon: Icons.emoji_events,
    color: Color(0xFFFF9100),
  ),
  Achievement(
    id: 'wins_50',
    title: 'Dominateur',
    description: 'Gagner 50 parties',
    icon: Icons.military_tech,
    color: Color(0xFFE040FB),
  ),
  Achievement(
    id: 'wins_100',
    title: 'Légende',
    description: 'Gagner 100 parties',
    icon: Icons.auto_awesome,
    color: Color(0xFFFF1744),
  ),
  // Séries
  Achievement(
    id: 'streak_3',
    title: 'Série de 3',
    description: '3 victoires consécutives',
    icon: Icons.local_fire_department,
    color: Color(0xFFFF6D00),
  ),
  Achievement(
    id: 'streak_5',
    title: 'En feu',
    description: '5 victoires consécutives',
    icon: Icons.whatshot,
    color: Color(0xFFFF1744),
  ),
  Achievement(
    id: 'streak_10',
    title: 'Inarrêtable',
    description: '10 victoires consécutives',
    icon: Icons.bolt,
    color: Color(0xFFFFD600),
  ),
  // Coins
  Achievement(
    id: 'rich_5k',
    title: 'Riche',
    description: 'Avoir 5 000 coins',
    icon: Icons.monetization_on,
    color: Color(0xFF00E676),
  ),
  Achievement(
    id: 'rich_10k',
    title: 'Millionnaire',
    description: 'Avoir 10 000 coins',
    icon: Icons.diamond,
    color: Color(0xFF00E5FF),
  ),
  // Par jeu
  Achievement(
    id: 'checkers_10',
    title: 'Roi des Dames',
    description: 'Gagner 10 parties de Dames',
    icon: Icons.grid_on,
    color: Color(0xFF8D6E63),
  ),
  Achievement(
    id: 'solitaire_10',
    title: 'Maître Solitaire',
    description: 'Gagner 10 parties de Solitaire',
    icon: Icons.style,
    color: Color(0xFF9C27B0),
  ),
  Achievement(
    id: 'cora_10',
    title: 'As du Cora',
    description: 'Gagner 10 parties de Cora Dice',
    icon: Icons.casino,
    color: Color(0xFF448AFF),
  ),
  // Rang
  Achievement(
    id: 'rank_argent',
    title: 'Rang Argent',
    description: 'Atteindre le rang Argent',
    icon: Icons.shield,
    color: Color(0xFFC0C0C0),
  ),
  Achievement(
    id: 'rank_or',
    title: 'Rang Or',
    description: 'Atteindre le rang Or',
    icon: Icons.workspace_premium,
    color: Color(0xFFFFD700),
  ),
  Achievement(
    id: 'rank_diamant',
    title: 'Rang Diamant',
    description: 'Atteindre le rang Diamant',
    icon: Icons.diamond,
    color: Color(0xFFE040FB),
  ),
  // Jeux joués
  Achievement(
    id: 'games_10',
    title: 'Joueur Régulier',
    description: 'Jouer 10 parties',
    icon: Icons.sports_esports,
    color: Color(0xFF448AFF),
  ),
  Achievement(
    id: 'games_50',
    title: 'Passionné',
    description: 'Jouer 50 parties',
    icon: Icons.videogame_asset,
    color: Color(0xFF00E676),
  ),
  Achievement(
    id: 'games_100',
    title: 'Accro',
    description: 'Jouer 100 parties',
    icon: Icons.gamepad,
    color: Color(0xFFFF1744),
  ),
  // Daily
  Achievement(
    id: 'daily_7',
    title: 'Fidèle',
    description: 'Se connecter 7 jours de suite',
    icon: Icons.calendar_month,
    color: Color(0xFF00E5FF),
  ),
];

// ── Récompenses quotidiennes ───────────────────────────────
const List<int> dailyRewardCoins = [100, 150, 200, 300, 500, 750, 1000];

// ── Entrée classement ──────────────────────────────────────
class LeaderboardEntry {
  final String oddsId;
  final String username;
  final int xp;
  final PlayerRank rank;
  final int wins;
  final int coins;
  final bool isCurrentUser;

  const LeaderboardEntry({
    required this.oddsId,
    required this.username,
    required this.xp,
    required this.rank,
    required this.wins,
    this.coins = 0,
    this.isCurrentUser = false,
  });
}

// ── Ami ────────────────────────────────────────────────────
class FriendModel {
  final String oddsId;
  final String username;
  final int xp;
  final PlayerRank rank;
  final String status; // 'online', 'in_game', 'offline'
  final DateTime? lastSeen;

  const FriendModel({
    required this.oddsId,
    required this.username,
    required this.xp,
    required this.rank,
    this.status = 'offline',
    this.lastSeen,
  });
}

class FriendRequest {
  final String id;
  final String fromId;
  final String fromUsername;
  final int fromXp;
  final DateTime sentAt;

  const FriendRequest({
    required this.id,
    required this.fromId,
    required this.fromUsername,
    required this.fromXp,
    required this.sentAt,
  });
}

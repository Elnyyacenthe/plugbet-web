// ============================================================
// CORA DICE - Modèles de données
// Jeu de dés camerounais virtuel (coins uniquement)
// ============================================================

import 'dart:convert';

/// Statut d'une room Cora
enum CoraRoomStatus { waiting, playing, finished, cancelled }

CoraRoomStatus coraRoomStatusFromString(String s) {
  switch (s) {
    case 'playing':
      return CoraRoomStatus.playing;
    case 'finished':
      return CoraRoomStatus.finished;
    case 'cancelled':
      return CoraRoomStatus.cancelled;
    default:
      return CoraRoomStatus.waiting;
  }
}

/// Résultat d'un lancer de dés
class DiceRoll {
  final int dice1;
  final int dice2;
  final DateTime timestamp;

  const DiceRoll({
    required this.dice1,
    required this.dice2,
    required this.timestamp,
  });

  int get total => dice1 + dice2;
  bool get isCora => dice1 == 1 && dice2 == 1;
  bool get isSeven => total == 7;

  factory DiceRoll.fromJson(Map<String, dynamic> json) {
    return DiceRoll(
      dice1: json['dice1'] as int,
      dice2: json['dice2'] as int,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'dice1': dice1,
        'dice2': dice2,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Joueur dans une partie Cora
class CoraPlayer {
  final String userId;
  final String username;
  final bool isReady;
  final DiceRoll? roll;
  final int? finalScore; // null = pas encore joué, -1 = 7 (perd auto)

  const CoraPlayer({
    required this.userId,
    required this.username,
    this.isReady = false,
    this.roll,
    this.finalScore,
  });

  bool get hasRolled => roll != null;
  bool get hasCora => roll?.isCora ?? false;
  bool get hasSeven => roll?.isSeven ?? false;

  factory CoraPlayer.fromJson(Map<String, dynamic> json) {
    return CoraPlayer(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? 'Joueur',
      isReady: json['is_ready'] as bool? ?? false,
      roll: json['roll'] != null
          ? DiceRoll.fromJson(json['roll'] as Map<String, dynamic>)
          : null,
      finalScore: json['final_score'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'is_ready': isReady,
        'roll': roll?.toJson(),
        'final_score': finalScore,
      };

  CoraPlayer copyWith({
    String? userId,
    String? username,
    bool? isReady,
    DiceRoll? roll,
    int? finalScore,
  }) =>
      CoraPlayer(
        userId: userId ?? this.userId,
        username: username ?? this.username,
        isReady: isReady ?? this.isReady,
        roll: roll ?? this.roll,
        finalScore: finalScore ?? this.finalScore,
      );
}

/// État du jeu Cora
class CoraGameState {
  final Map<String, CoraPlayer> players;
  final String? currentTurn;
  final List<String> winners; // Peut avoir plusieurs gagnants si Cora
  final bool isFinished;
  final String? result; // Description du résultat

  const CoraGameState({
    required this.players,
    this.currentTurn,
    this.winners = const [],
    this.isFinished = false,
    this.result,
  });

  factory CoraGameState.initial(List<Map<String, String>> playersList) {
    final players = <String, CoraPlayer>{};
    for (final p in playersList) {
      players[p['user_id']!] = CoraPlayer(
        userId: p['user_id']!,
        username: p['username']!,
      );
    }

    return CoraGameState(
      players: players,
      currentTurn: playersList.first['user_id'],
    );
  }

  factory CoraGameState.fromJson(Map<String, dynamic> json) {
    final playersRaw = json['players'] as Map<String, dynamic>? ?? {};
    final players = <String, CoraPlayer>{};
    for (final entry in playersRaw.entries) {
      players[entry.key] =
          CoraPlayer.fromJson(entry.value as Map<String, dynamic>);
    }

    return CoraGameState(
      players: players,
      currentTurn: json['current_turn'] as String?,
      winners: (json['winners'] as List?)?.cast<String>() ?? [],
      isFinished: json['is_finished'] as bool? ?? false,
      result: json['result'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'players': players.map((k, v) => MapEntry(k, v.toJson())),
        'current_turn': currentTurn,
        'winners': winners,
        'is_finished': isFinished,
        'result': result,
      };

  bool get allPlayersRolled => players.values.every((p) => p.hasRolled);
  int get coraCount => players.values.where((p) => p.hasCora).length;
  List<CoraPlayer> get coraPlayers =>
      players.values.where((p) => p.hasCora).toList();
}

/// Room Cora Dice
class CoraRoom {
  final String id;
  final String code;
  final String hostId;
  final int playerCount;
  final int betAmount;
  final bool isPrivate;
  final CoraRoomStatus status;
  final String? gameId;
  final DateTime createdAt;
  final String? hostUsername;

  const CoraRoom({
    required this.id,
    required this.code,
    required this.hostId,
    required this.playerCount,
    this.betAmount = 200,
    this.isPrivate = false,
    this.status = CoraRoomStatus.waiting,
    this.gameId,
    required this.createdAt,
    this.hostUsername,
  });

  int get potAmount => betAmount * playerCount;

  factory CoraRoom.fromJson(Map<String, dynamic> json) {
    return CoraRoom(
      id: json['id'] as String,
      code: json['code'] as String,
      hostId: json['host_id'] as String,
      playerCount: json['player_count'] as int? ?? 2,
      betAmount: json['bet_amount'] as int? ?? 200,
      isPrivate: json['is_private'] as bool? ?? false,
      status: coraRoomStatusFromString(json['status'] as String? ?? 'waiting'),
      gameId: json['game_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      hostUsername: json['host_username'] as String?,
    );
  }
}

/// Partie Cora complète
class CoraGame {
  final String id;
  final String roomId;
  final int betAmount;
  final int playerCount;
  final CoraGameState gameState;
  final CoraRoomStatus status;
  final List<String> winnerIds;
  final DateTime createdAt;

  const CoraGame({
    required this.id,
    required this.roomId,
    required this.betAmount,
    required this.playerCount,
    required this.gameState,
    required this.status,
    this.winnerIds = const [],
    required this.createdAt,
  });

  int get potAmount => betAmount * playerCount;
  bool get hasMultipleCora => gameState.coraCount > 1;
  bool get isCancelled => status == CoraRoomStatus.cancelled;

  factory CoraGame.fromJson(Map<String, dynamic> json) {
    final stateData = json['game_state'];
    final Map<String, dynamic> stateMap;
    if (stateData is String) {
      stateMap = jsonDecode(stateData) as Map<String, dynamic>;
    } else {
      stateMap = stateData as Map<String, dynamic>;
    }

    return CoraGame(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      betAmount: json['bet_amount'] as int? ?? 200,
      playerCount: json['player_count'] as int? ?? 2,
      gameState: CoraGameState.fromJson(stateMap),
      status: coraRoomStatusFromString(json['status'] as String? ?? 'playing'),
      winnerIds: (json['winner_ids'] as List?)?.cast<String>() ?? [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Message de chat
class CoraMessage {
  final String id;
  final String roomId;
  final String userId;
  final String username;
  final String message;
  final DateTime createdAt;

  const CoraMessage({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.username,
    required this.message,
    required this.createdAt,
  });

  factory CoraMessage.fromJson(Map<String, dynamic> json) {
    return CoraMessage(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? 'Joueur',
      message: json['message'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

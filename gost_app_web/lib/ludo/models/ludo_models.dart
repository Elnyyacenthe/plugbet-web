// ============================================================
// LUDO MODULE - Modèles de données
// UserProfile, Challenge, LudoGame, LudoGameState
// ============================================================

import 'dart:convert';
import 'dart:math';

/// Profil utilisateur avec portefeuille de coins
class UserProfile {
  final String id;
  final String username;
  final int coins;
  final int gamesPlayed;
  final int gamesWon;
  final DateTime? createdAt;

  const UserProfile({
    required this.id,
    required this.username,
    this.coins = 500,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.createdAt,
  });

  double get winRate =>
      gamesPlayed > 0 ? (gamesWon / gamesPlayed * 100) : 0.0;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String? ?? 'Joueur',
      coins: json['coins'] as int? ?? 500,
      gamesPlayed: json['games_played'] as int? ?? 0,
      gamesWon: json['games_won'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'coins': coins,
        'games_played': gamesPlayed,
        'games_won': gamesWon,
      };

  UserProfile copyWith({int? coins, String? username}) => UserProfile(
        id: id,
        username: username ?? this.username,
        coins: coins ?? this.coins,
        gamesPlayed: gamesPlayed,
        gamesWon: gamesWon,
        createdAt: createdAt,
      );
}

/// Joueur en ligne dans le lobby
class OnlinePlayer {
  final String userId;
  final String username;
  final int coins;
  final DateTime lastSeen;

  const OnlinePlayer({
    required this.userId,
    required this.username,
    required this.coins,
    required this.lastSeen,
  });

  bool get isOnline =>
      DateTime.now().difference(lastSeen).inMinutes < 5;

  factory OnlinePlayer.fromJson(Map<String, dynamic> json) {
    return OnlinePlayer(
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? 'Joueur',
      coins: json['coins'] as int? ?? 0,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : DateTime.now(),
    );
  }
}

/// Statut d'un défi
enum ChallengeStatus { pending, accepted, declined, expired }

ChallengeStatus challengeStatusFromString(String s) {
  switch (s) {
    case 'accepted':
      return ChallengeStatus.accepted;
    case 'declined':
      return ChallengeStatus.declined;
    case 'expired':
      return ChallengeStatus.expired;
    default:
      return ChallengeStatus.pending;
  }
}

/// Défi Ludo entre deux joueurs
class LudoChallenge {
  final String id;
  final String fromUser;
  final String toUser;
  final int betAmount;
  final ChallengeStatus status;
  final String? gameId;
  final DateTime createdAt;

  // Champs optionnels remplis côté client
  final String? fromUsername;
  final String? toUsername;

  const LudoChallenge({
    required this.id,
    required this.fromUser,
    required this.toUser,
    required this.betAmount,
    required this.status,
    this.gameId,
    required this.createdAt,
    this.fromUsername,
    this.toUsername,
  });

  factory LudoChallenge.fromJson(Map<String, dynamic> json) {
    return LudoChallenge(
      id: json['id'] as String,
      fromUser: json['from_user'] as String,
      toUser: json['to_user'] as String,
      betAmount: json['bet_amount'] as int? ?? 0,
      status: challengeStatusFromString(json['status'] as String? ?? 'pending'),
      gameId: json['game_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      fromUsername: json['from_username'] as String?,
      toUsername: json['to_username'] as String?,
    );
  }
}

/// Statut d'une partie
enum GameStatus { playing, finished, abandoned, cancelled }

GameStatus gameStatusFromString(String s) {
  switch (s) {
    case 'finished':
      return GameStatus.finished;
    case 'abandoned':
      return GameStatus.abandoned;
    case 'cancelled':
      return GameStatus.cancelled;
    default:
      return GameStatus.playing;
  }
}

/// Partie Ludo complète
class LudoGame {
  final String id;
  final String? challengeId;
  final String player1;
  final String player2;
  final String? player3;
  final String? player4;
  final int playerCount;
  final String currentTurn;
  final int betAmount;
  final LudoGameState gameState;
  final GameStatus status;
  final String? winnerId;
  final DateTime createdAt;

  const LudoGame({
    required this.id,
    this.challengeId,
    required this.player1,
    required this.player2,
    this.player3,
    this.player4,
    this.playerCount = 2,
    required this.currentTurn,
    required this.betAmount,
    required this.gameState,
    required this.status,
    this.winnerId,
    required this.createdAt,
  });

  bool isMyTurn(String userId) => currentTurn == userId;

  /// Retourne la liste de tous les joueurs
  List<String> get allPlayers {
    final players = [player1, player2];
    if (playerCount == 4 && player3 != null && player4 != null) {
      players.addAll([player3!, player4!]);
    }
    return players;
  }

  /// Retourne l'adversaire pour un mode 2 joueurs
  String opponentOf(String userId) {
    if (playerCount != 2) {
      throw Exception('opponentOf() est uniquement pour mode 2 joueurs');
    }
    return userId == player1 ? player2 : player1;
  }

  /// Retourne tous les adversaires d'un joueur
  List<String> opponentsOf(String userId) {
    return allPlayers.where((id) => id != userId).toList();
  }

  factory LudoGame.fromJson(Map<String, dynamic> json) {
    final stateData = json['game_state'];
    final Map<String, dynamic> stateMap;
    if (stateData is String) {
      stateMap = jsonDecode(stateData) as Map<String, dynamic>;
    } else {
      stateMap = stateData as Map<String, dynamic>;
    }

    return LudoGame(
      id: json['id'] as String,
      challengeId: json['challenge_id'] as String?,
      player1: json['player1'] as String,
      player2: json['player2'] as String,
      player3: json['player3'] as String?,
      player4: json['player4'] as String?,
      playerCount: json['player_count'] as int? ?? 2,
      currentTurn: json['current_turn'] as String,
      betAmount: json['bet_amount'] as int? ?? 0,
      gameState: LudoGameState.fromJson(stateMap),
      status: gameStatusFromString(json['status'] as String? ?? 'playing'),
      winnerId: json['winner_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// État interne du jeu Ludo
///
/// Chaque pion a une position (step) :
///   0 = dans la base (maison)
///   1 = case de départ sur le plateau
///   2-51 = progression sur le parcours principal
///   52-57 = couloir d'arrivée (home stretch)
///   58 = arrivé au centre (terminé)
class LudoGameState {
  /// Map userId → [step0, step1, step2, step3]
  final Map<String, List<int>> pawns;
  final int lastDice;
  final bool hasRolled;

  const LudoGameState({
    required this.pawns,
    this.lastDice = 0,
    this.hasRolled = false,
  });

  factory LudoGameState.initial(
    String player1Id,
    String player2Id, {
    String? player3Id,
    String? player4Id,
  }) {
    final pawns = {
      player1Id: [0, 0, 0, 0],
      player2Id: [0, 0, 0, 0],
    };

    if (player3Id != null) {
      pawns[player3Id] = [0, 0, 0, 0];
    }
    if (player4Id != null) {
      pawns[player4Id] = [0, 0, 0, 0];
    }

    return LudoGameState(pawns: pawns);
  }

  factory LudoGameState.fromJson(Map<String, dynamic> json) {
    final pawnsRaw = json['pawns'] as Map<String, dynamic>? ?? {};
    final pawns = <String, List<int>>{};
    for (final entry in pawnsRaw.entries) {
      final list = entry.value;
      if (list is List) {
        pawns[entry.key] = list.map((e) => (e as num).toInt()).toList();
      } else if (list is String) {
        final decoded = jsonDecode(list) as List;
        pawns[entry.key] = decoded.map((e) => (e as num).toInt()).toList();
      }
    }

    return LudoGameState(
      pawns: pawns,
      lastDice: (json['lastDice'] as num?)?.toInt() ?? 0,
      hasRolled: json['hasRolled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'pawns': pawns.map((k, v) => MapEntry(k, v)),
        'lastDice': lastDice,
        'hasRolled': hasRolled,
      };

  /// Positions des pions d'un joueur
  List<int> playerPawns(String playerId) =>
      pawns[playerId] ?? [0, 0, 0, 0];

  /// Vérifie si un joueur a gagné (tous les pions à 58)
  bool hasWon(String playerId) {
    final p = playerPawns(playerId);
    return p.every((step) => step >= 58);
  }

  /// Vérifie si un joueur peut bouger au moins un pion
  bool canMove(String playerId, int dice) {
    final p = playerPawns(playerId);
    for (int i = 0; i < 4; i++) {
      if (_isValidMove(p[i], dice)) return true;
    }
    return false;
  }

  /// Un déplacement est valide si :
  /// - Le pion est en base (step 0) et le dé = 6 → sort en step 1
  /// - Le pion est sur le plateau (1-57) et step + dice <= 58
  bool _isValidMove(int currentStep, int dice) {
    if (currentStep == 0) return dice == 6;
    if (currentStep >= 58) return false; // Déjà arrivé
    final newStep = currentStep + dice;
    return newStep <= 58;
  }

  /// Vérifie si un pion spécifique peut bouger
  bool canMovePawn(String playerId, int pawnIndex, int dice) {
    final step = playerPawns(playerId)[pawnIndex];
    return _isValidMove(step, dice);
  }

  /// Applique un mouvement et retourne le nouvel état
  /// Retourne aussi si un pion adverse a été capturé
  LudoMoveResult applyMove(
    String playerId,
    int pawnIndex,
    int dice,
    List<String> opponentIds,
  ) {
    final newPawns = <String, List<int>>{};
    for (final entry in pawns.entries) {
      newPawns[entry.key] = List<int>.from(entry.value);
    }

    final currentStep = newPawns[playerId]![pawnIndex];
    int newStep;

    if (currentStep == 0 && dice == 6) {
      newStep = 1; // Sort de la base
    } else {
      newStep = currentStep + dice;
    }

    newPawns[playerId]![pawnIndex] = newStep;

    // Vérifier capture (seulement sur le parcours principal, steps 1-51)
    bool captured = false;
    if (newStep >= 1 && newStep <= 51) {
      final myAbsPos = _absolutePosition(newStep, playerId);

      // Vérifier contre TOUS les adversaires
      for (final opponentId in opponentIds) {
        final opponentPawns = newPawns[opponentId]!;
        for (int i = 0; i < 4; i++) {
          if (opponentPawns[i] >= 1 && opponentPawns[i] <= 51) {
            final oppAbsPos =
                _absolutePosition(opponentPawns[i], opponentId);
            if (myAbsPos == oppAbsPos && !_isSafeCell(myAbsPos)) {
              opponentPawns[i] = 0; // Renvoyé à la base
              captured = true;
            }
          }
        }
      }
    }

    // Vérifier victoire
    final won = newPawns[playerId]!.every((s) => s >= 58);

    return LudoMoveResult(
      newState: LudoGameState(
        pawns: newPawns,
        lastDice: dice,
        hasRolled: true,
      ),
      captured: captured,
      won: won,
      rolledSix: dice == 6,
    );
  }

  /// Offsets par index joueur : Red=0, Green=13, Blue=26, Yellow=39
  static const _playerOffsets = [0, 13, 26, 39];

  /// Position absolue sur le circuit (0-51)
  int _absolutePosition(int relativeStep, String playerId) {
    if (relativeStep < 1 || relativeStep > 51) return -1;
    final keys = pawns.keys.toList();
    final idx = keys.indexOf(playerId).clamp(0, 3);
    final offset = _playerOffsets[idx];
    return ((relativeStep - 1) + offset) % 52;
  }

  /// Cases sûres : départs (0,13,26,39) + étoiles (8,21,34,47)
  static bool _isSafeCell(int absPosition) {
    const safeCells = {0, 8, 13, 21, 26, 34, 39, 47};
    return safeCells.contains(absPosition);
  }

  /// Lance un dé (1-6)
  static int rollDice() => Random().nextInt(6) + 1;
}

/// Résultat d'un mouvement
class LudoMoveResult {
  final LudoGameState newState;
  final bool captured;
  final bool won;
  final bool rolledSix;

  const LudoMoveResult({
    required this.newState,
    required this.captured,
    required this.won,
    required this.rolledSix,
  });
}

/// Salle de jeu Ludo
class LudoRoom {
  final String id;
  final String code;
  final String hostId;
  final String? player2Id;
  final String? player3Id;
  final String? player4Id;
  final int playerCount;
  final int betAmount;
  final bool isPrivate;
  final String status;
  final String? gameId;
  final DateTime createdAt;
  final String? hostUsername;

  const LudoRoom({
    required this.id,
    required this.code,
    required this.hostId,
    this.player2Id,
    this.player3Id,
    this.player4Id,
    this.playerCount = 2,
    required this.betAmount,
    this.isPrivate = false,
    this.status = 'waiting',
    this.gameId,
    required this.createdAt,
    this.hostUsername,
  });

  /// Alias pour compatibilité avec l'ancien code
  String? get guestId => player2Id;

  /// Nombre de joueurs actuellement dans la room
  int get currentPlayerCount {
    int count = 1; // host
    if (player2Id != null) count++;
    if (player3Id != null) count++;
    if (player4Id != null) count++;
    return count;
  }

  /// La room est-elle complète?
  bool get isFull => currentPlayerCount >= playerCount;

  factory LudoRoom.fromJson(Map<String, dynamic> json) {
    return LudoRoom(
      id: json['id'] as String,
      code: json['code'] as String,
      hostId: json['host_id'] as String,
      player2Id: json['player2_id'] as String? ?? json['guest_id'] as String?,
      player3Id: json['player3_id'] as String?,
      player4Id: json['player4_id'] as String?,
      playerCount: json['player_count'] as int? ?? 2,
      betAmount: json['bet_amount'] as int? ?? 50,
      isPrivate: json['is_private'] as bool? ?? false,
      status: json['status'] as String? ?? 'waiting',
      gameId: json['game_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      hostUsername: json['host_username'] as String?,
    );
  }
}

/// Message de chat en jeu
class ChatMessage {
  final String id;
  final String gameId;
  final String userId;
  final String message;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.message,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      gameId: json['game_id'] as String,
      userId: json['user_id'] as String,
      message: json['message'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

// ============================================================
// Constantes du plateau Ludo (15x15)
// ============================================================
class LudoBoard {
  /// Les 52 cases du parcours principal [row, col] sur une grille 15x15
  static const List<List<int>> trackCells = [
    // Bras bas, montée côté gauche (départ Rouge)
    [13, 6], // 0 - Départ Rouge
    [12, 6], // 1
    [11, 6], // 2
    [10, 6], // 3
    [9, 6], // 4

    // Bras gauche, traversée vers la gauche (bas)
    [8, 5], // 5
    [8, 4], // 6
    [8, 3], // 7
    [8, 2], // 8
    [8, 1], // 9
    [8, 0], // 10

    // Bras gauche, montée
    [7, 0], // 11

    // Bras gauche, traversée vers la droite (haut)
    [6, 0], // 12
    [6, 1], // 13
    [6, 2], // 14
    [6, 3], // 15
    [6, 4], // 16
    [6, 5], // 17

    // Bras haut, montée côté gauche
    [5, 6], // 18
    [4, 6], // 19
    [3, 6], // 20
    [2, 6], // 21
    [1, 6], // 22
    [0, 6], // 23

    // Bras haut, traversée vers la droite
    [0, 7], // 24

    // Bras haut, descente côté droit
    [0, 8], // 25
    [1, 8], // 26 - Départ Bleu
    [2, 8], // 27
    [3, 8], // 28
    [4, 8], // 29
    [5, 8], // 30

    // Bras droit, traversée vers la droite (haut)
    [6, 9], // 31
    [6, 10], // 32
    [6, 11], // 33
    [6, 12], // 34
    [6, 13], // 35
    [6, 14], // 36

    // Bras droit, descente
    [7, 14], // 37

    // Bras droit, traversée vers la gauche (bas)
    [8, 14], // 38
    [8, 13], // 39
    [8, 12], // 40
    [8, 11], // 41
    [8, 10], // 42
    [8, 9], // 43

    // Bras bas, descente côté droit
    [9, 8], // 44
    [10, 8], // 45
    [11, 8], // 46
    [12, 8], // 47
    [13, 8], // 48
    [14, 8], // 49

    // Bras bas, traversée vers la gauche
    [14, 7], // 50

    // Retour vers départ Rouge
    [14, 6], // 51
  ];

  /// Couloirs d'arrivée (home stretch) pour chaque offset de joueur
  /// Joueur offset 0 (Rouge) : entre depuis track[50] → monte vers le centre
  static const List<List<int>> homeStretchRed = [
    [13, 7], // step 52
    [12, 7], // step 53
    [11, 7], // step 54
    [10, 7], // step 55
    [9, 7], // step 56
    [8, 7], // step 57
  ];

  /// Joueur offset 26 (Bleu) : entre depuis track[24] → descend vers le centre
  static const List<List<int>> homeStretchBlue = [
    [1, 7], // step 52
    [2, 7], // step 53
    [3, 7], // step 54
    [4, 7], // step 55
    [5, 7], // step 56
    [6, 7], // step 57
  ];

  /// Cases de base (maison) pour chaque joueur
  static const List<List<int>> homeBaseRed = [
    [10, 1],
    [10, 4],
    [13, 1],
    [13, 4],
  ];

  static const List<List<int>> homeBaseBlue = [
    [1, 10],
    [1, 13],
    [4, 10],
    [4, 13],
  ];

  /// Bases decoratives (non jouables, pour le rendu visuel 4 couleurs)
  static const List<List<int>> homeBaseGreen = [
    [1, 1],
    [1, 4],
    [4, 1],
    [4, 4],
  ];

  static const List<List<int>> homeBaseYellow = [
    [10, 10],
    [10, 13],
    [13, 10],
    [13, 13],
  ];

  /// Couloirs d'arrivee decoratifs (bras horizontaux)
  /// Vert (gauche) : entre par la gauche, avance vers le centre sur row 7
  static const List<List<int>> homeStretchGreen = [
    [7, 1],
    [7, 2],
    [7, 3],
    [7, 4],
    [7, 5],
    [7, 6],
  ];

  /// Jaune (droite) : entre par la droite, avance vers le centre sur row 7
  static const List<List<int>> homeStretchYellow = [
    [7, 13],
    [7, 12],
    [7, 11],
    [7, 10],
    [7, 9],
    [7, 8],
  ];

  /// Centre du plateau
  static const List<int> center = [7, 7];

  /// Offset du parcours pour chaque joueur (index dans trackCells)
  static const int redOffset = 0;
  static const int greenOffset = 13;
  static const int blueOffset = 26;
  static const int yellowOffset = 39;

  /// Données par couleur indexées par playerIndex (0=red,1=green,2=blue,3=yellow)
  static const List<List<List<int>>> _homeBases = [
    homeBaseRed, homeBaseGreen, homeBaseBlue, homeBaseYellow,
  ];
  static const List<List<List<int>>> _homeStretches = [
    homeStretchRed, homeStretchGreen, homeStretchBlue, homeStretchYellow,
  ];
  static const List<int> _offsets = [redOffset, greenOffset, blueOffset, yellowOffset];

  /// Obtenir la position visuelle (row, col) d'un pion
  /// [playerIndex] : 0=red, 1=green, 2=blue, 3=yellow
  static List<int> getPawnPositionByPlayer(
    int step,
    int playerIndex, {
    int pawnIndex = 0,
  }) {
    final pi = playerIndex.clamp(0, 3);
    if (step == 0) {
      return _homeBases[pi][pawnIndex];
    }
    if (step >= 58) {
      return center;
    }
    if (step >= 52) {
      final stretchIndex = step - 52;
      return _homeStretches[pi][stretchIndex];
    }
    final absIndex = ((step - 1) + _offsets[pi]) % 52;
    return trackCells[absIndex];
  }

  /// Ancien API rétro-compatible (isPlayer1 = red, sinon blue)
  static List<int> getPawnPosition(
    int step,
    bool isPlayer1, {
    int pawnIndex = 0,
  }) {
    return getPawnPositionByPlayer(step, isPlayer1 ? 0 : 2, pawnIndex: pawnIndex);
  }
}

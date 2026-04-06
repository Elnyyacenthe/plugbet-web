// ============================================================
// Solitaire – Modèles de salle multijoueur
// ============================================================

class SolitaireRoomPlayer {
  final String id;
  final String username;
  final int score; // nombre de cartes envoyées en fondation

  const SolitaireRoomPlayer({
    required this.id,
    required this.username,
    this.score = 0,
  });

  SolitaireRoomPlayer copyWith({int? score}) =>
      SolitaireRoomPlayer(id: id, username: username, score: score ?? this.score);

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'score': score};

  factory SolitaireRoomPlayer.fromJson(Map<String, dynamic> json) =>
      SolitaireRoomPlayer(
        id: json['id'] as String,
        username: json['username'] as String? ?? 'Joueur',
        score: json['score'] as int? ?? 0,
      );
}

enum SolitaireRoomStatus { waiting, playing, finished }

class SolitaireRoom {
  final String id;
  final String hostId;
  final String hostUsername;
  final int maxPlayers;
  final int currentPlayers;
  final int betAmount;
  final int pot;
  final bool isPrivate;
  final String? privateCode;
  final SolitaireRoomStatus status;
  final List<SolitaireRoomPlayer> players;
  final int currentTurnIndex;
  final Map<String, dynamic>? gameStateJson;
  final String? winnerId;

  const SolitaireRoom({
    required this.id,
    required this.hostId,
    required this.hostUsername,
    required this.maxPlayers,
    required this.currentPlayers,
    required this.betAmount,
    required this.pot,
    required this.isPrivate,
    this.privateCode,
    required this.status,
    required this.players,
    this.currentTurnIndex = 0,
    this.gameStateJson,
    this.winnerId,
  });

  factory SolitaireRoom.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'waiting';
    final status = SolitaireRoomStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => SolitaireRoomStatus.waiting,
    );

    final gameState = json['game_state'] as Map<String, dynamic>?;
    final playersJson = (gameState?['players'] as List?) ?? [];
    final currentTurnIndex = gameState?['currentTurnIndex'] as int? ?? 0;

    return SolitaireRoom(
      id: json['id'] as String,
      hostId: json['host_id'] as String,
      hostUsername: json['host_username'] as String? ?? 'Hôte',
      maxPlayers: json['max_players'] as int? ?? 2,
      currentPlayers: json['current_players'] as int? ?? 1,
      betAmount: json['bet_amount'] as int? ?? 100,
      pot: json['pot'] as int? ?? 0,
      isPrivate: json['is_private'] as bool? ?? false,
      privateCode: json['private_code'] as String?,
      status: status,
      players: playersJson
          .map((p) => SolitaireRoomPlayer.fromJson(p as Map<String, dynamic>))
          .toList(),
      currentTurnIndex: currentTurnIndex,
      gameStateJson: gameState,
      winnerId: json['winner_id'] as String?,
    );
  }

  /// Retourne l'index du joueur avec l'id donné, -1 si absent
  int playerIndex(String uid) => players.indexWhere((p) => p.id == uid);

  /// True si c'est le tour de ce joueur
  bool isMyTurn(String uid) {
    final idx = playerIndex(uid);
    return idx >= 0 && idx == currentTurnIndex;
  }
}

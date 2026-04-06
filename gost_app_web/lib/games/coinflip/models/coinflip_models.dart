// ============================================================
// PILE OU FACE — Modèles
// ============================================================

class CFPlayer {
  final String odile;
  final String username;
  final String? choice; // pile ou face
  final bool hasChosen;

  const CFPlayer({required this.odile, required this.username, this.choice, this.hasChosen = false});

  factory CFPlayer.fromJson(String uid, Map<String, dynamic> j) => CFPlayer(
    odile: uid,
    username: j['username'] as String? ?? 'Joueur',
    choice: j['choice'] as String?,
    hasChosen: j['has_chosen'] as bool? ?? false,
  );
}

class CFGameState {
  final Map<String, CFPlayer> players;
  final String? result; // pile ou face
  final String? winnerId;
  final String phase; // choosing, flipping, finished
  final bool isFinished;

  const CFGameState({this.players = const {}, this.result, this.winnerId,
    this.phase = 'choosing', this.isFinished = false});

  factory CFGameState.fromJson(Map<String, dynamic> j) {
    final playersRaw = j['players'] as Map<String, dynamic>? ?? {};
    final players = <String, CFPlayer>{};
    for (final e in playersRaw.entries) {
      players[e.key] = CFPlayer.fromJson(e.key, e.value as Map<String, dynamic>);
    }
    return CFGameState(
      players: players,
      result: j['result'] as String?,
      winnerId: j['winner_id'] as String?,
      phase: j['phase'] as String? ?? 'choosing',
      isFinished: j['is_finished'] as bool? ?? false,
    );
  }
}

class CFGame {
  final String id;
  final String roomId;
  final int betAmount;
  final CFGameState gameState;
  final String status;

  const CFGame({required this.id, required this.roomId,
    this.betAmount = 100, required this.gameState, this.status = 'playing'});

  factory CFGame.fromJson(Map<String, dynamic> j) {
    final stateData = j['game_state'];
    final stateMap = stateData is Map<String, dynamic> ? stateData : <String, dynamic>{};
    return CFGame(
      id: j['id'] as String,
      roomId: j['room_id'] as String,
      betAmount: j['bet_amount'] as int? ?? 100,
      gameState: CFGameState.fromJson(stateMap),
      status: j['status'] as String? ?? 'playing',
    );
  }

  int get pot => betAmount * gameState.players.length;
}

class CFRoom {
  final String id;
  final String code;
  final String hostId;
  final int betAmount;
  final String status;
  final String? gameId;

  const CFRoom({required this.id, required this.code, required this.hostId,
    this.betAmount = 100, this.status = 'waiting', this.gameId});

  factory CFRoom.fromJson(Map<String, dynamic> j) => CFRoom(
    id: j['id'] as String,
    code: j['code'] as String,
    hostId: j['host_id'] as String,
    betAmount: j['bet_amount'] as int? ?? 100,
    status: j['status'] as String? ?? 'waiting',
    gameId: j['game_id'] as String?,
  );
}

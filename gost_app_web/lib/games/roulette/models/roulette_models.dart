// ============================================================
// ROULETTE — Modèles
// ============================================================

class RouletteBet {
  final String odile;
  final String type; // number, red, black, even, odd, low, high
  final int? number; // si type=number
  final int amount;

  const RouletteBet({required this.odile, required this.type, this.number, required this.amount});

  factory RouletteBet.fromJson(Map<String, dynamic> j) => RouletteBet(
    odile: j['user_id'] as String? ?? '',
    type: j['type'] as String? ?? 'red',
    number: j['number'] as int?,
    amount: j['amount'] as int? ?? 0,
  );

  int get payout {
    switch (type) {
      case 'number': return amount * 35;
      case 'red': case 'black': case 'even': case 'odd':
      case 'low': case 'high': return amount * 2;
      default: return 0;
    }
  }

  bool wins(int result) {
    if (result == 0) return false; // 0 = maison gagne
    switch (type) {
      case 'number': return number == result;
      case 'red': return _redNumbers.contains(result);
      case 'black': return !_redNumbers.contains(result);
      case 'even': return result % 2 == 0;
      case 'odd': return result % 2 == 1;
      case 'low': return result >= 1 && result <= 18;
      case 'high': return result >= 19 && result <= 36;
      default: return false;
    }
  }

  static const _redNumbers = {1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36};
}

class RoulettePlayer {
  final String odile;
  final String username;
  final List<RouletteBet> bets;
  final int totalBet;
  final int? winnings;

  const RoulettePlayer({required this.odile, required this.username,
    this.bets = const [], this.totalBet = 0, this.winnings});

  factory RoulettePlayer.fromJson(String uid, Map<String, dynamic> j) => RoulettePlayer(
    odile: uid,
    username: j['username'] as String? ?? 'Joueur',
    bets: (j['bets'] as List?)?.map((b) => RouletteBet.fromJson(b as Map<String, dynamic>)).toList() ?? [],
    totalBet: j['total_bet'] as int? ?? 0,
    winnings: j['winnings'] as int?,
  );
}

class RouletteGameState {
  final Map<String, RoulettePlayer> players;
  final String phase; // betting, spinning, finished
  final int? result; // 0-36
  final int bettingCountdown;
  final bool isFinished;

  const RouletteGameState({this.players = const {}, this.phase = 'betting',
    this.result, this.bettingCountdown = 30, this.isFinished = false});

  factory RouletteGameState.fromJson(Map<String, dynamic> j) {
    final playersRaw = j['players'] as Map<String, dynamic>? ?? {};
    final players = <String, RoulettePlayer>{};
    for (final e in playersRaw.entries) {
      players[e.key] = RoulettePlayer.fromJson(e.key, e.value as Map<String, dynamic>);
    }
    return RouletteGameState(
      players: players,
      phase: j['phase'] as String? ?? 'betting',
      result: j['result'] as int?,
      bettingCountdown: j['betting_countdown'] as int? ?? 30,
      isFinished: j['is_finished'] as bool? ?? false,
    );
  }
}

class RouletteGame {
  final String id;
  final String roomId;
  final int minBet;
  final RouletteGameState gameState;
  final String status;

  const RouletteGame({required this.id, required this.roomId,
    this.minBet = 50, required this.gameState, this.status = 'playing'});

  factory RouletteGame.fromJson(Map<String, dynamic> j) {
    final stateData = j['game_state'];
    final stateMap = stateData is Map<String, dynamic> ? stateData : <String, dynamic>{};
    return RouletteGame(
      id: j['id'] as String,
      roomId: j['room_id'] as String,
      minBet: j['min_bet'] as int? ?? 50,
      gameState: RouletteGameState.fromJson(stateMap),
      status: j['status'] as String? ?? 'playing',
    );
  }
}

class RouletteRoom {
  final String id;
  final String code;
  final String hostId;
  final int maxPlayers;
  final int minBet;
  final String status;
  final String? gameId;

  const RouletteRoom({required this.id, required this.code, required this.hostId,
    this.maxPlayers = 6, this.minBet = 50, this.status = 'waiting', this.gameId});

  factory RouletteRoom.fromJson(Map<String, dynamic> j) => RouletteRoom(
    id: j['id'] as String,
    code: j['code'] as String,
    hostId: j['host_id'] as String,
    maxPlayers: j['max_players'] as int? ?? 6,
    minBet: j['min_bet'] as int? ?? 50,
    status: j['status'] as String? ?? 'waiting',
    gameId: j['game_id'] as String?,
  );
}

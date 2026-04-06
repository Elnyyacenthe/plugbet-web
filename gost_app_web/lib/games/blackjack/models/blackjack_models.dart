// ============================================================
// BLACKJACK — Modèles de données
// ============================================================

class BJCard {
  final String suit; // hearts, diamonds, clubs, spades
  final String rank; // A, 2-10, J, Q, K

  const BJCard({required this.suit, required this.rank});

  factory BJCard.fromJson(Map<String, dynamic> j) =>
      BJCard(suit: j['suit'] as String, rank: j['rank'] as String);

  Map<String, dynamic> toJson() => {'suit': suit, 'rank': rank};

  int get value {
    if (rank == 'A') return 11;
    if (['K', 'Q', 'J'].contains(rank)) return 10;
    return int.parse(rank);
  }

  String get display {
    const suits = {'hearts': '♥', 'diamonds': '♦', 'clubs': '♣', 'spades': '♠'};
    return '$rank${suits[suit] ?? ''}';
  }

  bool get isRed => suit == 'hearts' || suit == 'diamonds';
}

class BJHand {
  final List<BJCard> cards;
  final String status; // playing, stand, bust, blackjack, won, lost, push

  const BJHand({this.cards = const [], this.status = 'playing'});

  factory BJHand.fromJson(Map<String, dynamic> j) => BJHand(
        cards: (j['cards'] as List?)
                ?.map((c) => BJCard.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        status: j['status'] as String? ?? 'playing',
      );

  int get score {
    int total = 0;
    int aces = 0;
    for (final c in cards) {
      total += c.value;
      if (c.rank == 'A') aces++;
    }
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
    return total;
  }

  bool get isBust => score > 21;
  bool get isBlackjack => cards.length == 2 && score == 21;
  bool get canHit => status == 'playing' && !isBust;
}

class BJPlayer {
  final String odile;
  final String username;
  final int bet;
  final BJHand hand;

  const BJPlayer({
    required this.odile,
    required this.username,
    this.bet = 0,
    this.hand = const BJHand(),
  });

  factory BJPlayer.fromJson(String odile, Map<String, dynamic> j) => BJPlayer(
        odile: odile,
        username: j['username'] as String? ?? 'Joueur',
        bet: j['bet'] as int? ?? 0,
        hand: j['hand'] != null
            ? BJHand.fromJson(j['hand'] as Map<String, dynamic>)
            : const BJHand(),
      );
}

class BJGameState {
  final Map<String, BJPlayer> players;
  final BJHand dealerHand;
  final String phase; // betting, playing, dealer_turn, finished
  final String? currentTurn;
  final List<String> turnOrder;
  final Map<String, String> results; // uid -> won/lost/push
  final bool isFinished;

  const BJGameState({
    this.players = const {},
    this.dealerHand = const BJHand(),
    this.phase = 'betting',
    this.currentTurn,
    this.turnOrder = const [],
    this.results = const {},
    this.isFinished = false,
  });

  factory BJGameState.fromJson(Map<String, dynamic> j) {
    final playersRaw = j['players'] as Map<String, dynamic>? ?? {};
    final players = <String, BJPlayer>{};
    for (final e in playersRaw.entries) {
      players[e.key] = BJPlayer.fromJson(e.key, e.value as Map<String, dynamic>);
    }
    final resultsRaw = j['results'] as Map<String, dynamic>? ?? {};
    final results = resultsRaw.map((k, v) => MapEntry(k, v.toString()));

    return BJGameState(
      players: players,
      dealerHand: j['dealer'] != null
          ? BJHand.fromJson(j['dealer'] as Map<String, dynamic>)
          : const BJHand(),
      phase: j['phase'] as String? ?? 'betting',
      currentTurn: j['current_turn'] as String?,
      turnOrder: (j['turn_order'] as List?)?.cast<String>() ?? [],
      results: results,
      isFinished: j['is_finished'] as bool? ?? false,
    );
  }
}

class BJGame {
  final String id;
  final String roomId;
  final int betAmount;
  final int playerCount;
  final BJGameState gameState;
  final String status;

  const BJGame({
    required this.id,
    required this.roomId,
    required this.betAmount,
    required this.playerCount,
    required this.gameState,
    required this.status,
  });

  factory BJGame.fromJson(Map<String, dynamic> j) {
    final stateData = j['game_state'];
    final Map<String, dynamic> stateMap =
        stateData is Map<String, dynamic> ? stateData : {};

    return BJGame(
      id: j['id'] as String,
      roomId: j['room_id'] as String,
      betAmount: j['bet_amount'] as int? ?? 0,
      playerCount: j['player_count'] as int? ?? 2,
      gameState: BJGameState.fromJson(stateMap),
      status: j['status'] as String? ?? 'playing',
    );
  }
}

class BJRoom {
  final String id;
  final String code;
  final String hostId;
  final int playerCount;
  final int betAmount;
  final String status;
  final String? gameId;
  final String? hostUsername;

  const BJRoom({
    required this.id,
    required this.code,
    required this.hostId,
    this.playerCount = 2,
    this.betAmount = 100,
    this.status = 'waiting',
    this.gameId,
    this.hostUsername,
  });

  factory BJRoom.fromJson(Map<String, dynamic> j) => BJRoom(
        id: j['id'] as String,
        code: j['code'] as String,
        hostId: j['host_id'] as String,
        playerCount: j['player_count'] as int? ?? 2,
        betAmount: j['bet_amount'] as int? ?? 100,
        status: j['status'] as String? ?? 'waiting',
        gameId: j['game_id'] as String?,
        hostUsername: j['host_username'] as String?,
      );
}

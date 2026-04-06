// ============================================================
// LUDO V2 — Models
// ============================================================

import 'dart:convert';

/// État d'une room
class LudoV2Room {
  final String id;
  final String code;
  final String hostId;
  final int playerCount;
  final int betAmount;
  final bool isPrivate;
  final String status;
  final String? gameId;
  final DateTime createdAt;
  final List<LudoV2RoomPlayer> players;

  const LudoV2Room({
    required this.id,
    required this.code,
    required this.hostId,
    required this.playerCount,
    required this.betAmount,
    required this.isPrivate,
    required this.status,
    this.gameId,
    required this.createdAt,
    this.players = const [],
  });

  bool get isFull => players.length >= playerCount;
  bool get isWaiting => status == 'waiting';

  factory LudoV2Room.fromJson(Map<String, dynamic> j) => LudoV2Room(
    id: j['id'] as String,
    code: j['code'] as String? ?? '',
    hostId: j['host_id'] as String,
    playerCount: j['player_count'] as int? ?? 2,
    betAmount: j['bet_amount'] as int? ?? 0,
    isPrivate: j['is_private'] as bool? ?? false,
    status: j['status'] as String? ?? 'waiting',
    gameId: j['game_id'] as String?,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    players: (j['ludo_v2_room_players'] as List?)
        ?.map((p) => LudoV2RoomPlayer.fromJson(p as Map<String, dynamic>))
        .toList() ?? [],
  );
}

class LudoV2RoomPlayer {
  final String userId;
  final int slot;
  final String username;

  const LudoV2RoomPlayer({
    required this.userId,
    required this.slot,
    required this.username,
  });

  factory LudoV2RoomPlayer.fromJson(Map<String, dynamic> j) => LudoV2RoomPlayer(
    userId: j['user_id'] as String,
    slot: j['slot'] as int? ?? 0,
    username: j['username'] as String? ?? 'Joueur',
  );
}

/// État complet d'une partie
class LudoV2Game {
  final String id;
  final String? roomId;
  final Map<String, List<int>> pawns;    // {uid: [s0,s1,s2,s3]}
  final String currentTurn;               // uid
  final List<String> turnOrder;           // [uid1, uid2, ...]
  final Map<String, int> colorMap;        // {uid: colorIndex}
  final int? diceValue;
  final bool diceRolled;
  final String? lastMoveBy;
  final String status;
  final String? winnerId;
  final int turnNumber;
  final int betAmount;

  const LudoV2Game({
    required this.id,
    this.roomId,
    required this.pawns,
    required this.currentTurn,
    required this.turnOrder,
    required this.colorMap,
    this.diceValue,
    this.diceRolled = false,
    this.lastMoveBy,
    this.status = 'playing',
    this.winnerId,
    this.turnNumber = 0,
    this.betAmount = 0,
  });

  bool get isPlaying => status == 'playing';
  bool get isFinished => status == 'finished';

  bool isMyTurn(String uid) => currentTurn == uid;
  int myColor(String uid) => colorMap[uid] ?? 0;
  List<int> myPawns(String uid) => pawns[uid] ?? [0, 0, 0, 0];

  /// Parse depuis Supabase
  factory LudoV2Game.fromJson(Map<String, dynamic> j) {
    // Parse pawns
    final rawPawns = j['pawns'];
    final Map<String, List<int>> pawns = {};
    if (rawPawns is Map) {
      for (final e in rawPawns.entries) {
        final key = e.key.toString();
        if (e.value is List) {
          pawns[key] = (e.value as List).map((v) => (v as num).toInt()).toList();
        } else if (e.value is String) {
          pawns[key] = (jsonDecode(e.value as String) as List).map((v) => (v as num).toInt()).toList();
        }
      }
    }

    // Parse color_map
    final rawColors = j['color_map'];
    final Map<String, int> colorMap = {};
    if (rawColors is Map) {
      for (final e in rawColors.entries) {
        colorMap[e.key.toString()] = (e.value as num).toInt();
      }
    }

    // Parse turn_order
    final rawOrder = j['turn_order'];
    final List<String> turnOrder;
    if (rawOrder is List) {
      turnOrder = rawOrder.map((v) => v.toString()).toList();
    } else {
      turnOrder = [];
    }

    return LudoV2Game(
      id: j['id'] as String,
      roomId: j['room_id'] as String?,
      pawns: pawns,
      currentTurn: j['current_turn'] as String? ?? '',
      turnOrder: turnOrder,
      colorMap: colorMap,
      diceValue: j['dice_value'] as int?,
      diceRolled: j['dice_rolled'] as bool? ?? false,
      lastMoveBy: j['last_move_by'] as String?,
      status: j['status'] as String? ?? 'playing',
      winnerId: j['winner_id'] as String?,
      turnNumber: j['turn_number'] as int? ?? 0,
      betAmount: j['bet_amount'] as int? ?? 0,
    );
  }
}

/// Résultat d'un mouvement (retour RPC)
class LudoV2MoveResult {
  final bool captured;
  final bool won;
  final bool extraTurn;

  const LudoV2MoveResult({
    this.captured = false,
    this.won = false,
    this.extraTurn = false,
  });

  factory LudoV2MoveResult.fromJson(Map<String, dynamic> j) => LudoV2MoveResult(
    captured: j['captured'] as bool? ?? false,
    won: j['won'] as bool? ?? false,
    extraTurn: j['extra_turn'] as bool? ?? false,
  );
}

// ============================================================
// AVIATOR – Modèles de données
// ============================================================

// ─── Phase du jeu ─────────────────────────────────────────
enum AviatorPhase { waiting, flying, crashed }

// ─── Mise joueur ──────────────────────────────────────────
class AviatorBet {
  final int slot; // 1 ou 2 (deux paris simultanés)
  int amount;
  bool placed;
  bool cashedOut;
  double? cashMultiplier; // multiplicateur au moment du cash out
  double? autoCashOut;    // null = manuel seulement
  int? profit;            // positif = gain, négatif = perte

  AviatorBet({required this.slot})
      : amount = 90,
        placed = false,
        cashedOut = false;

  void reset() {
    placed = false;
    cashedOut = false;
    cashMultiplier = null;
    profit = null;
  }

  // Gain total reçu (mise incluse)
  int get payout {
    if (!cashedOut || cashMultiplier == null) return 0;
    return (amount * cashMultiplier!).floor();
  }
}

// ─── Round crashé (historique + provably fair) ─────────────
class CrashRound {
  final String roundId;
  final double crashPoint;
  final String serverSeed;
  final String clientSeed;
  final DateTime time;

  const CrashRound({
    required this.roundId,
    required this.crashPoint,
    required this.serverSeed,
    required this.clientSeed,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'round_id': roundId,
        'crash_point': crashPoint,
        'server_seed': serverSeed,
        'client_seed': clientSeed,
        'created_at': time.toIso8601String(),
      };

  factory CrashRound.fromJson(Map<String, dynamic> j) => CrashRound(
        roundId: j['round_id'] as String? ?? '',
        crashPoint: (j['crash_point'] as num?)?.toDouble() ?? 1.00,
        serverSeed: j['server_seed'] as String? ?? '',
        clientSeed: j['client_seed'] as String? ?? '',
        time: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  // Couleur badge selon crash point
  bool get isEarly => crashPoint < 1.5;
  bool get isMid => crashPoint >= 1.5 && crashPoint < 5.0;
  bool get isHigh => crashPoint >= 5.0;
}

// ─── Message de chat ──────────────────────────────────────
class AviatorChatMessage {
  final String username;
  final String text;
  final DateTime time;
  final bool isSystem; // messages automatiques (cash out broadcast)

  const AviatorChatMessage({
    required this.username,
    required this.text,
    required this.time,
    this.isSystem = false,
  });

  factory AviatorChatMessage.fromJson(Map<String, dynamic> j) =>
      AviatorChatMessage(
        username: j['username'] as String? ?? 'Joueur',
        text: j['text'] as String? ?? '',
        time: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String) ?? DateTime.now()
            : DateTime.now(),
        isSystem: j['is_system'] as bool? ?? false,
      );
}

// ─── LiveBet : mise d'un joueur partagee via Supabase ──────
class LiveBet {
  final String id;
  final int roundNum;
  final String userId;
  final String username;
  final int slot;
  final int amount;
  final double? cashedOutAt;
  final int? winAmount;
  final DateTime placedAt;

  const LiveBet({
    required this.id,
    required this.roundNum,
    required this.userId,
    required this.username,
    required this.slot,
    required this.amount,
    this.cashedOutAt,
    this.winAmount,
    required this.placedAt,
  });

  factory LiveBet.fromJson(Map<String, dynamic> j) => LiveBet(
        id: j['id'] as String,
        roundNum: (j['round_num'] as num).toInt(),
        userId: j['user_id'] as String? ?? '',
        username: j['username'] as String? ?? 'Joueur',
        slot: (j['slot'] as num).toInt(),
        amount: (j['amount'] as num).toInt(),
        cashedOutAt: j['cashed_out_at'] != null
            ? (j['cashed_out_at'] as num).toDouble()
            : null,
        winAmount:
            j['win_amount'] != null ? (j['win_amount'] as num).toInt() : null,
        placedAt: DateTime.tryParse(j['placed_at'] as String? ?? '') ??
            DateTime.now(),
      );

  LiveBet copyWith({double? cashedOutAt, int? winAmount}) => LiveBet(
        id: id,
        roundNum: roundNum,
        userId: userId,
        username: username,
        slot: slot,
        amount: amount,
        cashedOutAt: cashedOutAt ?? this.cashedOutAt,
        winAmount: winAmount ?? this.winAmount,
        placedAt: placedAt,
      );
}

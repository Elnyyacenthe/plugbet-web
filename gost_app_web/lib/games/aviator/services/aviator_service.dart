// ============================================================
// AVIATOR – Service : RNG provably fair + Supabase + Wallet
// ============================================================

import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/aviator_models.dart';
import '../../../services/wallet_service.dart';

class AviatorService {
  static final AviatorService instance = AviatorService._();
  AviatorService._();

  final _db = Supabase.instance.client;
  final _wallet = WalletService();
  final _rand = Random();

  // ─── Provably Fair RNG ──────────────────────────────────
  // Algorithme :
  // 1. serverSeed genere aleatoirement (16 octets hex)
  // 2. clientSeed genere aleatoirement (8 octets hex)
  // 3. hash = XOR-fold de combined (affiche apres crash pour verif)
  // 4. crashPoint = distribution Pareto avec house edge 7%
  //    (7% instant crash + 93% avec P(crash > M) = 1/M) -> RTP 93% constant

  String generateServerSeed() {
    final bytes = List.generate(16, (_) => _rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String generateClientSeed() {
    final bytes = List.generate(8, (_) => _rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String computeHash(String serverSeed, String clientSeed) {
    final combined = '$serverSeed:$clientSeed';
    var h = 5381;
    for (final c in combined.codeUnits) {
      h = ((h << 5) + h) ^ c;
      h &= 0x7FFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// Genere le point de crash a partir des seeds.
  /// Distribution discrete elargie (21 buckets) avec RTP 90% constant.
  /// House edge = 10% quelle que soit la strategie de cashout.
  /// Max crash = 30x (atteignable en ~8.9s dans la fenetre de 10s de vol).
  /// ATTENTION : identique cote SQL (_aviator_crash_point) pour l'anti-triche.
  double generateCrashPoint(String serverSeed, String clientSeed) {
    final combined = '$serverSeed:$clientSeed';
    var h = 5381;
    for (final c in combined.codeUnits) {
      h = ((h << 5) + h) ^ c;
      h &= 0x7FFFFFFF;
    }
    // Avalanche XorShift (2 passes) pour decorreler seeds consecutifs.
    // MUST match SQL _aviator_crash_point.
    h ^= (h << 13) & 0x7FFFFFFF;
    h ^= h >> 17;
    h ^= (h << 5) & 0x7FFFFFFF;
    h &= 0x7FFFFFFF;
    h ^= (h << 13) & 0x7FFFFFFF;
    h ^= h >> 17;
    h ^= (h << 5) & 0x7FFFFFFF;
    h &= 0x7FFFFFFF;

    final hVal = h.abs();

    const e = 0x7FFFFFFF;
    final ratio = hVal / e; // [0, 1)

    // Seuils cumulatifs (somme des probas jusqu'a ce bucket)
    if (ratio < 0.0500) return 0.00;   //  5.00%
    if (ratio < 0.0600) return 0.25;   //  1.00%
    if (ratio < 0.0750) return 0.50;   //  1.50%
    if (ratio < 0.0900) return 0.75;   //  1.50%
    if (ratio < 0.1000) return 0.90;   //  1.00%
    if (ratio < 0.1818) return 1.00;   //  8.18%
    if (ratio < 0.2500) return 1.10;   //  6.82%
    if (ratio < 0.3333) return 1.20;   //  8.33%
    if (ratio < 0.4000) return 1.35;   //  6.67%
    if (ratio < 0.4857) return 1.50;   //  8.57%
    if (ratio < 0.5500) return 1.75;   //  6.43%
    if (ratio < 0.6400) return 2.00;   //  9.00%
    if (ratio < 0.7000) return 2.50;   //  6.00%
    if (ratio < 0.7750) return 3.00;   //  7.50%
    if (ratio < 0.8200) return 4.00;   //  4.50%
    if (ratio < 0.8714) return 5.00;   //  5.14%
    if (ratio < 0.9100) return 7.00;   //  3.86%
    if (ratio < 0.9400) return 10.00;  //  3.00%
    if (ratio < 0.9550) return 15.00;  //  1.50%
    if (ratio < 0.9700) return 20.00;  //  1.50%
    return 30.00;                       //  3.00%
  }

  /// Multiplicateur à l'instant t (ms écoulés depuis décollage)
  /// Démarre à x0.00 — x1.00 atteint en ~1.8 secondes
  /// k = ln(2) / 1800 ≈ 0.000385 → e^(kt) - 1
  double computeMultiplier(int elapsedMs) {
    if (elapsedMs <= 0) return 0.00;
    // t=0.0s → x0.00 (décollage)
    // t=1.8s → x1.00 (break-even, prise en 1.8s)
    // t=3.0s → x2.17
    // t=5.0s → x5.86
    // t=8.0s → x20.8  (rare)
    // t=10s  → x46    (très rare)
    // t=12s  → x100   (extrêmement rare)
    const k = 0.000385;
    final value = exp(k * elapsedMs) - 1.0;
    return double.parse(value.toStringAsFixed(2)).clamp(0.00, 9999.99);
  }

  // ─── Wallet ─────────────────────────────────────────────
  Future<bool> deductBet(int amount) => _wallet.deductCoins(amount);
  Future<void> addWinnings(int amount) => _wallet.addCoins(amount);
  Future<int> getBalance() => _wallet.getCoins();
  Future<String> getUsername() => _wallet.getUsername();

  // ─── Synchronisation horloge serveur ────────────────────
  /// Mesure l'offset (ms) entre horloge locale et horloge serveur.
  /// Corrige la derive entre devices pour que tous voient le meme roundNum.
  /// Tolere une latence reseau raisonnable (divise par 2 = estimation one-way).
  Future<int> measureServerClockOffset() async {
    try {
      final localBefore = DateTime.now().millisecondsSinceEpoch;
      final res = await _db.rpc('server_epoch_ms');
      final localAfter = DateTime.now().millisecondsSinceEpoch;
      if (res is! num) return 0;
      final serverMs = res.toInt();
      final localMidpoint = (localBefore + localAfter) ~/ 2;
      return serverMs - localMidpoint;
    } catch (_) {
      return 0;
    }
  }

  // ─── Supabase : Historique crashes ──────────────────────
  Future<List<CrashRound>> getRecentRounds({int limit = 20}) async {
    try {
      final data = await _db
          .from('aviator_rounds')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List).map((j) => CrashRound.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRound(CrashRound round) async {
    try {
      await _db.from('aviator_rounds').insert(round.toJson());
    } catch (_) {}
  }

  // ─── Supabase : Chat ────────────────────────────────────
  Future<List<AviatorChatMessage>> getRecentChat({int limit = 50}) async {
    try {
      final data = await _db
          .from('aviator_chat')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List)
          .map((j) => AviatorChatMessage.fromJson(j))
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> sendCashOutMessage({
    required String username,
    required double multiplier,
    required int profit,
  }) async {
    try {
      await _db.from('aviator_chat').insert({
        'username': username,
        'text':
            'a cashouté à x${multiplier.toStringAsFixed(2)} (+$profit FCFA)',
        'is_system': true,
      });
    } catch (_) {}
  }

  // ─── Supabase : Paris multijoueur (aviator_bets) ────────

  /// Place une mise de maniere atomique (deduit les coins + insert la mise).
  /// Retourne null si succes, sinon le code d'erreur (ex: INSUFFICIENT_COINS).
  Future<String?> placeBetRpc({
    required int roundNum,
    required int slot,
    required int amount,
    required String username,
  }) async {
    try {
      await _db.rpc('aviator_place_bet', params: {
        'p_round_num': roundNum,
        'p_slot': slot,
        'p_amount': amount,
        'p_username': username,
      });
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Cashout atomique. Retourne le win (coins credites) ou null si erreur.
  Future<int?> cashoutRpc({
    required int roundNum,
    required int slot,
    required double mult,
  }) async {
    try {
      final res = await _db.rpc('aviator_cashout', params: {
        'p_round_num': roundNum,
        'p_slot': slot,
        'p_mult': mult,
      });
      if (res is int) return res;
      if (res is num) return res.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Marque une mise comme perdue apres crash (win_amount = 0).
  Future<void> settleLossRpc({required int roundNum, required int slot}) async {
    try {
      await _db.rpc('aviator_settle_loss', params: {
        'p_round_num': roundNum,
        'p_slot': slot,
      });
    } catch (_) {}
  }

  /// Liste les paris actifs du round courant (tous joueurs confondus).
  Future<List<LiveBet>> getCurrentRoundBets(int roundNum) async {
    try {
      final data = await _db
          .from('aviator_bets')
          .select()
          .eq('round_num', roundNum)
          .order('placed_at', ascending: true);
      return (data as List).map((j) => LiveBet.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Derniers cashouts reussis (pour feed "gains live") - tous rounds recents.
  Future<List<LiveBet>> getRecentWinnings({int limit = 30}) async {
    try {
      final data = await _db
          .from('aviator_bets')
          .select()
          .not('cashed_out_at', 'is', null)
          .order('placed_at', ascending: false)
          .limit(limit);
      return (data as List).map((j) => LiveBet.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Realtime ───────────────────────────────────────────
  RealtimeChannel subscribeLive({
    required void Function(AviatorChatMessage) onMessage,
    required void Function(CrashRound) onRound,
    required void Function(LiveBet) onBetPlaced,
    required void Function(LiveBet) onBetUpdated,
  }) {
    return _db
        .channel('aviator_live_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'aviator_chat',
          callback: (payload) {
            try {
              onMessage(AviatorChatMessage.fromJson(payload.newRecord));
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'aviator_rounds',
          callback: (payload) {
            try {
              onRound(CrashRound.fromJson(payload.newRecord));
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'aviator_bets',
          callback: (payload) {
            try {
              onBetPlaced(LiveBet.fromJson(payload.newRecord));
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'aviator_bets',
          callback: (payload) {
            try {
              onBetUpdated(LiveBet.fromJson(payload.newRecord));
            } catch (_) {}
          },
        )
        .subscribe();
  }
}

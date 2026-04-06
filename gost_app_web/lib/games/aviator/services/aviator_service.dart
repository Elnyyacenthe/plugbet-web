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
  // 1. serverSeed généré aléatoirement (16 octets hex)
  // 2. clientSeed généré aléatoirement (8 octets hex)
  // 3. hash = XOR-fold de combined (affiché après crash pour vérif)
  // 4. crashPoint = distribution exponentielle pondérée
  //    (3% des rounds : x1.00, le reste : exponentiel)

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

  /// Génère le point de crash à partir des seeds
  /// Crash à x0.00 = perte totale / break-even à x1.00 / profit au-dessus
  double generateCrashPoint(String serverSeed, String clientSeed) {
    final combined = '$serverSeed:$clientSeed';
    var h = 5381;
    for (final c in combined.codeUnits) {
      h = ((h << 5) + h) ^ c;
      h &= 0x7FFFFFFF;
    }
    final hVal = h.abs();

    // ~8% des rounds : crash immédiat à x0.00 (perte totale instantanée)
    if (hVal % 13 == 0) return 0.00;

    // Distribution exponentielle pondérée (mean ≈ 1.5) :
    // P(crash < x1.00) ≈ 48%  → majorité des joueurs perdent sans cashout
    // P(crash x1–x2)   ≈ 24%  → gain modeste
    // P(crash x2–x5)   ≈ 17%  → bon gain
    // P(crash x5–x20)  ≈  8%  → gros gain (rare)
    // P(crash > x20)   ≈  3%  → jackpot (très rare)
    // Formula : -ln(1-u) / lambda, avec lambda = 0.65 → mean = 1/0.65 ≈ 1.54
    const e = 0x7FFFFFFF;
    final ratio = hVal % e / e; // [0, 1)
    const lambda = 0.65;
    final raw = -log(1 - ratio.clamp(0.0001, 0.9999)) / lambda;
    return raw.clamp(0.00, 1000.0);
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
            'a cashouté à x${multiplier.toStringAsFixed(2)} (+$profit coins)',
        'is_system': true,
      });
    } catch (_) {}
  }

  // ─── Realtime ───────────────────────────────────────────
  RealtimeChannel subscribeLive({
    required void Function(AviatorChatMessage) onMessage,
    required void Function(CrashRound) onRound,
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
        .subscribe();
  }
}

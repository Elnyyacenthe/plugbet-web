// ============================================================
// WheelService — RPC wheel_spin + historique
// ============================================================
// Tout passe par le RPC server-side. Le client ne fait JAMAIS de RNG
// pour le segment gagnant : il anime juste vers la valeur retournee
// par le serveur.
//
// Le RPC :
//   wheel_spin(p_bets jsonb, p_request_id text) returns jsonb
//   - Idempotent via request_id (PK wheel_spins.id)
//   - Debit total_bet via _ledger_post + game_treasury +bet
//   - RNG segment 0..47 server-side (gen_random_bytes)
//   - Credit winnings = stake_on_winning_tile × (winning_tile + 1)
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wheel_models.dart';
import '../../../utils/logger.dart';

class WheelService {
  WheelService._();
  static final WheelService instance = WheelService._();

  static const _log = Logger('WHEEL');

  SupabaseClient get _client => Supabase.instance.client;
  final Random _rng = Random.secure();

  String? get currentUserId => _client.auth.currentUser?.id;

  final List<WheelSpinResult> _history = [];
  List<WheelSpinResult> get history => List.unmodifiable(_history);

  /// Genere un request_id stable. Reutilise sur les retries.
  /// Evite '1 << 32' (bug Flutter Web JS = 0).
  String generateRequestId() {
    final uid = currentUserId ?? 'anon';
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = _rng.nextInt(0x7FFFFFFF).toRadixString(16);
    return 'wheel_${uid}_${ts}_$r';
  }

  /// Lance un spin via RPC. Throws des StateError parlants si erreur.
  Future<WheelSpinResult> spin({
    required Map<WheelTile, int> chipsByTile,
    required String requestId,
  }) async {
    if (currentUserId == null) throw StateError('NOT_AUTH');

    // Validation cote client AVANT envoi (retour rapide).
    int total = 0;
    for (final e in chipsByTile.entries) {
      if (e.value < 0) throw ArgumentError('NEGATIVE_BET');
      if (e.value > 0 && e.value < kMinBetPerTile) {
        throw StateError('BET_TOO_LOW_ON_TILE');
      }
      if (e.value > kMaxBetPerTile) {
        throw StateError('BET_TOO_HIGH_ON_TILE');
      }
      total += e.value;
    }
    if (total < kMinTotalBet) throw StateError('TOTAL_BET_TOO_LOW');
    if (total > kMaxTotalBet) throw StateError('TOTAL_BET_TOO_HIGH');

    final betsJson = tilesToJsonMap(chipsByTile);

    try {
      final res = await _client.rpc('wheel_spin', params: {
        'p_bets': betsJson,
        'p_request_id': requestId,
      }).timeout(const Duration(seconds: 15));
      if (res is! Map) throw StateError('INVALID_RESPONSE');

      final data = Map<String, dynamic>.from(res);
      final segment = (data['segment'] as num).toInt();
      final winningTile = (data['winning_tile'] as num).toInt();
      final winnings = (data['winnings'] as num?)?.toInt() ?? 0;
      final totalBet = (data['total_bet'] as num).toInt();
      final newBalance = (data['new_balance'] as num).toInt();

      // Reparse les bets retournes par le serveur (echo)
      final Map<int, int> serverBets = {};
      final rawBets = data['bets'];
      if (rawBets is Map) {
        rawBets.forEach((k, v) {
          final tile = int.tryParse('$k');
          final stake = (v as num?)?.toInt() ?? 0;
          if (tile != null && stake > 0) serverBets[tile] = stake;
        });
      }

      final result = WheelSpinResult(
        segment: segment,
        winningTile: winningTile,
        winnings: winnings,
        totalBet: totalBet,
        newBalance: newBalance,
        bets: serverBets,
      );

      _log.info('spin OK seg=$segment tile=$winningTile '
          'totalBet=$totalBet winnings=$winnings');

      _history.insert(0, result);
      if (_history.length > 50) _history.removeLast();

      return result;
    } on PostgrestException catch (e) {
      _log.warn('spin RPC error: ${e.message} code=${e.code}');
      final msg = e.message;
      if (msg.contains('INSUFFICIENT_FUNDS')) throw StateError('INSUFFICIENT_FUNDS');
      if (msg.contains('RATE_LIMIT')) throw StateError('RATE_LIMIT');
      if (msg.contains('TOTAL_BET_TOO_LOW')) throw StateError('TOTAL_BET_TOO_LOW');
      if (msg.contains('TOTAL_BET_TOO_HIGH')) throw StateError('TOTAL_BET_TOO_HIGH');
      if (msg.contains('BET_TOO_LOW_ON_TILE')) throw StateError('BET_TOO_LOW_ON_TILE');
      if (msg.contains('BET_TOO_HIGH_ON_TILE')) throw StateError('BET_TOO_HIGH_ON_TILE');
      if (msg.contains('NOT_AUTH')) throw StateError('NOT_AUTH');
      // RPC pas deployee
      if (e.code == 'PGRST202' ||
          (msg.toLowerCase().contains('wheel_spin') &&
              msg.toLowerCase().contains('does not exist'))) {
        throw StateError('RPC_NOT_DEPLOYED');
      }
      throw StateError('RPC_ERROR: $msg');
    } on TimeoutException {
      throw StateError('TIMEOUT');
    }
  }

  /// Charge les N derniers spins (RLS = owner-only).
  Future<List<WheelSpinResult>> getRecentSpins({int limit = 20}) async {
    if (currentUserId == null) return const [];
    try {
      final rows = await _client.from('wheel_spins')
          .select('bets, total_bet, segment, winning_tile, winnings')
          .order('created_at', ascending: false).limit(limit);
      return (rows as List).map((r) {
        final m = Map<String, dynamic>.from(r);
        final Map<int, int> bets = {};
        if (m['bets'] is Map) {
          (m['bets'] as Map).forEach((k, v) {
            final t = int.tryParse('$k');
            final s = (v as num?)?.toInt() ?? 0;
            if (t != null && s > 0) bets[t] = s;
          });
        }
        return WheelSpinResult(
          segment: (m['segment'] as num).toInt(),
          winningTile: (m['winning_tile'] as num).toInt(),
          winnings: (m['winnings'] as num?)?.toInt() ?? 0,
          totalBet: (m['total_bet'] as num).toInt(),
          newBalance: 0, // pas pertinent pour historique
          bets: bets,
        );
      }).toList();
    } catch (e) {
      _log.warn('getRecentSpins error: $e');
      return const [];
    }
  }
}

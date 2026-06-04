// ============================================================
// SlotsService — Phase 2 : RPC server-side via caisse principale
// ============================================================
// spin() appelle slots_spin() Supabase :
//   - Debit wallet (V2 ledger) + credit caisse principale (game_treasury)
//   - RNG crypto serveur (gen_random_bytes + rejection sampling)
//   - Idempotent via request_id (PK = request_id)
//   - Credit user + retire caisse si gain
//
// Le client ne fait PAS de RNG. Le résultat vient du serveur.
//
// Mode demo (offline) : si Supabase non dispo, fallback local RNG
// pour permettre de jouer en dev sans connexion. En prod = RPC only.
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/slot_models.dart';
import '../../../utils/logger.dart';

class SlotsService {
  SlotsService._();
  static final SlotsService instance = SlotsService._();

  static const _log = Logger('SLOTS');

  SupabaseClient get _client => Supabase.instance.client;
  final Random _rng = Random.secure();

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Historique des spins du user courant (cache local, 50 max).
  /// Phase 2 : on garde le cache local pour eviter de refetch a chaque
  /// retour sur l'ecran. Recharge initiale = getRecentSpins().
  final List<SpinResult> _history = [];
  List<SpinResult> get history => List.unmodifiable(_history);

  /// Genere un request_id stable pour un spin. A garder identique sur
  /// chaque retry pour que la RPC deduplique.
  ///
  /// IMPORTANT : on n'utilise PAS `1 << 32` ici car sur Flutter Web
  /// (compilation JS), les shifts sont limites a 32-bit signed donc
  /// `1 << 32 == 0` et `nextInt(0)` throw RangeError. Le throw remontait
  /// hors du try/catch du provider et bloquait `_spinning = true` -> le
  /// bouton SPIN restait grise. On utilise 0x7FFFFFFF qui est safe natif+web.
  String generateRequestId() {
    final uid = currentUserId ?? 'anon';
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = _rng.nextInt(0x7FFFFFFF).toRadixString(16);
    return 'slot_${uid}_${ts}_$r';
  }

  /// Mappe un nom de symbole serveur ('cherry', 'seven', ...) vers SlotSymbol.
  SlotSymbol _parseSymbol(String name) {
    switch (name) {
      case 'cherry': return SlotSymbol.cherry;
      case 'lemon':  return SlotSymbol.lemon;
      case 'orange': return SlotSymbol.orange;
      case 'grape':  return SlotSymbol.grape;
      case 'bell':   return SlotSymbol.bell;
      case 'bar':    return SlotSymbol.bar;
      case 'seven':  return SlotSymbol.seven;
      default:       return SlotSymbol.blank;
    }
  }

  /// Spin reel via RPC.
  Future<SpinResult> spin({
    required int bet,
    required String requestId,
  }) async {
    if (!isValidBet(bet)) {
      throw ArgumentError('BET_NOT_ALLOWED');
    }
    if (currentUserId == null) {
      throw StateError('NOT_AUTH');
    }

    try {
      final res = await _client.rpc('slots_spin', params: {
        'p_bet': bet,
        'p_request_id': requestId,
      }).timeout(const Duration(seconds: 15));
      if (res is! Map) throw StateError('INVALID_RESPONSE');

      final data = Map<String, dynamic>.from(res);
      final reels = (data['reels'] as List).map((e) => _parseSymbol('$e')).toList();
      final multiplier = (data['multiplier'] as num?)?.toInt() ?? 0;
      final payout = (data['payout'] as num?)?.toInt() ?? 0;
      final newBalance = (data['new_balance'] as num?)?.toInt() ?? 0;

      String? label;
      if (Paytable.isJackpot(multiplier)) {
        label = 'JACKPOT';
      } else if (Paytable.isBigWin(multiplier)) {
        label = 'BIG WIN';
      } else if (multiplier > 0) {
        label = 'WIN';
      }

      final result = SpinResult(
        reels: reels,
        bet: bet,
        multiplier: multiplier,
        payout: payout,
        newBalance: newBalance,
        winLabel: label,
      );

      _log.info('spin OK bet=$bet reels=$reels mult=$multiplier '
          'payout=$payout newBal=$newBalance');

      _history.insert(0, result);
      if (_history.length > 50) _history.removeLast();

      return result;
    } on PostgrestException catch (e) {
      _log.warn('spin RPC error: ${e.message} code=${e.code}');
      if (e.message.contains('INSUFFICIENT_FUNDS')) {
        throw StateError('INSUFFICIENT_FUNDS');
      }
      if (e.message.contains('RATE_LIMIT')) {
        throw StateError('RATE_LIMIT');
      }
      if (e.message.contains('INVALID_BET')) {
        throw ArgumentError('BET_NOT_ALLOWED');
      }
      // 'violates check constraint wallet_ledger' : desync entre
      // wallet_balance affiche en UI et la realite ledger. Code dedie
      // -> le provider doit refresh le wallet et donner un message clair.
      final lower = e.message.toLowerCase();
      if (lower.contains('violates check constraint') &&
          (lower.contains('wallet_ledger') ||
              lower.contains('balance_after'))) {
        throw StateError('BALANCE_DESYNC');
      }
      // RPC slots_spin inexistante (SQL migration pas executee).
      // On verifie de maniere stricte pour ne pas faussement matcher
      // 'wallet_apply_delta does not exist' ou autres dependances.
      final msgLower = e.message.toLowerCase();
      final isMissingSlotsSpin = e.code == 'PGRST202' ||
          msgLower.contains('function public.slots_spin') ||
          (msgLower.contains('slots_spin') &&
              (msgLower.contains('does not exist') ||
                  msgLower.contains('not found')));
      if (isMissingSlotsSpin) {
        throw StateError('RPC_NOT_DEPLOYED');
      }
      // Autre erreur de dependance (wallet_apply_delta absent,
      // game_treasury absent, etc.) -> on propage avec le vrai message.
      throw StateError('RPC_ERROR: ${e.message}');
    } on TimeoutException {
      _log.warn('spin RPC timeout (>15s)');
      throw StateError('TIMEOUT');
    }
  }

  /// Charge les N derniers spins du user (RLS = owner-only).
  Future<List<SpinResult>> getRecentSpins({int limit = 20}) async {
    if (currentUserId == null) return const [];
    try {
      final rows = await _client.from('slot_spins')
          .select('bet_amount, reels, multiplier, payout')
          .order('created_at', ascending: false).limit(limit);
      return (rows as List).map((r) {
        final m = Map<String, dynamic>.from(r);
        final reels = (m['reels'] as List).map((e) => _parseSymbol('$e')).toList();
        final mult = (m['multiplier'] as num?)?.toInt() ?? 0;
        String? label;
        if (Paytable.isJackpot(mult)) {
          label = 'JACKPOT';
        } else if (Paytable.isBigWin(mult)) {
          label = 'BIG WIN';
        } else if (mult > 0) {
          label = 'WIN';
        }
        return SpinResult(
          reels: reels,
          bet: (m['bet_amount'] as num).toInt(),
          multiplier: mult,
          payout: (m['payout'] as num?)?.toInt() ?? 0,
          newBalance: 0, // pas pertinent pour historique
          winLabel: label,
        );
      }).toList();
    } catch (e) {
      _log.warn('getRecentSpins error: $e');
      return const [];
    }
  }
}

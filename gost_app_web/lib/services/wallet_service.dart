// ============================================================
// WalletService — Operations sur le wallet (coins)
// Source unique pour toutes les operations de FCFA.
//
// IMPORTANT : les operations atomiques (deduct/add) passent par la RPC
// `my_wallet_apply_delta` qui :
//   1. Verrouille la ligne user (FOR UPDATE) → pas de race condition
//   2. Verifie le solde avant de debiter
//   3. Enregistre chaque operation dans wallet_transactions (audit trail)
//
// En fallback (si la RPC n'est pas encore deployee), l'ancienne methode
// non-atomique est utilisee mais un warning est loggue.
// ============================================================
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class WalletService {
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal();

  static const _log = Logger('WALLET');
  final SupabaseClient _client = Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // ============================================================
  // PROFIL
  // ============================================================

  Future<Map<String, dynamic>?> getProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final res = await _client
          .from('user_profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (res == null) {
        await _client.from('user_profiles').insert({
          'id': uid,
          'username': 'Joueur${uid.substring(0, 4)}',
          'coins': 1000,
        });
        return getProfile();
      }
      return res;
    } catch (e, s) {
      _log.error('getProfile', e, s);
      return null;
    }
  }

  Future<int> getCoins() async {
    final p = await getProfile();
    return p?['coins'] as int? ?? 0;
  }

  Future<String> getUsername() async {
    final p = await getProfile();
    return p?['username'] as String? ?? 'Joueur';
  }

  // ============================================================
  // OPERATIONS ATOMIQUES via RPC
  // ============================================================

  /// Retire des FCFA au joueur courant.
  /// Retourne true si l'operation a reussi (solde suffisant).
  ///
  /// [source] : identifiant de la source ('aviator', 'apple_fortune', ...)
  /// [referenceId] : id de session/round/match optionnel
  Future<bool> deductCoins(
    int amount, {
    String source = 'generic',
    String? referenceId,
    String? note,
  }) async {
    if (amount <= 0) return true;
    final uid = currentUserId;
    if (uid == null) return false;

    try {
      final res = await _client.rpc('my_wallet_apply_delta', params: {
        'p_delta': -amount,
        'p_source': source,
        'p_reference_id': referenceId,
        'p_note': note,
      });
      if (res is Map && res.containsKey('error')) {
        _log.warn('deductCoins refuse: ${res['error']}');
        return false;
      }
      return res != null;
    } catch (e, s) {
      _log.error('deductCoins RPC failed, fallback legacy', e, s);
      return _legacyDeduct(amount);
    }
  }

  /// Crediter des FCFA au joueur courant.
  Future<bool> addCoins(
    int amount, {
    String source = 'generic',
    String? referenceId,
    String? note,
  }) async {
    if (amount <= 0) return true;
    final uid = currentUserId;
    if (uid == null) return false;

    try {
      final res = await _client.rpc('my_wallet_apply_delta', params: {
        'p_delta': amount,
        'p_source': source,
        'p_reference_id': referenceId,
        'p_note': note,
      });
      if (res is Map && res.containsKey('error')) {
        _log.warn('addCoins refuse: ${res['error']}');
        return false;
      }
      return res != null;
    } catch (e, s) {
      _log.error('addCoins RPC failed, fallback legacy', e, s);
      return _legacyAdd(amount);
    }
  }

  /// Crediter un autre utilisateur (pour jeux multijoueurs).
  /// Passe par la RPC admin-level (necessite que le backend autorise).
  Future<void> addCoinsToUser(
    String userId,
    int amount, {
    String source = 'multiplayer_win',
    String? referenceId,
  }) async {
    if (amount <= 0) return;
    try {
      await _client.rpc('wallet_apply_delta', params: {
        'p_user_id': userId,
        'p_delta': amount,
        'p_source': source,
        'p_reference_id': referenceId,
      });
    } catch (e, s) {
      _log.error('addCoinsToUser RPC failed, fallback legacy', e, s);
      await _legacyAddToUser(userId, amount);
    }
  }

  // ============================================================
  // FALLBACK LEGACY (non-atomique)
  // Utilise uniquement si la RPC n'est pas encore deployee
  // ============================================================

  Future<bool> _legacyDeduct(int amount) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final coins = await getCoins();
      if (coins < amount) return false;
      await _client
          .from('user_profiles')
          .update({'coins': coins - amount}).eq('id', uid);
      return true;
    } catch (e, s) {
      _log.error('legacyDeduct', e, s);
      return false;
    }
  }

  Future<bool> _legacyAdd(int amount) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final coins = await getCoins();
      await _client
          .from('user_profiles')
          .update({'coins': coins + amount}).eq('id', uid);
      return true;
    } catch (e, s) {
      _log.error('legacyAdd', e, s);
      return false;
    }
  }

  Future<void> _legacyAddToUser(String userId, int amount) async {
    try {
      final profile = await _client
          .from('user_profiles')
          .select('coins')
          .eq('id', userId)
          .maybeSingle();
      final current = profile?['coins'] as int? ?? 0;
      await _client
          .from('user_profiles')
          .update({'coins': current + amount}).eq('id', userId);
    } catch (e, s) {
      _log.error('legacyAddToUser', e, s);
    }
  }
}

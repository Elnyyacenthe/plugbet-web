// ============================================================
// ProfileService — Operations liees au profil utilisateur
// (stats, transactions, demandes d'amitie envoyees)
// ============================================================
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class ProfileService {
  static const _log = Logger('PROFILE');
  final SupabaseClient _client = Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;
  User? get currentUser => _client.auth.currentUser;

  /// Profil complet de l'utilisateur courant.
  Future<Map<String, dynamic>?> getMyProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final res = await _client
          .from('user_profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      return res;
    } catch (e, s) {
      _log.error('getMyProfile', e, s);
      return null;
    }
  }

  /// Demandes d'amitie envoyees par l'utilisateur courant (avec username).
  Future<List<Map<String, dynamic>>> getSentFriendRequests() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await _client
          .from('friend_requests')
          .select('id, to_id, status, created_at')
          .eq('from_id', uid)
          .order('created_at', ascending: false);

      // Enrichit avec username (1 query par destinataire)
      final results = <Map<String, dynamic>>[];
      for (final row in (data as List)) {
        final toId = row['to_id'] as String? ?? '';
        String username = 'Joueur';
        try {
          final p = await _client
              .from('user_profiles')
              .select('username')
              .eq('id', toId)
              .maybeSingle();
          if (p != null) username = p['username'] as String? ?? 'Joueur';
        } catch (_) {}
        results.add({
          ...row,
          'to_username': username,
        });
      }
      return results;
    } catch (e, s) {
      _log.error('getSentFriendRequests', e, s);
      return [];
    }
  }

  /// Historique des transactions de paris Ludo de l'utilisateur courant.
  /// Retourne une liste enrichie avec le delta calcule.
  Future<List<Map<String, dynamic>>> getLudoTransactions({int limit = 50}) async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final ludo = await _client
          .from('ludo_challenges')
          .select('id, bet_amount, status, created_at, from_user, to_user')
          .or('from_user.eq.$uid,to_user.eq.$uid')
          .order('created_at', ascending: false)
          .limit(limit);

      final txList = <Map<String, dynamic>>[];
      for (final row in ludo) {
        final bet = row['bet_amount'] as int? ?? 0;
        final fromUser = row['from_user'] as String?;
        final status = row['status'] as String? ?? '';
        final isFromMe = fromUser == uid;

        int delta = 0;
        String label = '';
        if (status == 'completed') {
          delta = isFromMe ? -bet : bet; // simplification
          label = isFromMe ? 'Mise Ludo' : 'Gain Ludo';
        }
        txList.add({
          ...row,
          'delta': delta,
          'label': label,
        });
      }
      return txList;
    } catch (e, s) {
      _log.error('getLudoTransactions', e, s);
      return [];
    }
  }

  /// Historique complet via la nouvelle table wallet_transactions.
  /// Retourne les N dernieres transactions (toutes sources confondues).
  Future<List<Map<String, dynamic>>> getWalletTransactions(
      {int limit = 100}) async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await _client
          .from('wallet_transactions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (e, s) {
      _log.error('getWalletTransactions', e, s);
      return [];
    }
  }

  /// Deconnexion.
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e, s) {
      _log.error('signOut', e, s);
    }
  }

  /// True si l'utilisateur est anonyme (pas d'email).
  bool get isAnonymous {
    final u = currentUser;
    return u == null || u.email == null || u.email!.isEmpty;
  }
}

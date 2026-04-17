// ============================================================
// UserSearchService — Recherche et listing de profils utilisateurs
// Encapsule les queries Supabase pour ne pas les laisser dans les screens
// ============================================================
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class UserSearchService {
  static const _log = Logger('USER_SEARCH');
  final SupabaseClient _client = Supabase.instance.client;

  String? get _myId => _client.auth.currentUser?.id;

  /// Top N joueurs triés par XP (excluant l'utilisateur courant).
  Future<List<Map<String, dynamic>>> topPlayers({int limit = 50}) async {
    try {
      final data = await _client
          .from('user_profiles')
          .select('id, username, xp, coins, total_wins, avatar_url')
          .neq('id', _myId ?? '')
          .order('xp', ascending: false)
          .limit(limit);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (e, s) {
      _log.error('topPlayers', e, s);
      return [];
    }
  }

  /// Recherche par fragment de username (case-insensitive).
  Future<List<Map<String, dynamic>>> searchByUsername(
    String query, {
    int limit = 30,
  }) async {
    if (query.trim().isEmpty) return [];
    try {
      final data = await _client
          .from('user_profiles')
          .select('id, username, xp, coins, total_wins, avatar_url')
          .ilike('username', '%${query.trim()}%')
          .neq('id', _myId ?? '')
          .limit(limit);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (e, s) {
      _log.error('searchByUsername', e, s);
      return [];
    }
  }

  /// Profil public d'un utilisateur par son id.
  Future<Map<String, dynamic>?> getProfileById(String userId) async {
    try {
      final p = await _client
          .from('user_profiles')
          .select('id, username, xp, coins, total_wins, avatar_url')
          .eq('id', userId)
          .maybeSingle();
      return p;
    } catch (e, s) {
      _log.error('getProfileById', e, s);
      return null;
    }
  }

  /// Verifie l'etat de la relation avec un autre utilisateur.
  /// Retourne 'friends' | 'request_sent' | 'request_received' | 'none'
  Future<String> relationWith(String otherId) async {
    final uid = _myId;
    if (uid == null) return 'none';
    try {
      final friendship = await _client
          .from('friendships')
          .select('id')
          .eq('user_id', uid)
          .eq('friend_id', otherId)
          .maybeSingle();
      if (friendship != null) return 'friends';

      final sent = await _client
          .from('friend_requests')
          .select('id')
          .eq('from_id', uid)
          .eq('to_id', otherId)
          .eq('status', 'pending')
          .maybeSingle();
      if (sent != null) return 'request_sent';

      final received = await _client
          .from('friend_requests')
          .select('id')
          .eq('from_id', otherId)
          .eq('to_id', uid)
          .eq('status', 'pending')
          .maybeSingle();
      if (received != null) return 'request_received';

      return 'none';
    } catch (e, s) {
      _log.error('relationWith', e, s);
      return 'none';
    }
  }
}

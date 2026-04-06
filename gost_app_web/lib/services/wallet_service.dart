// ============================================================
// WalletService – Caisse générale (profiles table)
// Source unique pour toutes les opérations de coins
// ============================================================
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WalletService {
  // Singleton pour partager l'instance entre tous les services
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal();

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
    } catch (e) {
      debugPrint('[WALLET] getProfile: $e');
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
  // OPÉRATIONS COINS (joueur courant)
  // ============================================================

  Future<bool> deductCoins(int amount) async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final coins = await getCoins();
      if (coins < amount) return false;
      await _client
          .from('user_profiles')
          .update({'coins': coins - amount}).eq('id', uid);
      return true;
    } catch (e) {
      debugPrint('[WALLET] deductCoins: $e');
      return false;
    }
  }

  Future<void> addCoins(int amount) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      final coins = await getCoins();
      await _client
          .from('user_profiles')
          .update({'coins': coins + amount}).eq('id', uid);
    } catch (e) {
      debugPrint('[WALLET] addCoins: $e');
    }
  }

  // ============================================================
  // OPÉRATIONS COINS (n'importe quel utilisateur – gains)
  // ============================================================

  Future<void> addCoinsToUser(String userId, int amount) async {
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
    } catch (e) {
      debugPrint('[WALLET] addCoinsToUser: $e');
    }
  }
}

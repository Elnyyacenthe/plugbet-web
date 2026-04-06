// ============================================================
// Solitaire – Service (coins + best score via caisse générale)
// ============================================================
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/wallet_service.dart';

class SolitaireService {
  final SupabaseClient _client = Supabase.instance.client;
  final WalletService _wallet = WalletService();

  String? get currentUserId => _client.auth.currentUser?.id;

  // Délégation à la caisse générale
  Future<Map<String, dynamic>?> getProfile() => _wallet.getProfile();
  Future<int> getCoins() => _wallet.getCoins();
  Future<bool> deductCoins(int amount) => _wallet.deductCoins(amount);
  Future<void> addCoins(int amount) => _wallet.addCoins(amount);

  Future<void> saveBestScore(int score) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      final p = await _wallet.getProfile();
      final best = p?['solitaire_best_score'] as int? ?? 0;
      if (score > best) {
        await _client.from('user_profiles').update({'solitaire_best_score': score}).eq('id', uid);
      }
    } catch (e) {
      debugPrint('[SOLITAIRE] saveBestScore: $e');
    }
  }
}

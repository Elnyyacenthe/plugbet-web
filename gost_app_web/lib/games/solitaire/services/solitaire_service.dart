// ============================================================
// Solitaire – Service (treasury unifie : 1 RPC = 1 mouvement)
// ============================================================
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/wallet_service.dart';

class SolitaireService {
  final SupabaseClient _client = Supabase.instance.client;
  final WalletService _wallet = WalletService();

  String? get currentUserId => _client.auth.currentUser?.id;

  // Lecture seule via le wallet (pas de mouvements)
  Future<Map<String, dynamic>?> getProfile() => _wallet.getProfile();
  Future<int> getCoins() => _wallet.getCoins();

  /// Mise du joueur via le treasury (atomique, debit + log).
  Future<bool> placeBet(int amount) async {
    try {
      await _client.rpc('solitaire_place_bet', params: {'p_amount': amount});
      return true;
    } catch (e) {
      debugPrint('[SOLITAIRE] placeBet: $e');
      return false;
    }
  }

  /// Joueur gagne : un seul appel RPC qui credite 90% au joueur et 10%
  /// a la caisse. Retourne le NET recu.
  Future<int> payWin(int gross) async {
    try {
      final r = await _client.rpc('solitaire_payout', params: {'p_gross': gross});
      if (r is num) return r.toInt();
      return 0;
    } catch (e) {
      debugPrint('[SOLITAIRE] payWin: $e');
      return 0;
    }
  }

  // Anciennes API (gardees pour compat, redirigent vers les nouvelles)
  Future<bool> deductCoins(int amount) => placeBet(amount);
  Future<void> addCoins(int amount) async { await payWin(amount); }

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

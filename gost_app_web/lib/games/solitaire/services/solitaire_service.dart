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

  /// Mise du joueur (deduit son wallet ET envoie a la caisse jeu)
  Future<bool> placeBet(int amount) async {
    final ok = await _wallet.deductCoins(amount);
    if (!ok) return false;
    // La mise va dans la caisse du jeu (solitaire est solo)
    try {
      await _client.rpc('game_treasury_collect_loss', params: {
        'p_amount': amount,
        'p_game_type': 'solitaire',
        'p_user_id': currentUserId,
        'p_description': 'Solitaire: mise placee',
      });
    } catch (e) {
      debugPrint('[SOLITAIRE] treasury_collect: $e');
    }
    return true;
  }

  /// Joueur gagne : on credite son wallet ET on retire de la caisse jeu
  Future<void> payWin(int amount) async {
    await _wallet.addCoins(amount);
    try {
      await _client.rpc('game_treasury_pay_win', params: {
        'p_amount': amount,
        'p_game_type': 'solitaire',
        'p_user_id': currentUserId,
        'p_description': 'Solitaire: gain',
      });
    } catch (e) {
      debugPrint('[SOLITAIRE] treasury_pay: $e');
    }
  }

  // Anciennes API (gardées pour compat)
  Future<bool> deductCoins(int amount) => placeBet(amount);
  Future<void> addCoins(int amount) => payWin(amount);

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

// ============================================================
// Apple of Fortune – Service (Supabase RPC + Wallet)
// ============================================================
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/wallet_service.dart';
import '../models/apple_fortune_models.dart';

class AppleFortuneService {
  static final AppleFortuneService instance = AppleFortuneService._();
  AppleFortuneService._();

  final _db = Supabase.instance.client;
  final _wallet = WalletService();

  String? get _uid => _db.auth.currentUser?.id;

  // ──────────────────────────────────────────────
  // CREATE SESSION
  // Deducts bet, creates server-side session with hidden board
  // ──────────────────────────────────────────────
  Future<AppleFortuneSession?> createSession({
    required int betAmount,
    required AppleFortuneDifficulty difficulty,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final res = await _db.rpc('create_apple_fortune_session', params: {
        'p_user_id': uid,
        'p_bet_amount': betAmount,
        'p_columns': difficulty.columns,
        'p_safe_tiles': difficulty.safeTiles,
        'p_total_rows': difficulty.totalRows,
      });

      if (res == null) return null;
      if (res is Map && res.containsKey('error')) {
        debugPrint('[APPLE] create error: ${res['error']}');
        return null;
      }

      return AppleFortuneSession.fromJson(res as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[APPLE] createSession: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // REVEAL TILE
  // Player picks a tile on the current row
  // Backend validates and returns updated state
  // ──────────────────────────────────────────────
  Future<Map<String, dynamic>?> revealTile({
    required String sessionId,
    required int tileIndex,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final res = await _db.rpc('reveal_apple_fortune_tile', params: {
        'p_session_id': sessionId,
        'p_user_id': uid,
        'p_tile_index': tileIndex,
      });

      if (res == null) return null;
      return res as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[APPLE] revealTile: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // CASH OUT
  // Player collects current winnings
  // ──────────────────────────────────────────────
  Future<Map<String, dynamic>?> cashOut({
    required String sessionId,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final res = await _db.rpc('cashout_apple_fortune_session', params: {
        'p_session_id': sessionId,
        'p_user_id': uid,
      });

      if (res == null) return null;
      return res as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[APPLE] cashOut: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // GET SESSION STATE
  // Recover session (e.g., after app restart)
  // ──────────────────────────────────────────────
  Future<AppleFortuneSession?> getActiveSession() async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final res = await _db.rpc('get_apple_fortune_state', params: {
        'p_user_id': uid,
      });

      if (res == null) return null;
      if (res is Map && res.containsKey('error')) return null;

      return AppleFortuneSession.fromJson(res as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[APPLE] getActiveSession: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // WALLET helpers (for UI refresh)
  // ──────────────────────────────────────────────
  Future<int> getCoins() => _wallet.getCoins();
}

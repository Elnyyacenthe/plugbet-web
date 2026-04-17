// ============================================================
// Mines — Service (Supabase RPC + wallet)
// ============================================================
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/wallet_service.dart';
import '../../../utils/logger.dart';
import '../models/mines_models.dart';

class MinesService {
  static final MinesService instance = MinesService._();
  MinesService._();

  static const _log = Logger('MINES');
  final _db = Supabase.instance.client;
  final _wallet = WalletService();

  String? get _uid => _db.auth.currentUser?.id;

  /// Cree une session : deduit la mise, genere les positions des mines
  Future<MinesSession?> createSession({
    required int betAmount,
    required int minesCount,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final res = await _db.rpc('create_mines_session', params: {
        'p_user_id': uid,
        'p_bet_amount': betAmount,
        'p_mines_count': minesCount,
      });

      if (res == null) return null;
      if (res is Map && res.containsKey('error')) {
        _log.warn('createSession error: ${res['error']}');
        return null;
      }
      return MinesSession.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e, s) {
      _log.error('createSession', e, s);
      return null;
    }
  }

  /// Joueur revele une case (position 0..24)
  Future<Map<String, dynamic>?> revealTile({
    required String sessionId,
    required int position,
  }) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final res = await _db.rpc('reveal_mines_tile', params: {
        'p_session_id': sessionId,
        'p_user_id': uid,
        'p_position': position,
      });

      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (e, s) {
      _log.error('revealTile', e, s);
      return null;
    }
  }

  /// Encaisse le gain actuel et termine la session
  Future<Map<String, dynamic>?> cashOut({required String sessionId}) async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final res = await _db.rpc('cashout_mines_session', params: {
        'p_session_id': sessionId,
        'p_user_id': uid,
      });

      if (res == null) return null;
      return Map<String, dynamic>.from(res as Map);
    } catch (e, s) {
      _log.error('cashOut', e, s);
      return null;
    }
  }

  /// Recuperer une session active (ex: apres redemarrage de l'app)
  Future<MinesSession?> getActiveSession() async {
    final uid = _uid;
    if (uid == null) return null;

    try {
      final res = await _db.rpc('get_mines_state', params: {
        'p_user_id': uid,
      });

      if (res == null) return null;
      if (res is Map && res.containsKey('error')) return null;
      return MinesSession.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e, s) {
      _log.error('getActiveSession', e, s);
      return null;
    }
  }

  Future<int> getCoins() => _wallet.getCoins();
}

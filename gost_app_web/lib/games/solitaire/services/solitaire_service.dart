// ============================================================
// SOLITAIRE V2 — Service (session-based, idempotent, anti-cheat)
// ============================================================
// Refonte complète conformément à l'audit P0 :
//   - placeBet retourne un session_id signé serveur
//   - payWin n'accepte plus de gross du client (calculé serveur)
//   - reprise de session après crash via getActiveSession
//   - retry automatique sur les RPCs critiques
//   - dédup anti double-tap via _inFlight
// ============================================================
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/wallet_service.dart';
import '../../../services/game_audit_service.dart';

class SolitaireService {
  final SupabaseClient _client = Supabase.instance.client;
  final WalletService _wallet = WalletService();

  String? get currentUserId => _client.auth.currentUser?.id;

  // ============================================================
  // IDEMPOTENCE : déduplication anti double-tap
  // ============================================================
  final Map<String, Future<dynamic>> _inFlight = {};

  Future<T> _dedup<T>(String key, Future<T> Function() fn) async {
    if (_inFlight.containsKey(key)) {
      return await _inFlight[key]! as T;
    }
    final fut = fn();
    _inFlight[key] = fut;
    try {
      return await fut;
    } finally {
      _inFlight.remove(key);
    }
  }

  // Lecture seule wallet
  Future<Map<String, dynamic>?> getProfile() => _wallet.getProfile();
  Future<int> getCoins() => _wallet.getCoins();

  // ============================================================
  // 1. placeBet — débit + crée session côté serveur
  // ============================================================
  /// Retourne la session ouverte (id, bet, expires_at) ou throws.
  /// L'id est utilisé pour TOUS les appels subséquents (payWin, cancel).
  Future<Map<String, dynamic>?> placeBet({
    required int amount,
    bool isPractice = false,
  }) {
    final uid = currentUserId ?? 'anon';
    return _dedup('place:$uid:$amount:$isPractice', () async {
      try {
        final res = await _client.rpc('solitaire_place_bet', params: {
          'p_amount': amount,
          'p_is_practice': isPractice,
        });
        if (res is! Map) return null;
        final session = Map<String, dynamic>.from(res);
        // Audit (fire-and-forget)
        unawaited(GameAuditService.instance.logGameStart(
          gameId: session['session_id'] as String,
          gameType: 'solitaire',
          payload: {'bet': amount, 'is_practice': isPractice},
        ));
        if (!isPractice) {
          unawaited(GameAuditService.instance.logBetPlaced(
            gameId: session['session_id'] as String,
            gameType: 'solitaire',
            amount: amount,
          ));
        }
        return session;
      } catch (e) {
        debugPrint('[SOLITAIRE] placeBet: $e');
        rethrow;
      }
    });
  }

  // ============================================================
  // 2. payWin — payout server-validé, idempotent, avec retry
  // ============================================================
  /// Le serveur recalcule le payout. Le client envoie SEULEMENT
  /// session_id, score, won. Aucune manipulation possible.
  Future<Map<String, dynamic>?> finishSession({
    required String sessionId,
    required int score,
    required bool won,
    List<Map<String, dynamic>> moves = const [],
  }) {
    return _dedup('finish:$sessionId', () async {
      // Retry exponentiel jusqu'à 3 tentatives (timeout réseau, 5xx)
      Object? lastError;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final res = await _client.rpc('solitaire_payout', params: {
            'p_session_id': sessionId,
            'p_score': score,
            'p_won': won,
            'p_moves': moves,
          });
          if (res is! Map) return null;
          final r = Map<String, dynamic>.from(res);
          unawaited(GameAuditService.instance.logGameEnd(
            gameId: sessionId,
            gameType: 'solitaire',
            won: won,
            payout: (r['paid'] as num?)?.toInt() ?? 0,
            extra: {
              'gross': r['gross'],
              'commission': r['commission'],
              'state': r['state'],
              'idempotent': r['idempotent'] ?? false,
            },
          ));
          return r;
        } on PostgrestException catch (e) {
          lastError = e;
          // Erreurs métier non-retryables → on remonte tout de suite
          if (e.code == 'P0008' || // SESSION_EXPIRED
              e.code == 'P0007' || // SESSION_INVALID_STATE
              e.code == 'P0002' || // SESSION_NOT_FOUND
              e.code == 'P0009') { // DAILY_PAYOUT_CAP
            rethrow;
          }
          await Future.delayed(Duration(seconds: 1 << attempt));
        } catch (e) {
          lastError = e;
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
      throw lastError ?? Exception('payout_failed_after_retries');
    });
  }

  // ============================================================
  // 3. cancelSession — annule dans les 5 premières secondes
  // ============================================================
  Future<Map<String, dynamic>?> cancelSession(String sessionId) {
    return _dedup('cancel:$sessionId', () async {
      try {
        final res = await _client.rpc('solitaire_cancel_session', params: {
          'p_session_id': sessionId,
        });
        if (res is Map) return Map<String, dynamic>.from(res);
        return null;
      } catch (e) {
        debugPrint('[SOLITAIRE] cancelSession: $e');
        return null;
      }
    });
  }

  // ============================================================
  // 4. getActiveSession — reprise après crash
  // ============================================================
  Future<Map<String, dynamic>?> getActiveSession() async {
    try {
      final res = await _client.rpc('solitaire_get_active_session');
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (e) {
      debugPrint('[SOLITAIRE] getActiveSession: $e');
      return null;
    }
  }

  // ============================================================
  // 5. saveBestScore — via RPC sécurisée
  // ============================================================
  Future<bool> saveBestScore(int score) async {
    try {
      final res = await _client.rpc('update_solitaire_best_score', params: {
        'p_score': score,
      });
      if (res is Map) return res['updated'] == true;
      return false;
    } catch (e) {
      debugPrint('[SOLITAIRE] saveBestScore: $e');
      return false;
    }
  }

  // ============================================================
  // DEPRECATED — anciennes APIs vulnérables
  // ============================================================
  @Deprecated('Use placeBet() qui retourne un session_id signé serveur.')
  Future<bool> deductCoins(int amount) async {
    final r = await placeBet(amount: amount);
    return r != null;
  }

  @Deprecated('Use finishSession() avec session_id. addCoins(brut) permet le vol.')
  Future<void> addCoins(int amount) async {
    debugPrint('[SOLITAIRE] addCoins legacy appelé — NO-OP. '
        'Utilise finishSession(sessionId, score, won) à la place.');
    // Volontairement no-op : laisser passer permettrait le vol.
  }
}

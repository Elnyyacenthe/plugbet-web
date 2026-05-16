// ============================================================
// KpayService – Gestion des paiements via K-Pay API v1
// ============================================================
// Base URL : https://admin.kpay.site
//
// Flux:
// 1. DEPOSIT : POST /api/v1/payments/init -> user valide sur tel
//    -> polling GET /api/v1/payments/:id -> credit wallet
// 2. WITHDRAW : debit wallet -> POST /api/v1/payments/withdraw
//    -> polling GET /api/v1/payments/withdraw/:id -> finalise
//
// Auth : headers X-API-Key + X-Secret-Key
// Montant 1:1 (1 FCFA = 1 unite K-Pay). Aucun calcul de frais cote app.
// Pas de webhook : resolution de statut par polling de l'API.
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../utils/logger.dart';

class KpayService {
  static const _log = Logger('KPAY');
  static const _defaultBaseUrl = 'https://admin.kpay.site';

  /// Montant minimum de retrait imposé par K-Pay (refus 400 en dessous).
  static const int minWithdrawalAmount = 100;
  final _client = Supabase.instance.client;
  final _uuid = const Uuid();

  String? _apiKey;
  String? _secretKey;
  String _baseUrl = _defaultBaseUrl;
  bool _configLoaded = false;

  // ============================================================
  // Configuration
  // ============================================================

  /// Charge la config depuis Supabase (table app_settings, clé kpay_config)
  Future<bool> loadConfig() async {
    if (_configLoaded) return true;
    try {
      final res = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'kpay_config')
          .maybeSingle();

      if (res == null || res['value'] == null) {
        _log.error('loadConfig', 'No K-Pay config found in app_settings', null);
        return false;
      }

      final config = res['value'] as Map<String, dynamic>;

      final isActive = config['active'] as bool? ?? false;
      if (!isActive) {
        _log.warn('K-Pay service is disabled in config');
        return false;
      }

      _apiKey = config['apiKey'] as String?;
      _secretKey = config['secretKey'] as String?;
      _baseUrl = (config['baseUrl'] as String?)?.trim().isNotEmpty == true
          ? (config['baseUrl'] as String).trim()
          : _defaultBaseUrl;

      if (_apiKey == null || _secretKey == null) {
        _log.error('loadConfig', 'Missing apiKey or secretKey', null);
        return false;
      }

      _configLoaded = true;
      _log.info('K-Pay config loaded successfully');
      return true;
    } catch (e, s) {
      _log.error('loadConfig', e, s);
      return false;
    }
  }

  Map<String, String> _authHeaders() => {
        'Content-Type': 'application/json',
        'X-API-Key': _apiKey ?? '',
        'X-Secret-Key': _secretKey ?? '',
      };

  /// Mappe un statut K-Pay (PENDING/PROCESSING/COMPLETED/FAILED/CANCELLED)
  /// vers nos 3 etats internes (PENDING/SUCCESS/FAILED).
  String _mapStatus(String raw) {
    final s = raw.toUpperCase();
    if (s == 'COMPLETED' || s == 'SUCCESS') return 'SUCCESS';
    if (s == 'FAILED' || s == 'CANCELLED' || s == 'EXPIRED' || s == 'REJECTED') {
      return 'FAILED';
    }
    return 'PENDING';
  }

  // ============================================================
  // DEPOSIT – Dépôt d'argent (Mobile Money → Coins)
  // ============================================================

  /// Initie un dépôt via K-Pay.
  /// [payer] : numéro au format 237XXXXXXXXX
  /// [amount] : montant en FCFA (1:1)
  Future<Map<String, dynamic>> initiateDeposit({
    required String payer,
    required int amount,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return {'success': false, 'message': 'Vous devez être connecté.'};
    }

    // WEB : Edge Function (proxy serveur, evite CORS)
    if (kIsWeb) {
      try {
        final res = await _client.functions.invoke(
          'kpay_initiate_deposit',
          body: {'amount': amount, 'payer': payer},
        );
        final data = res.data;
        if (data is Map) return Map<String, dynamic>.from(data);
        return {'success': false, 'message': 'Reponse serveur invalide.'};
      } catch (e, s) {
        _log.error('initiateDeposit (web edge function)', e, s);
        return {
          'success': false,
          'message': 'Erreur reseau. Verifiez votre connexion.',
        };
      }
    }

    // MOBILE : appel direct K-Pay
    if (!await loadConfig()) {
      return {
        'success': false,
        'message': 'Configuration K-Pay manquante. Contactez le support.',
      };
    }

    final externalId = 'DEPOSIT_${_uuid.v4().substring(0, 8)}_$uid';

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/v1/payments/init'),
            headers: _authHeaders(),
            body: jsonEncode({
              'amount': amount,
              'phoneNumber': payer,
              'externalId': externalId,
              'description': 'Dépôt de $amount FCFA',
            }),
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final kId = (data['id'] as String?) ?? '';
      final kStatus = (data['status'] as String? ?? '').toUpperCase();
      final accepted = (response.statusCode == 200 ||
              response.statusCode == 201) &&
          kId.isNotEmpty &&
          !['FAILED', 'CANCELLED', 'REJECTED'].contains(kStatus);

      if (accepted) {
        await _client.from('kpay_transactions').insert({
          'user_id': uid,
          'reference': kId,
          'external_id': externalId,
          'transaction_type': 'DEPOSIT',
          'amount': amount,
          'status': 'PENDING',
          'phone': payer,
          'message': data['message'] ?? 'Paiement initié',
        });

        return {
          'success': true,
          'reference': kId,
          'externalId': externalId,
          'message':
              'Transaction initiée. Validez le paiement sur votre téléphone.',
        };
      } else {
        _log.warn('initiateDeposit failed: $data');
        return {
          'success': false,
          'message': data['message'] ??
              data['error'] ??
              'Erreur lors de l\'initialisation du paiement.',
        };
      }
    } catch (e, s) {
      _log.error('initiateDeposit', e, s);
      return {
        'success': false,
        'message': 'Erreur réseau. Vérifiez votre connexion.',
      };
    }
  }

  // ============================================================
  // WITHDRAW – Retrait d'argent (Coins → Mobile Money)
  // ============================================================

  /// Initie un retrait via K-Pay.
  /// [receiver] : numéro au format 237XXXXXXXXX
  /// [amount] : montant en FCFA (1:1)
  Future<Map<String, dynamic>> initiateWithdrawal({
    required String receiver,
    required int amount,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return {'success': false, 'message': 'Vous devez être connecté.'};
    }

    // K-Pay refuse les retraits < 100 F (HTTP 400). On bloque ici, avant
    // tout débit du wallet ou appel réseau, avec un message clair.
    if (amount < minWithdrawalAmount) {
      return {
        'success': false,
        'message':
            'Le montant minimum de retrait est de $minWithdrawalAmount FCFA.',
      };
    }

    if (!kIsWeb && !await loadConfig()) {
      return {
        'success': false,
        'message': 'Configuration K-Pay manquante. Contactez le support.',
      };
    }

    // Verification anti-fraude + limites de retrait (optionnel)
    try {
      final check = await _client.rpc('check_withdrawal_allowed', params: {
        'p_amount': amount,
      });
      if (check is Map && check['allowed'] != true) {
        return {
          'success': false,
          'message': check['reason'] as String? ?? 'Retrait non autorisé',
          'kyc_required': check['kyc_required'] == true,
        };
      }
    } catch (_) {
      // RPC absente -> pas de blocage (compat descendante)
    }

    final externalId = 'WITHDRAW_${_uuid.v4().substring(0, 8)}_$uid';

    // 1. DEBIT WALLET via ledger V2 (atomique + idempotent)
    final debitRes = await _client.rpc('kpay_debit_for_withdrawal', params: {
      'p_amount': amount,
      'p_external_id': externalId,
    });
    if (debitRes is! Map || debitRes['success'] != true) {
      final err = (debitRes is Map ? debitRes['error'] : null) ?? 'DEBIT_FAILED';
      if (err == 'INSUFFICIENT_FUNDS') {
        final bal = (debitRes is Map ? debitRes['balance'] : null) ?? 0;
        return {
          'success': false,
          'message': 'Solde insuffisant (vous avez $bal FCFA).',
        };
      }
      _log.warn('Debit ledger refused: $err');
      return {'success': false, 'message': 'Erreur debit solde: $err'};
    }

    // 2. APPEL K-Pay
    if (kIsWeb) {
      try {
        final res = await _client.functions.invoke(
          'kpay_initiate_withdrawal',
          body: {
            'amount': amount,
            'receiver': receiver,
            'externalId': externalId,
          },
        );
        final data = res.data;
        if (data is Map && data['success'] == true) {
          return Map<String, dynamic>.from(data);
        }
        final msg = (data is Map ? data['message'] : null) as String? ??
            'Erreur lors de l\'initialisation du retrait. Solde restauré.';
        _log.warn('initiateWithdrawal (web) refused: $data');
        await _refundWithdrawal(amount, externalId, 'kpay_init_failed_web');
        return {'success': false, 'message': msg};
      } catch (e, s) {
        _log.error('initiateWithdrawal (web edge function)', e, s);
        await _refundWithdrawal(amount, externalId, 'network_error_web');
        return {
          'success': false,
          'message': 'Erreur reseau. Solde restaure, reessayez plus tard.',
        };
      }
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/v1/payments/withdraw'),
            headers: _authHeaders(),
            body: jsonEncode({
              'amount': amount,
              'phoneNumber': receiver,
              'description': 'Retrait de $amount FCFA',
            }),
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final kId = (data['id'] as String?) ?? '';
      final kStatus = (data['status'] as String? ?? '').toUpperCase();
      final accepted = (response.statusCode == 200 ||
              response.statusCode == 201) &&
          kId.isNotEmpty &&
          !['FAILED', 'CANCELLED', 'REJECTED'].contains(kStatus);

      if (accepted) {
        await _client.from('kpay_transactions').insert({
          'user_id': uid,
          'reference': kId,
          'external_id': externalId,
          'transaction_type': 'WITHDRAW',
          'amount': amount,
          'status': 'PENDING',
          'phone': receiver,
          'message': data['message'] ?? 'Retrait initié',
        });

        return {
          'success': true,
          'reference': kId,
          'externalId': externalId,
          'message': 'Retrait en cours. Vous recevrez l\'argent sous peu.',
        };
      } else {
        // ECHEC K-Pay -> REFUND auto
        _log.warn('initiateWithdrawal K-Pay failed: $data');
        await _refundWithdrawal(amount, externalId, 'kpay_init_failed');
        return {
          'success': false,
          'message': data['message'] ??
              data['error'] ??
              'Erreur lors de l\'initialisation du retrait. Solde restauré.',
        };
      }
    } catch (e, s) {
      _log.error('initiateWithdrawal', e, s);
      await _refundWithdrawal(amount, externalId, 'network_error');
      return {
        'success': false,
        'message': 'Erreur réseau. Solde restauré, réessayez plus tard.',
      };
    }
  }

  /// Refund interne si l'init K-Pay echoue apres le debit.
  Future<void> _refundWithdrawal(
      int amount, String externalId, String reason) async {
    try {
      await _client.rpc('kpay_refund_withdrawal', params: {
        'p_amount': amount,
        'p_external_id': externalId,
        'p_reason': reason,
      });
    } catch (e) {
      _log.error('refundWithdrawal', e, null);
      // Si meme le refund plante, le cron prendra le relai
    }
  }

  // ============================================================
  // STATUS – Récupérer le statut d'une transaction
  // ============================================================

  /// Vérifie si une transaction a déjà été créditée/refundée (anti-doublon).
  Future<bool> isAlreadyCredited(String reference) async {
    try {
      final r = await _client
          .rpc('is_kpay_credited', params: {'p_reference': reference});
      return r == true;
    } catch (e) {
      _log.warn('isAlreadyCredited check failed: $e');
      return false;
    }
  }

  /// Récupère le statut courant d'une transaction K-Pay via l'API.
  /// [transactionType] : 'DEPOSIT' ou 'WITHDRAW' (endpoint différent).
  /// Retourne un map { 'status': PENDING|SUCCESS|FAILED, 'raw', 'reason' }.
  Future<Map<String, dynamic>?> getTransactionStatus(
    String reference, {
    required String transactionType,
  }) async {
    if (!await loadConfig()) return null;

    final path = transactionType == 'WITHDRAW'
        ? '/api/v1/payments/withdraw/$reference'
        : '/api/v1/payments/$reference';

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl$path'), headers: _authHeaders())
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (body['data'] is Map)
            ? body['data'] as Map<String, dynamic>
            : body;
        final raw = (data['status'] as String? ?? '').toUpperCase();
        return {
          'status': _mapStatus(raw),
          'raw': raw,
          'reason': data['failureReason'] ?? data['message'] ?? '',
        };
      } else {
        _log.warn('getTransactionStatus failed: ${response.body}');
        return null;
      }
    } catch (e, s) {
      _log.error('getTransactionStatus', e, s);
      return null;
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Récupère les transactions K-Pay de l'utilisateur courant.
  Future<List<Map<String, dynamic>>> getMyTransactions() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];

    try {
      final res = await _client
          .from('kpay_transactions')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(50);
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e, s) {
      _log.error('getMyTransactions', e, s);
      return [];
    }
  }

  /// Met à jour le statut d'une transaction (appelé par le polling client).
  Future<void> updateTransactionStatus({
    required String reference,
    required String status,
    String? message,
    Map<String, dynamic>? callbackData,
  }) async {
    try {
      await _client.from('kpay_transactions').update({
        'status': status,
        if (message != null) 'message': message,
        if (callbackData != null) 'callback_data': callbackData,
      }).eq('reference', reference);
    } catch (e, s) {
      _log.error('updateTransactionStatus', e, s);
    }
  }

  /// Normalise un numéro -> '237XXXXXXXXX'.
  String normalizePhoneNumber(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('237')) return digits;
    if (digits.startsWith('0') && digits.length >= 10) {
      digits = digits.substring(1);
    }
    return '237$digits';
  }

  /// Valide le format après normalisation : 237 + 9 chiffres.
  bool validatePhoneNumber(String phone) {
    final n = normalizePhoneNumber(phone);
    return RegExp(r'^237[0-9]{9}$').hasMatch(n);
  }

  /// Alias de normalizePhoneNumber.
  String cleanPhoneNumber(String phone) => normalizePhoneNumber(phone);
}

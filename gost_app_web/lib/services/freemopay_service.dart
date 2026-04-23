// ============================================================
// FreemopayService – Gestion des paiements via Freemopay API v2
// ============================================================
// API Base URL: https://api-v2.freemopay.com/api/v2
//
// Flux:
// 1. DEPOSIT: initier paiement → user valide sur téléphone → webhook callback → créditer wallet
// 2. WITHDRAW: débiter wallet → initier retrait → webhook callback → finaliser
//
// Auth: Basic Auth (appKey:secretKey) en base64
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../utils/logger.dart';

class FreemopayService {
  static const _log = Logger('FREEMOPAY');
  static const _baseUrl = 'https://api-v2.freemopay.com/api/v2';
  final _client = Supabase.instance.client;
  final _uuid = const Uuid();

  String? _appKey;
  String? _secretKey;
  String? _webhookUrl;
  bool _configLoaded = false;

  // ============================================================
  // Configuration
  // ============================================================

  /// Charge la config depuis Supabase (table app_settings, clé freemopay_config)
  Future<bool> loadConfig() async {
    if (_configLoaded) return true;
    try {
      final res = await _client
          .from('app_settings')
          .select('value')
          .eq('key', 'freemopay_config')
          .maybeSingle();

      if (res == null || res['value'] == null) {
        _log.error('loadConfig', 'No Freemopay config found in app_settings', null);
        return false;
      }

      final config = res['value'] as Map<String, dynamic>;

      // Vérifier si le service est actif
      final isActive = config['active'] as bool? ?? false;
      if (!isActive) {
        _log.warn('Freemopay service is disabled in config');
        return false;
      }

      _appKey = config['appKey'] as String?;
      _secretKey = config['secretKey'] as String?;
      _webhookUrl = config['callbackUrl'] as String?;

      if (_appKey == null || _secretKey == null) {
        _log.error('loadConfig', 'Missing appKey or secretKey', null);
        return false;
      }

      _configLoaded = true;
      _log.info('Freemopay config loaded successfully');
      return true;
    } catch (e, s) {
      _log.error('loadConfig', e, s);
      return false;
    }
  }

  /// Génère le header Basic Auth
  String _basicAuthHeader() {
    final credentials = '$_appKey:$_secretKey';
    final encoded = base64Encode(utf8.encode(credentials));
    return 'Basic $encoded';
  }

  // ============================================================
  // DEPOSIT – Dépôt d'argent (Mobile Money → Coins)
  // ============================================================

  /// Initie un dépôt via Freemopay
  ///
  /// [payer] : Numéro de téléphone au format international (ex: 237658895572)
  /// [amount] : Montant en FCFA (= FCFA)
  ///
  /// Retourne un Map avec:
  /// - 'success': bool
  /// - 'reference': String? (référence Freemopay)
  /// - 'message': String (message utilisateur)
  /// - 'externalId': String? (notre ID interne)
  Future<Map<String, dynamic>> initiateDeposit({
    required String payer,
    required int amount,
  }) async {
    if (!await loadConfig()) {
      return {
        'success': false,
        'message': 'Configuration Freemopay manquante. Contactez le support.',
      };
    }

    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return {'success': false, 'message': 'Vous devez être connecté.'};
    }

    // Générer un ID unique pour cette transaction
    final externalId = 'DEPOSIT_${_uuid.v4().substring(0, 8)}_$uid';

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/payment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _basicAuthHeader(),
        },
        body: jsonEncode({
          'payer': payer,
          'amount': amount.toString(),
          'externalId': externalId,
          'description': 'Dépôt de $amount FCFA',
          'callback': _webhookUrl ?? '',
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 &&
          (data['status'] == 'SUCCESS' || data['status'] == 'CREATED')) {
        final reference = data['reference'] as String;

        // Enregistrer dans freemopay_transactions
        await _client.from('freemopay_transactions').insert({
          'user_id': uid,
          'reference': reference,
          'external_id': externalId,
          'transaction_type': 'DEPOSIT',
          'amount': amount,
          'status': 'PENDING',
          'payer_or_receiver': payer,
          'message': data['message'] ?? 'Paiement initié',
        });

        return {
          'success': true,
          'reference': reference,
          'externalId': externalId,
          'message':
              'Transaction initiée. Validez le paiement sur votre téléphone.',
        };
      } else {
        _log.warn('initiateDeposit failed: ${data}');
        return {
          'success': false,
          'message': data['message']?['fr'] ?? data['message'] ??
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

  /// Initie un retrait via Freemopay
  ///
  /// [receiver] : Numéro de téléphone au format international
  /// [amount] : Montant en FCFA (= FCFA)
  ///
  /// Retourne un Map avec:
  /// - 'success': bool
  /// - 'reference': String?
  /// - 'message': String
  /// - 'externalId': String?
  Future<Map<String, dynamic>> initiateWithdrawal({
    required String receiver,
    required int amount,
  }) async {
    if (!await loadConfig()) {
      return {
        'success': false,
        'message': 'Configuration Freemopay manquante. Contactez le support.',
      };
    }

    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return {'success': false, 'message': 'Vous devez être connecté.'};
    }

    // Verification anti-fraude + limites de retrait
    try {
      final check = await _client.rpc('check_withdrawal_allowed', params: {
        'p_amount': amount,
      });
      if (check is Map) {
        if (check['allowed'] != true) {
          return {
            'success': false,
            'message': check['reason'] as String? ?? 'Retrait non autorisé',
            'kyc_required': check['kyc_required'] == true,
          };
        }
        // Si review manuelle requise, informer le joueur
        if (check['review_needed'] == true) {
          // On continue mais on pourrait demander confirmation UI
        }
      }
    } catch (e) {
      // Si la RPC n'existe pas encore (migration pas faite), on continue
      // Pas de blocage pour compat descendante
    }

    final externalId = 'WITHDRAW_${_uuid.v4().substring(0, 8)}_$uid';

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/payment/direct-withdraw'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _basicAuthHeader(),
        },
        body: jsonEncode({
          'receiver': receiver,
          'amount': amount.toString(),
          'externalId': externalId,
          'callback': _webhookUrl ?? '',
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 &&
          (data['status'] == 'CREATED' || data['status'] == 'SUCCESS')) {
        final reference = data['reference'] as String;

        // Enregistrer dans freemopay_transactions
        await _client.from('freemopay_transactions').insert({
          'user_id': uid,
          'reference': reference,
          'external_id': externalId,
          'transaction_type': 'WITHDRAW',
          'amount': amount,
          'status': 'PENDING',
          'payer_or_receiver': receiver,
          'message': data['message'] ?? 'Retrait initié',
        });

        return {
          'success': true,
          'reference': reference,
          'externalId': externalId,
          'message': 'Retrait en cours. Vous recevrez l\'argent sous peu.',
        };
      } else {
        _log.warn('initiateWithdrawal failed: ${data}');
        return {
          'success': false,
          'message': data['message']?['fr'] ?? data['message'] ??
              'Erreur lors de l\'initialisation du retrait.',
        };
      }
    } catch (e, s) {
      _log.error('initiateWithdrawal', e, s);
      return {
        'success': false,
        'message': 'Erreur réseau. Vérifiez votre connexion.',
      };
    }
  }

  // ============================================================
  // STATUS – Récupérer le statut d'une transaction
  // ============================================================

  /// Récupère le statut d'une transaction Freemopay
  /// Utile pour le polling manuel si pas de webhook
  Future<Map<String, dynamic>?> getTransactionStatus(String reference) async {
    if (!await loadConfig()) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/payment/$reference'),
        headers: {
          'Authorization': _basicAuthHeader(),
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
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

  /// Récupère les transactions Freemopay de l'utilisateur courant
  Future<List<Map<String, dynamic>>> getMyTransactions() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];

    try {
      final res = await _client
          .from('freemopay_transactions')
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

  /// Met à jour le statut d'une transaction (appelé par webhook ou polling)
  Future<void> updateTransactionStatus({
    required String reference,
    required String status,
    String? message,
    Map<String, dynamic>? callbackData,
  }) async {
    try {
      await _client.from('freemopay_transactions').update({
        'status': status,
        if (message != null) 'message': message,
        if (callbackData != null) 'callback_data': callbackData,
      }).eq('reference', reference);
    } catch (e, s) {
      _log.error('updateTransactionStatus', e, s);
    }
  }

  /// Valide le format d'un numéro de téléphone (Cameroun/international)
  /// Format attendu: 237XXXXXXXXX (9 chiffres après 237)
  bool validatePhoneNumber(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Accepte: 237XXXXXXXXX ou +237XXXXXXXXX
    final pattern = RegExp(r'^\+?237[0-9]{9}$');
    return pattern.hasMatch(cleaned);
  }

  /// Nettoie un numéro de téléphone pour l'API
  String cleanPhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
  }
}

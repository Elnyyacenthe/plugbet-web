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
import 'package:flutter/foundation.dart' show kIsWeb;
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
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return {'success': false, 'message': 'Vous devez être connecté.'};
    }

    // ============================================================
    // WEB : passe par l'Edge Function (proxy serveur) pour eviter
    // les blocages CORS. Sur mobile (natif), on reste sur l'appel direct.
    // ============================================================
    if (kIsWeb) {
      try {
        final res = await _client.functions.invoke(
          'freemopay_initiate_deposit',
          body: {'amount': amount, 'payer': payer},
        );
        final data = res.data;
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
        return {'success': false, 'message': 'Reponse serveur invalide.'};
      } catch (e, s) {
        _log.error('initiateDeposit (web edge function)', e, s);
        return {
          'success': false,
          'message': 'Erreur reseau. Verifiez votre connexion.',
        };
      }
    }

    // ============================================================
    // MOBILE : appel direct FreemoPay (pas de CORS)
    // ============================================================
    if (!await loadConfig()) {
      return {
        'success': false,
        'message': 'Configuration Freemopay manquante. Contactez le support.',
      };
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
      ).timeout(const Duration(seconds: 20));

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
        _log.warn('initiateDeposit failed: $data');
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
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      return {'success': false, 'message': 'Vous devez être connecté.'};
    }

    // Sur mobile : besoin de loadConfig pour le POST direct
    // Sur web : pas besoin, l'Edge Function lit la config server-side
    if (!kIsWeb && !await loadConfig()) {
      return {
        'success': false,
        'message': 'Configuration Freemopay manquante. Contactez le support.',
      };
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

    // 1. DEBIT WALLET via ledger V2 (atomique + idempotent)
    // Avant tout appel Freemopay, on debite le solde via la RPC ledger.
    // Si solde insuffisant -> rejet immediat, pas d'appel Freemopay.
    final debitRes = await _client.rpc('freemopay_debit_for_withdrawal', params: {
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

    // 2. APPEL FREEMOPAY
    // Sur web : passe par l'Edge Function (CORS)
    // Sur mobile : POST direct
    if (kIsWeb) {
      try {
        final res = await _client.functions.invoke(
          'freemopay_initiate_withdrawal',
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
        // Echec serveur -> refund
        final msg = (data is Map ? data['message'] : null) as String? ??
            'Erreur lors de l\'initialisation du retrait. Solde restauré.';
        _log.warn('initiateWithdrawal (web) refused: $data');
        await _refundWithdrawal(amount, externalId, 'freemopay_init_failed_web');
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
      ).timeout(const Duration(seconds: 20));

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
        // 3. ECHEC FREEMOPAY -> REFUND auto
        _log.warn('initiateWithdrawal Freemopay failed: $data');
        await _refundWithdrawal(amount, externalId, 'freemopay_init_failed');
        return {
          'success': false,
          'message': data['message']?['fr'] ?? data['message'] ??
              'Erreur lors de l\'initialisation du retrait. Solde restauré.',
        };
      }
    } catch (e, s) {
      // 3bis. ERREUR RESEAU/TIMEOUT -> REFUND auto
      _log.error('initiateWithdrawal', e, s);
      await _refundWithdrawal(amount, externalId, 'network_error');
      return {
        'success': false,
        'message': 'Erreur réseau. Solde restauré, réessayez plus tard.',
      };
    }
  }

  /// Refund interne si l'init Freemopay echoue apres le debit.
  Future<void> _refundWithdrawal(int amount, String externalId, String reason) async {
    try {
      await _client.rpc('freemopay_refund_withdrawal', params: {
        'p_amount': amount,
        'p_external_id': externalId,
        'p_reason': reason,
      });
    } catch (e) {
      _log.error('refundWithdrawal', e, null);
      // Si meme le refund plante, on log et le cron prendra le relai
    }
  }

  // ============================================================
  // STATUS – Récupérer le statut d'une transaction
  // ============================================================

  /// Verifie si une transaction a deja ete creditee (anti-double-credit).
  /// Le webhook ou le cron reconcile peuvent avoir credite avant que le
  /// polling client n'arrive. On evite le doublon.
  Future<bool> isAlreadyCredited(String reference) async {
    try {
      final r = await _client.rpc('is_freemopay_credited',
          params: {'p_reference': reference});
      return r == true;
    } catch (e) {
      _log.warn('isAlreadyCredited check failed: $e');
      return false;  // En cas d'erreur, on laisse passer (fallback safe)
    }
  }

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

  /// Normalise un numero de telephone en format API (sans +, sans espace,
  /// avec prefixe 237 auto-ajoute si absent).
  ///
  /// Accepte tous ces formats et retourne '237XXXXXXXXX' :
  ///   - '699123456'       -> '237699123456'
  ///   - '237699123456'    -> '237699123456'
  ///   - '+237 699 123 456' -> '237699123456'
  ///   - '00237699123456'  -> '237699123456'
  String normalizePhoneNumber(String phone) {
    // 1. Retire tout ce qui n'est pas chiffre
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    // 2. Retire prefixe international 00 si present
    if (digits.startsWith('00')) digits = digits.substring(2);
    // 3. Si commence deja par 237 -> garder
    if (digits.startsWith('237')) return digits;
    // 4. Si commence par 0 (format local francais 0691... -> 691...) retire le 0
    if (digits.startsWith('0') && digits.length >= 10) {
      digits = digits.substring(1);
    }
    // 5. Prepend 237
    return '237$digits';
  }

  /// Valide le format d'un numéro de téléphone après normalisation.
  /// Format attendu: 237XXXXXXXXX (9 chiffres après le préfixe)
  bool validatePhoneNumber(String phone) {
    final n = normalizePhoneNumber(phone);
    return RegExp(r'^237[0-9]{9}$').hasMatch(n);
  }

  /// Nettoie un numéro de téléphone pour l'API (alias de normalizePhoneNumber).
  String cleanPhoneNumber(String phone) => normalizePhoneNumber(phone);
}

// ============================================================
// FreemopayAwaitingScreen – Page d'attente transaction Freemopay
// Poll l'API toutes les 5 secondes pour vérifier le statut
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../services/freemopay_service.dart';
import '../providers/wallet_provider.dart';
import '../utils/logger.dart';

class FreemopayAwaitingScreen extends StatefulWidget {
  final String reference;
  final String externalId;
  final String transactionType; // 'DEPOSIT' ou 'WITHDRAW'
  final int amount;
  final String phoneNumber;

  const FreemopayAwaitingScreen({
    super.key,
    required this.reference,
    required this.externalId,
    required this.transactionType,
    required this.amount,
    required this.phoneNumber,
  });

  @override
  State<FreemopayAwaitingScreen> createState() =>
      _FreemopayAwaitingScreenState();
}

class _FreemopayAwaitingScreenState extends State<FreemopayAwaitingScreen>
    with SingleTickerProviderStateMixin {
  static const _log = Logger('FREEMOPAY_AWAIT');
  final _freemopayService = FreemopayService();

  Timer? _pollingTimer;
  int _secondsElapsed = 0;
  String _status = 'PENDING';
  String _message = 'En attente de validation...';
  bool _isCompleted = false;
  bool _hasNetworkError = false;
  int _consecutiveErrors = 0;
  RealtimeChannel? _txChannel;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // 1. Realtime : push instantane des qu'un autre canal (cron/webhook) marque SUCCESS/FAILED
    _subscribeRealtime();

    // 2. Polling Flutter : fallback si realtime ne livre pas
    //    Premier check immediat, puis intervalles courts qui s'allongent
    _checkStatus();
    _scheduleNextPoll();

    // Timeout apres 5 minutes
    Future.delayed(const Duration(minutes: 5), () {
      if (!_isCompleted && mounted) {
        _handleTimeout();
      }
    });
  }

  void _subscribeRealtime() {
    try {
      _txChannel = Supabase.instance.client
          .channel('freemopay_tx_${widget.reference}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'freemopay_transactions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'reference',
              value: widget.reference,
            ),
            callback: (payload) {
              final newStatus = payload.newRecord['status'] as String? ?? '';
              if (newStatus == 'SUCCESS' && !_isCompleted) {
                _handleSuccess();
              } else if (newStatus == 'FAILED' && !_isCompleted) {
                final reason = payload.newRecord['message'] as String? ?? '';
                _handleFailure(reason);
              }
            },
          )
          .subscribe();
    } catch (e) {
      _log.warn('subscribeRealtime: $e');
    }
  }

  void _scheduleNextPoll() {
    // Backoff : 2s, 5s, 10s, puis 5s steady
    final delays = [2, 5, 10, 5, 5, 5, 5, 5];
    final idx = (_secondsElapsed / 5).floor().clamp(0, delays.length - 1);
    final next = delays[idx];
    _pollingTimer?.cancel();
    _pollingTimer = Timer(Duration(seconds: next), () {
      if (_isCompleted || !mounted) return;
      _secondsElapsed += next;
      _checkStatus();
      _scheduleNextPoll();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    if (_txChannel != null) {
      Supabase.instance.client.removeChannel(_txChannel!);
    }
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final result =
          await _freemopayService.getTransactionStatus(widget.reference);

      if (result == null || !mounted) return;

      // Réinitialiser le compteur d'erreurs en cas de succès
      _consecutiveErrors = 0;
      if (_hasNetworkError) {
        setState(() {
          _hasNetworkError = false;
        });
      }

      final status = result['status'] as String? ?? 'PENDING';
      final reason = result['reason'] as String? ?? '';

      _log.info('Transaction ${widget.reference}: $status');

      setState(() {
        _status = status;
      });

      if (status == 'SUCCESS') {
        await _handleSuccess();
      } else if (status == 'FAILED') {
        await _handleFailure(reason);
      } else if (status == 'PENDING') {
        setState(() {
          _message = 'En attente de validation sur votre téléphone...';
        });
      }
    } catch (e, s) {
      // Détection d'erreur réseau (SocketException, Connection abort, etc.)
      final isNetworkError = e.toString().contains('SocketException') ||
          e.toString().contains('connection abort') ||
          e.toString().contains('Failed host lookup');

      if (isNetworkError) {
        _consecutiveErrors++;

        if (mounted) {
          setState(() {
            _hasNetworkError = true;
            _message = 'Pas de connexion internet. Vérification en pause...';
          });
        }

        // Arrêter le polling après 3 erreurs consécutives
        if (_consecutiveErrors >= 3) {
          _log.warn('Polling stopped after 3 consecutive network errors');
          _pollingTimer?.cancel();
        }
      } else {
        // Autre type d'erreur - logger normalement
        _log.error('checkStatus', e, s);
      }
    }
  }

  Future<void> _handleSuccess() async {
    _pollingTimer?.cancel();

    // ANTI-DOUBLE-CRÉDIT : check si déjà crédité par webhook/cron avant
    final alreadyCredited = await _freemopayService.isAlreadyCredited(widget.reference);

    // ============================================================
    // 1) CRÉDIT D'ABORD (si dépôt non déjà crédité)
    // Si le crédit échoue, on NE marque PAS SUCCESS dans la DB
    // → la transaction reste PENDING → le cron reconcile la finalisera
    // ============================================================
    bool creditOk = true;
    if (widget.transactionType == 'DEPOSIT' && !alreadyCredited) {
      // V2 LEDGER : passe par freemopay_credit_deposit (atomique + idempotent)
      // au lieu de _walletService.addCoins (legacy my_wallet_apply_delta -> wallet_transactions)
      try {
        final r = await Supabase.instance.client.rpc(
          'freemopay_credit_deposit',
          params: {
            'p_amount': widget.amount,
            'p_reference': widget.reference,
            'p_external_id': widget.externalId,
          },
        );
        creditOk = r is Map && r['success'] == true;
        if (!creditOk) {
          _log.warn('freemopay_credit_deposit refused: ${r is Map ? r['error'] : r}');
        }
      } catch (e, s) {
        _log.error('freemopay_credit_deposit RPC failed', e, s);
        creditOk = false;
      }
      if (!creditOk) {
        _log.error('addCoins failed for reference=${widget.reference}, transaction stays PENDING', null, null);
        // On ne marque PAS SUCCESS dans la DB. Le cron reconcile prendra
        // le relais (transaction reste PENDING jusqu'a credit reussi).
        if (mounted) {
          setState(() {
            _isCompleted = true;
            _status = 'PENDING';
            _message = 'Paiement reçu mais crédit en cours. Réessayez plus tard.';
          });
          _animationController.stop();
        }
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) Navigator.pop(context, false);
        return;
      }
    }

    // ============================================================
    // 2) Marque SUCCESS dans la DB SEULEMENT si credit ok (ou deja credite)
    // ============================================================
    await _freemopayService.updateTransactionStatus(
      reference: widget.reference,
      status: 'SUCCESS',
      message: 'Transaction confirmée',
    );

    if (mounted) {
      setState(() {
        _isCompleted = true;
        _message = 'Transaction réussie !';
      });
      _animationController.stop();
      context.read<WalletProvider>().refresh();
    }

    // Attendre 2 secondes puis retourner au profil
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.pop(context, true); // true = succès
    }
  }

  Future<void> _handleFailure(String reason) async {
    setState(() {
      _isCompleted = true;
      _message = 'Transaction échouée: $reason';
    });
    _pollingTimer?.cancel();
    _animationController.stop();

    // ANTI-DOUBLE-REFUND : check si déjà refundé par webhook/cron
    final alreadyRefunded = await _freemopayService.isAlreadyCredited(widget.reference);

    // Mettre à jour le statut dans freemopay_transactions
    await _freemopayService.updateTransactionStatus(
      reference: widget.reference,
      status: 'FAILED',
      message: reason,
    );

    // Si c'est un retrait échoué et pas déjà refundé, re-créditer via ledger V2
    if (widget.transactionType == 'WITHDRAW' && !alreadyRefunded) {
      bool success = false;
      try {
        final r = await Supabase.instance.client.rpc(
          'freemopay_refund_withdrawal',
          params: {
            'p_amount': widget.amount,
            'p_external_id': widget.externalId,
            'p_reason': 'polling_detected_failed: $reason',
          },
        );
        success = r is Map && r['success'] == true;
      } catch (e, s) {
        _log.error('freemopay_refund_withdrawal RPC failed', e, s);
      }

      if (success && mounted) {
        context.read<WalletProvider>().refresh();
      }
    }

    // Attendre 3 secondes puis retourner au profil
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      Navigator.pop(context, false); // false = échec
    }
  }

  void _handleTimeout() {
    setState(() {
      _isCompleted = true;
      _message = 'Timeout - Vérifiez votre historique plus tard';
    });
    _pollingTimer?.cancel();
    _animationController.stop();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context, null); // null = timeout
      }
    });
  }

  /// Réessayer manuellement le polling
  void _retryPolling() {
    setState(() {
      _hasNetworkError = false;
      _consecutiveErrors = 0;
      _message = 'Vérification en cours...';
    });
    // Redemarre le polling adaptatif
    _checkStatus();
    _scheduleNextPoll();
  }


  IconData get _icon {
    if (_status == 'SUCCESS') return Icons.check_circle;
    if (_status == 'FAILED') return Icons.error;
    if (_hasNetworkError) return Icons.wifi_off;
    return Icons.access_time;
  }

  Color get _color {
    if (_status == 'SUCCESS') return AppColors.neonGreen;
    if (_status == 'FAILED') return AppColors.neonRed;
    if (_hasNetworkError) return AppColors.neonOrange;
    return AppColors.neonYellow;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isCompleted,
      child: Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgBlueNight,
          title: Text(
              widget.transactionType == 'DEPOSIT' ? 'Dépôt en cours' : 'Retrait en cours'),
          automaticallyImplyLeading: _isCompleted,
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppColors.bgGradient),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icône animée
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _color.withValues(alpha: 0.1),
                        border: Border.all(color: _color, width: 3),
                      ),
                      child: Icon(_icon, size: 60, color: _color),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Montant
                  Text(
                    '${widget.amount} FCFA',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Type de transaction
                  Text(
                    widget.transactionType == 'DEPOSIT'
                        ? 'Dépôt Mobile Money'
                        : 'Retrait Mobile Money',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Message de statut
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppColors.cardGradient,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.divider.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!_isCompleted && _status == 'PENDING') ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: _color,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Vérification en cours... ($_secondsElapsed s)',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Numéro
                  Text(
                    widget.phoneNumber,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Référence
                  Text(
                    'Réf: ${widget.reference.substring(0, 8)}...',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),

                  if (_status == 'PENDING' && !_isCompleted) ...[
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _hasNetworkError
                            ? AppColors.neonOrange.withValues(alpha: 0.1)
                            : AppColors.neonBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _hasNetworkError
                                ? AppColors.neonOrange.withValues(alpha: 0.3)
                                : AppColors.neonBlue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              _hasNetworkError
                                  ? Icons.wifi_off
                                  : Icons.info_outline,
                              color: _hasNetworkError
                                  ? AppColors.neonOrange
                                  : AppColors.neonBlue,
                              size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _hasNetworkError
                                  ? 'Pas de connexion internet. Connectez-vous et réessayez.'
                                  : (widget.transactionType == 'DEPOSIT'
                                      ? 'Vous allez recevoir un prompt de paiement sur votre téléphone. Composez votre code PIN pour valider.'
                                      : 'Votre retrait est en cours de traitement. Vous recevrez l\'argent sous peu.'),
                              style: TextStyle(
                                color: _hasNetworkError
                                    ? AppColors.neonOrange
                                    : AppColors.neonBlue,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bouton de retry si erreur réseau
                    if (_hasNetworkError) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _retryPolling,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Réessayer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              AppColors.neonOrange.withValues(alpha: 0.2),
                          foregroundColor: AppColors.neonOrange,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: AppColors.neonOrange, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

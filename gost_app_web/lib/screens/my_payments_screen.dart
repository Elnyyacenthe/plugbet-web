// ============================================================
// Mes paiements — Historique Mobile Money pour le user
// ============================================================
// Affiche toutes les transactions K-Pay du user avec :
//   - Statut clair en français
//   - Bouton "Vérifier maintenant" (force reconcile)
//   - Bouton "Contacter support" si PENDING > 1h
//   - Realtime auto-refresh
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

class MyPaymentsScreen extends StatefulWidget {
  const MyPaymentsScreen({super.key});

  @override
  State<MyPaymentsScreen> createState() => _MyPaymentsScreenState();
}

class _MyPaymentsScreenState extends State<MyPaymentsScreen> {
  final _client = Supabase.instance.client;
  List<_PaymentRow> _rows = [];
  bool _loading = true;
  bool _checking = false;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _client
          .from('my_kpay_transactions_v')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() {
          _rows = (data as List).map((j) => _PaymentRow.fromJson(j as Map<String, dynamic>)).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Impossible de charger l\'historique.';
          _loading = false;
        });
      }
    }
  }

  void _subscribe() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    _channel = _client
        .channel('my-kpay-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kpay_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  Future<void> _checkPending() async {
    setState(() => _checking = true);
    try {
      final r = await _client.rpc('user_check_my_pending_kpay');
      if (mounted && r is Map) {
        final msg = r['message'] as String? ?? 'Vérification effectuée';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.neonGreen,
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        final friendly = msg.contains('RATE_LIMIT')
            ? 'Patiente 30 secondes avant de réessayer.'
            : 'Erreur lors de la vérification. Réessaie dans quelques minutes.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendly),
          backgroundColor: AppColors.neonRed,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        _load();
      }
    }
  }

  void _contactSupport(_PaymentRow row) {
    Navigator.pushNamed(
      context,
      '/support',
      arguments: {
        'preset_subject': 'Transaction ${row.transactionType == 'DEPOSIT' ? 'Dépôt' : 'Retrait'} ${row.amount} FCFA',
        'preset_message':
            'Bonjour,\nMa transaction ${row.transactionType} de ${row.amount} FCFA n\'a pas abouti.\n\n'
            'Référence : ${row.reference}\n'
            'Téléphone : ${row.phone}\n'
            'Date : ${DateFormat('dd/MM/yyyy HH:mm').format(row.createdAt)}\n\n'
            'Pouvez-vous vérifier ?',
        'preset_category': 'paiement',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        title: const Text('Mes paiements'),
        actions: [
          IconButton(
            icon: _checking
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.search),
            tooltip: 'Vérifier maintenant',
            onPressed: _checking ? null : _checkPending,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: AppColors.neonRed, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
                    ],
                  ),
                )
              : _rows.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _buildRow(_rows[i]),
                      ),
                    ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
               size: 56, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'Aucun paiement',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Tes dépôts et retraits Mobile Money apparaîtront ici.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(_PaymentRow row) {
    final isDeposit = row.transactionType == 'DEPOSIT';
    final color = _statusColor(row.status);
    final ageMin = DateTime.now().difference(row.createdAt).inMinutes;
    final showSupport = row.status == 'PENDING' && ageMin >= 60;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDeposit ? Icons.arrow_downward : Icons.arrow_upward,
                color: isDeposit ? AppColors.neonGreen : AppColors.neonOrange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                isDeposit ? 'Dépôt' : 'Retrait',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${isDeposit ? '+' : '-'} ${row.amount} FCFA',
                style: TextStyle(
                  color: isDeposit ? AppColors.neonGreen : AppColors.neonOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  row.statusLabel,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                row.phone,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              Text(
                DateFormat('dd/MM HH:mm').format(row.createdAt),
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          if (row.reference.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Réf : ${row.reference.substring(0, row.reference.length > 12 ? 12 : row.reference.length)}...',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          if (showSupport) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _contactSupport(row),
                icon: const Icon(Icons.support_agent, size: 16),
                label: const Text('Contacter le support'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.neonYellow,
                  side: BorderSide(color: AppColors.neonYellow.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'SUCCESS': return AppColors.neonGreen;
      case 'FAILED':  return AppColors.neonRed;
      case 'PENDING': return AppColors.neonYellow;
      default:        return AppColors.textSecondary;
    }
  }
}

class _PaymentRow {
  final String id;
  final String reference;
  final String externalId;
  final String transactionType;
  final int amount;
  final String status;
  final String statusLabel;
  final String phone;
  final DateTime createdAt;

  _PaymentRow({
    required this.id,
    required this.reference,
    required this.externalId,
    required this.transactionType,
    required this.amount,
    required this.status,
    required this.statusLabel,
    required this.phone,
    required this.createdAt,
  });

  factory _PaymentRow.fromJson(Map<String, dynamic> j) => _PaymentRow(
    id: j['id'] as String? ?? '',
    reference: j['reference'] as String? ?? '',
    externalId: j['external_id'] as String? ?? '',
    transactionType: j['transaction_type'] as String? ?? 'DEPOSIT',
    amount: (j['amount'] as num?)?.toInt() ?? 0,
    status: j['status'] as String? ?? 'PENDING',
    statusLabel: j['status_label'] as String? ?? 'En cours',
    phone: j['phone'] as String? ?? '',
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

// ============================================================
// WalletProvider – Solde global accessible depuis toute l'app
// ============================================================
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier with WidgetsBindingObserver {
  final WalletService _service = WalletService();
  final SupabaseClient _client = Supabase.instance.client;

  int _coins = 0;
  String _username = '';
  bool _loading = false;

  RealtimeChannel? _channel;
  RealtimeChannel? _kpayChannel;

  int get coins => _coins;
  String get username => _username;
  bool get loading => _loading;

  WalletProvider() {
    _init();
  }

  Future<void> _init() async {
    WidgetsBinding.instance.addObserver(this);
    await refresh();
    _subscribeRealtime();
    _subscribeKpayRealtime();
  }

  /// Au retour de l'app (resume) : re-fetch le solde + re-abonnement
  /// realtime. Couvre le cas où un crédit/refund serveur (webhook, cron,
  /// watcher) a eu lieu pendant que l'app était fermée/en arrière-plan
  /// (la socket realtime ne rejoue pas les events manqués).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      if (_channel == null) {
        _subscribeRealtime();
      }
      if (_kpayChannel == null) {
        _subscribeKpayRealtime();
      }
    }
  }

  /// notifyListeners safe — si on est en plein build, differe au prochain frame
  void _safeNotify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  /// Recharge le solde depuis Supabase.
  /// Source primaire : RPC `wallet_balance` (lit wallet_ledger = source de
  /// verite V2). Fallback : user_profiles.coins.
  /// Le username vient toujours de user_profiles.
  Future<void> refresh() async {
    _loading = true;
    _safeNotify();
    int? ledgerBalance;
    try {
      final r = await _client.rpc('wallet_balance');
      if (r is int) {
        ledgerBalance = r;
      } else if (r is num) {
        ledgerBalance = r.toInt();
      }
    } catch (_) {/* fallback user_profiles ci-dessous */}
    final profile = await _service.getProfile();
    _coins = ledgerBalance ?? (profile?['coins'] as int? ?? 0);
    _username = profile?['username'] as String? ?? '';
    _loading = false;
    _safeNotify();
  }

  /// Met à jour le solde local directement (après débit/crédit connu)
  void updateLocal(int newCoins) {
    _coins = newCoins;
    _safeNotify();
  }

  /// Abonnement temps réel sur la table profiles
  void _subscribeRealtime() {
    final uid = _service.currentUserId;
    if (uid == null) return;
    _channel = _client
        .channel('wallet_profile_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'user_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            _coins = rec['coins'] as int? ?? _coins;
            _username = rec['username'] as String? ?? _username;
            notifyListeners();
          },
        )
        .subscribe();
  }

  /// Abonnement realtime sur kpay_transactions du user : des qu'un depot
  /// passe PENDING -> SUCCESS (ou retrait -> FAILED + refund), on
  /// rafraichit le solde. Couvre le cas ou le user_profiles UPDATE est
  /// rate (socket realtime tombee pendant l'attente du paiement).
  void _subscribeKpayRealtime() {
    final uid = _service.currentUserId;
    if (uid == null) return;
    _kpayChannel = _client
        .channel('wallet_kpay_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'kpay_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            // Toute transition hors PENDING => le solde a peut-etre change
            if (newStatus != null && newStatus != 'PENDING') {
              refresh();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_channel != null) {
      _client.removeChannel(_channel!);
    }
    if (_kpayChannel != null) {
      _client.removeChannel(_kpayChannel!);
    }
    super.dispose();
  }
}

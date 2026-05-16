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

  /// Recharge le solde depuis Supabase
  Future<void> refresh() async {
    _loading = true;
    _safeNotify();
    final profile = await _service.getProfile();
    _coins = profile?['coins'] as int? ?? 0;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_channel != null) {
      _client.removeChannel(_channel!);
    }
    super.dispose();
  }
}

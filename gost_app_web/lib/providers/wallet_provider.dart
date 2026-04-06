// ============================================================
// WalletProvider – Solde global accessible depuis toute l'app
// ============================================================
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier {
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
    await refresh();
    _subscribeRealtime();
  }

  /// Recharge le solde depuis Supabase
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    final profile = await _service.getProfile();
    _coins = profile?['coins'] as int? ?? 0;
    _username = profile?['username'] as String? ?? '';
    _loading = false;
    notifyListeners();
  }

  /// Met à jour le solde local directement (après débit/crédit connu)
  void updateLocal(int newCoins) {
    _coins = newCoins;
    notifyListeners();
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
    if (_channel != null) {
      _client.removeChannel(_channel!);
    }
    super.dispose();
  }
}

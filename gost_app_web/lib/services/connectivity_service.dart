// ============================================================
// ConnectivityService — Detection online/offline event-driven
// ============================================================
// Pas de dependance native (pas connectivity_plus) -> patchable Shorebird.
//
// Strategie event-driven :
//   - Les services appellent notifyOffline() quand une erreur reseau survient
//   - notifyOnline() quand une operation reseau reussit
//   - online$ stream consomme par l'UI pour afficher banner
//
// Pas de ping sondant (eviterait des appels reseau inutiles).
// Le seul cout est de wrapper les RPC avec NetworkRetry qui notifie ici.
// ============================================================

import 'dart:async';
import '../utils/logger.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  static const _log = Logger('CONNECTIVITY');

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get online$ => _controller.stream;

  DateTime? _lastOfflineAt;
  DateTime? _lastOnlineAt;
  DateTime? get lastOfflineAt => _lastOfflineAt;
  DateTime? get lastOnlineAt => _lastOnlineAt;

  /// Appele depuis NetworkRetry quand toutes les tentatives RPC echouent
  /// avec une erreur reseau.
  void notifyOffline({String? source}) {
    final wasOnline = _isOnline;
    _isOnline = false;
    _lastOfflineAt = DateTime.now();
    if (wasOnline) {
      _log.warn('PASS offline (source=${source ?? "unknown"})');
      _controller.add(false);
    }
  }

  /// Appele quand une operation reseau reussit (RPC, fetch, etc.)
  /// Si on etait offline, broadcast la transition online.
  void notifyOnline({String? source}) {
    final wasOffline = !_isOnline;
    _isOnline = true;
    _lastOnlineAt = DateTime.now();
    if (wasOffline) {
      _log.info('PASS online (source=${source ?? "unknown"})');
      _controller.add(true);
    }
  }

  /// Duree depuis la derniere transition offline (ou null si on a jamais ete offline)
  Duration? get offlineDuration {
    if (_isOnline || _lastOfflineAt == null) return null;
    return DateTime.now().difference(_lastOfflineAt!);
  }
}

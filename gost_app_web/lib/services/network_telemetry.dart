// ============================================================
// NetworkTelemetry — Log fire-and-forget des incidents reseau
// ============================================================
// Appele par NetworkRetry quand une action a du etre reessayee :
//   - 'recovered' : a fini par passer apres N retries
//   - 'failed'    : a echoue malgre tous les retries
//
// Regles strictes :
//   - JAMAIS de throw (toute erreur avalee) -> zero impact gameplay
//   - PAS de NetworkRetry sur le log lui-meme (pas de recursion)
//   - Best-effort : si offline, le log est simplement perdu
//   - Throttle anti-spam : 1 log / action / 5s max
// ============================================================

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class NetworkTelemetry {
  NetworkTelemetry._();
  static final NetworkTelemetry instance = NetworkTelemetry._();

  static const _log = Logger('NET_TELEMETRY');

  // Anti-spam : derniere emission par (label+outcome)
  final Map<String, DateTime> _lastSent = {};
  static const _minInterval = Duration(seconds: 5);

  /// Logue un incident reseau. Fire-and-forget : ne jamais await ce
  /// retour dans un chemin de gameplay (utiliser unawaited).
  Future<void> report({
    required String label,
    required int retries,
    required String outcome, // 'recovered' | 'failed'
    String? error,
  }) async {
    try {
      final key = '$label|$outcome';
      final now = DateTime.now();
      final last = _lastSent[key];
      if (last != null && now.difference(last) < _minInterval) return;
      _lastSent[key] = now;

      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return; // pas de log anonyme

      await client.rpc('log_network_event', params: {
        'p_label': label,
        'p_retries': retries,
        'p_outcome': outcome,
        'p_err': error == null
            ? null
            : (error.length > 300 ? error.substring(0, 300) : error),
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Best-effort : un echec de telemetrie ne doit jamais remonter.
      _log.info('report skipped: $e');
    }
  }
}

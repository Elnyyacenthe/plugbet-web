// ============================================================
// NetworkRetry — Wrapper retry generique pour les RPC Supabase
// ============================================================
// Reessaye automatiquement sur erreurs reseau transitoires :
//   - SocketException (DNS, connection abort, host lookup)
//   - TimeoutException
//   - PostgrestException 5xx (server-side transient)
//
// Ne reessaye PAS sur :
//   - PostgrestException 4xx (erreur metier : INSUFFICIENT_FUNDS, etc.)
//   - Exceptions custom Dart (FormatException, ArgumentError, etc.)
//
// Backoff exponentiel : 500ms -> 1s -> 2s -> 4s (capped a 8s).
// Max 4 tentatives par defaut.
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../utils/logger.dart';
import 'connectivity_service.dart';
import 'network_telemetry.dart';

class NetworkRetry {
  static const _log = Logger('NET_RETRY');

  /// Reessaye [fn] sur erreurs reseau transitoires.
  ///
  /// [maxAttempts] : nombre total de tentatives (incluant la 1ere).
  /// [initialDelay] : delai avant 1er retry. Double a chaque tentative.
  /// [maxDelay] : cap du delai entre tentatives.
  /// [onRetry] : callback appele avant chaque retry (attempt, error).
  ///   Utile pour afficher un banner "Reconnexion..." dans l'UI.
  static Future<T> run<T>(
    Future<T> Function() fn, {
    int maxAttempts = 4,
    Duration initialDelay = const Duration(milliseconds: 500),
    Duration maxDelay = const Duration(seconds: 8),
    void Function(int attempt, Object error)? onRetry,
    String? label,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    Object lastError = Exception('UNREACHABLE');

    while (attempt < maxAttempts) {
      attempt++;
      try {
        final result = await fn();
        // Si on revient d'une erreur reseau : signale qu'on est revenu online
        if (attempt > 1) {
          ConnectivityService.instance.notifyOnline(source: label ?? 'rpc');
          if (label != null) {
            unawaited(NetworkTelemetry.instance.report(
              label: label, retries: attempt - 1, outcome: 'recovered'));
          }
        }
        return result;
      } catch (e) {
        lastError = e;
        if (!_isRetryable(e) || attempt >= maxAttempts) {
          if (_isNetworkError(e) && attempt >= maxAttempts) {
            ConnectivityService.instance.notifyOffline(source: label ?? 'rpc');
            if (label != null) {
              unawaited(NetworkTelemetry.instance.report(
                label: label, retries: attempt, outcome: 'failed',
                error: _errorBrief(e)));
            }
          }
          if (label != null) _log.warn('$label: definitive fail apres $attempt essais: $e');
          rethrow;
        }
        if (label != null) _log.info('$label: retry $attempt/$maxAttempts apres ${delay.inMilliseconds}ms (${_errorBrief(e)})');
        onRetry?.call(attempt, e);
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * 2).clamp(0, maxDelay.inMilliseconds));
      }
    }

    throw lastError;
  }

  static bool _isNetworkError(Object e) {
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is HttpException) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('socketexception')
        || msg.contains('failed host lookup')
        || msg.contains('connection abort')
        || msg.contains('connection refused')
        || msg.contains('connection timed out')
        || msg.contains('network is unreachable')
        || msg.contains('clientexception');
  }

  /// True si l'erreur est transitoire (vaut le coup de retry).
  static bool _isRetryable(Object e) {
    // Erreurs reseau Dart natives
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;
    if (e is HttpException) return true;

    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception')) return true;
    if (msg.contains('failed host lookup')) return true;
    if (msg.contains('connection abort')) return true;
    if (msg.contains('connection refused')) return true;
    if (msg.contains('connection timed out')) return true;
    if (msg.contains('connection reset')) return true;
    if (msg.contains('network is unreachable')) return true;
    if (msg.contains('clientexception')) return true;

    // PostgrestException : ne retry que les 5xx (serveur transient)
    if (e is PostgrestException) {
      final code = e.code;
      // 503 service unavailable, 504 gateway timeout, 502 bad gateway
      if (code == '503' || code == '504' || code == '502') return true;
      // PGRST codes : seuls quelques uns sont transients
      // PGRST116 : 'PGRST116' resource not found - PAS retryable
      // Autres = erreur metier, pas retryable
      return false;
    }

    return false;
  }

  static String _errorBrief(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }
}

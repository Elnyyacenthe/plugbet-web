// ============================================================
// Logger — wrapper centralise pour les logs de l'app
// En debug : affiche dans la console
// En release : silencieux (prepare l'integration Sentry/Crashlytics)
// ============================================================
import 'package:flutter/foundation.dart';

/// Niveau de log
enum LogLevel { debug, info, warn, error }

class Logger {
  /// Tag optionnel (ex: 'MESSAGING', 'WALLET', 'API-FD')
  final String tag;

  const Logger(this.tag);

  void debug(Object? message) => _log(LogLevel.debug, message);
  void info(Object? message) => _log(LogLevel.info, message);
  void warn(Object? message) => _log(LogLevel.warn, message);

  /// Log une erreur.
  /// En debug : affiche dans la console.
  /// En release : remonte via [configureErrorReporter] si configure.
  void error(Object? message, [Object? error, StackTrace? stack]) {
    _log(LogLevel.error, message);
    if (error != null && kDebugMode) {
      debugPrint('  └─ $error');
      if (stack != null) debugPrint('  └─ $stack');
    }
    // En release, remonte au service d'erreurs configure (Sentry/Crashlytics).
    if (!kDebugMode && _errorReporter != null) {
      try {
        _errorReporter!(tag, message, error, stack);
      } catch (_) {
        // Ne jamais laisser le reporter planter l'app
      }
    }
  }

  void _log(LogLevel level, Object? message) {
    if (!kDebugMode) return; // silencieux en release
    final prefix = _prefix(level);
    debugPrint('$prefix[$tag] $message');
  }

  String _prefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug: return '🔹 ';
      case LogLevel.info:  return 'ℹ  ';
      case LogLevel.warn:  return '⚠  ';
      case LogLevel.error: return '❌ ';
    }
  }
}

// ============================================================
// Error reporter (Sentry/Crashlytics hook)
// ============================================================

/// Callback pour reporter les erreurs en release.
typedef ErrorReporter = void Function(
  String tag,
  Object? message,
  Object? error,
  StackTrace? stack,
);

ErrorReporter? _errorReporter;

/// Configure le reporter d'erreurs global.
/// Appeler au demarrage de l'app (dans `main.dart`) :
/// ```dart
/// configureErrorReporter((tag, msg, err, stack) {
///   Sentry.captureException(err, stackTrace: stack);
/// });
/// ```
void configureErrorReporter(ErrorReporter? reporter) {
  _errorReporter = reporter;
}

/// Logger global pour les cas ou on ne veut pas creer un Logger(tag)
final log = Logger('APP');

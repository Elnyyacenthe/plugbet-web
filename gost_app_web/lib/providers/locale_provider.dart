// ============================================================
// LocaleProvider — Gestion de la langue de l'app (FR / EN)
// Persiste le choix dans Hive via HiveService
// ============================================================
import 'package:flutter/material.dart';
import '../services/hive_service.dart';

class LocaleProvider extends ChangeNotifier {
  final HiveService _hive;
  Locale? _locale;

  LocaleProvider(this._hive) : _locale = _initLocale(_hive);

  static Locale? _initLocale(HiveService h) {
    final code = h.getSetting<String>('locale');
    if (code == null || code == 'system') return null; // suit le systeme
    return Locale(code);
  }

  /// null = suivre la langue du systeme
  Locale? get locale => _locale;

  /// Code langue actif (pour affichage UI)
  String get currentCode => _locale?.languageCode ?? 'system';

  /// Nom affichable de la langue actuelle
  String get currentLabel {
    switch (currentCode) {
      case 'fr': return 'Francais';
      case 'en': return 'English';
      default:   return 'Systeme';
    }
  }

  /// Change la langue. Accepte 'fr', 'en', ou 'system'
  void setLanguage(String code) {
    if (code == 'system') {
      _locale = null;
    } else {
      _locale = Locale(code);
    }
    _hive.saveSetting('locale', code);
    notifyListeners();
  }
}

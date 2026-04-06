// ============================================================
// ThemeProvider – Bascule Sombre / Clair
// ============================================================
import 'package:flutter/material.dart';
import '../services/hive_service.dart';

class ThemeProvider extends ChangeNotifier {
  final HiveService _hive;
  ThemeMode _mode;

  ThemeProvider(this._hive)
      : _mode = _initMode(_hive);

  static ThemeMode _initMode(HiveService h) {
    final str = h.getSetting<String>('theme_mode');
    if (str == 'light') return ThemeMode.light;
    if (str == 'system') return ThemeMode.system;
    // Default ou 'dark' ou ancien bool
    final legacy = h.getSetting<bool>('dark_mode');
    if (legacy == false) return ThemeMode.light;
    return ThemeMode.dark;
  }

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  // Accessibilité
  bool get highContrast => _hive.getSetting<bool>('high_contrast') ?? false;
  bool get largeText => _hive.getSetting<bool>('large_text') ?? false;
  double get textScaleFactor => largeText ? 1.3 : 1.0;

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    _hive.saveSetting('dark_mode', isDark);
    _hive.saveSetting('theme_mode', isDark ? 'dark' : 'light');
    notifyListeners();
  }

  void setMode(ThemeMode mode) {
    _mode = mode;
    _hive.saveSetting('dark_mode', mode == ThemeMode.dark);
    _hive.saveSetting('theme_mode',
        mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system');
    notifyListeners();
  }

  void notifyAccessibilityChanged() => notifyListeners();
}

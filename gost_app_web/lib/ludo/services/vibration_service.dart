import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

class VibrationService {
  static bool _enabled = true;
  static bool _hasVibrator = false;
  static bool _checked = false;

  static Future<void> _checkVibrator() async {
    if (_checked) return;
    _checked = true;
    if (kIsWeb) {
      _hasVibrator = false;
      return;
    }
    try {
      _hasVibrator = (await Vibration.hasVibrator()) == true;
    } catch (_) {
      _hasVibrator = false;
    }
  }

  static void setEnabled(bool v) => _enabled = v;
  static bool get enabled => _enabled;

  static Future<void> light() async {
    await _checkVibrator();
    if (!_enabled || !_hasVibrator) return;
    try {
      Vibration.vibrate(duration: 20);
    } catch (_) {}
  }

  static Future<void> medium() async {
    await _checkVibrator();
    if (!_enabled || !_hasVibrator) return;
    try {
      Vibration.vibrate(duration: 50);
    } catch (_) {}
  }

  static Future<void> heavy() async {
    await _checkVibrator();
    if (!_enabled || !_hasVibrator) return;
    try {
      Vibration.vibrate(duration: 100, amplitude: 255);
    } catch (_) {}
  }
}

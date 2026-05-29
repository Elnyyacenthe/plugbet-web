// ============================================================
// PenaltyAudio — implémentation Flutter Web via dart:html
// AudioElement (les MP3 sont déjà bundles dans assets/audio/ via
// pubspec, servis sous /assets/audio/<nom>.mp3 par Flutter web).
// Contourne le 'kIsWeb skip' de AudioService.
// ============================================================
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

class PenaltyAudio {
  PenaltyAudio._();

  static html.AudioElement? _ambient;

  static html.AudioElement _make(String asset,
      {bool loop = false, double vol = 0.8}) {
    final a = html.AudioElement()
      ..src = 'assets/assets/audio/$asset'
      ..loop = loop
      ..volume = vol
      ..preload = 'auto';
    return a;
  }

  static void startAmbient() {
    try {
      _ambient?.pause();
      _ambient = _make('bg_music.mp3', loop: true, vol: 0.3);
      // play() peut être bloqué par la politique autoplay si pas de
      // user-gesture récent ; on ignore l'éventuelle exception.
      _ambient!.play().catchError((_) {});
    } catch (_) {}
  }

  static void stopAmbient() {
    try {
      _ambient?.pause();
      _ambient = null;
    } catch (_) {}
  }

  static void _playOnce(String asset, {double vol = 0.8}) {
    try {
      final a = _make(asset, vol: vol);
      a.play().catchError((_) {});
    } catch (_) {}
  }

  static void playKick() => _playOnce('dice_roll.mp3', vol: 0.8);
  static void playGoal() => _playOnce('win.mp3', vol: 0.9);
  static void playSave() => _playOnce('capture.mp3', vol: 0.8);
}

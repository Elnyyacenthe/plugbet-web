import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import '../../services/hive_service.dart';

class AudioService {
  static final AudioService instance = AudioService._();
  AudioService._();

  bool _soundEnabled = true;
  bool _musicEnabled = true;
  double _sfxVolume = 0.8;
  double _musicVolume = 0.5;
  bool _initialized = false;

  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;

    // Lire les réglages depuis Hive
    try {
      final hive = HiveService();
      _soundEnabled = hive.getSetting<bool>('sound_enabled') ?? true;
      _musicEnabled = hive.getSetting<bool>('sound_enabled') ?? true; // music suit sound global
      _sfxVolume = (hive.getSetting<double>('sfx_volume') ?? 0.8).clamp(0.0, 1.0);
      _musicVolume = (hive.getSetting<double>('music_volume') ?? 0.5).clamp(0.0, 1.0);
    } catch (_) {}

    try {
      await FlameAudio.audioCache.loadAll([
        'dice_roll.mp3',
        'pawn_move.mp3',
        'capture.mp3',
        'win.mp3',
      ]);
      _initialized = true;
    } catch (e) {
      debugPrint('AudioService init skipped (fichiers audio manquants): $e');
    }
  }

  /// Recharge les réglages depuis Hive (appelé quand les settings changent)
  void reloadSettings() {
    try {
      final hive = HiveService();
      _soundEnabled = hive.getSetting<bool>('sound_enabled') ?? true;
      _sfxVolume = (hive.getSetting<double>('sfx_volume') ?? 0.8).clamp(0.0, 1.0);
      _musicVolume = (hive.getSetting<double>('music_volume') ?? 0.5).clamp(0.0, 1.0);

      if (!_soundEnabled) {
        stopBackgroundMusic();
      }
    } catch (_) {}
  }

  void playDiceRoll() {
    if (kIsWeb || !_soundEnabled || !_initialized) return;
    final enabled = _getSpecific('sound_dice');
    if (!enabled) return;
    try { FlameAudio.play('dice_roll.mp3', volume: _sfxVolume).then((_) {}).catchError((e) { debugPrint('[AUDIO] $e'); }); } catch (_) {}
  }

  void playPawnMove() {
    if (kIsWeb || !_soundEnabled || !_initialized) return;
    try { FlameAudio.play('pawn_move.mp3', volume: _sfxVolume * 0.6).then((_) {}).catchError((e) { debugPrint('[AUDIO] $e'); }); } catch (_) {}
  }

  void playCapture() {
    if (kIsWeb || !_soundEnabled || !_initialized) return;
    final enabled = _getSpecific('sound_capture');
    if (!enabled) return;
    try { FlameAudio.play('capture.mp3', volume: _sfxVolume).then((_) {}).catchError((e) { debugPrint('[AUDIO] $e'); }); } catch (_) {}
  }

  void playWin() {
    if (kIsWeb || !_soundEnabled || !_initialized) return;
    final enabled = _getSpecific('sound_victory');
    if (!enabled) return;
    try { FlameAudio.play('win.mp3', volume: _sfxVolume).then((_) {}).catchError((e) { debugPrint('[AUDIO] $e'); }); } catch (_) {}
  }

  Future<void> startBackgroundMusic() async {
    if (kIsWeb || !_musicEnabled || !_initialized) return;
    try {
      await FlameAudio.bgm.play('bg_music.mp3', volume: _musicVolume);
    } catch (e) {
      debugPrint('[AUDIO] BGM non disponible: $e');
    }
  }

  void stopBackgroundMusic() {
    if (kIsWeb) return;
    try { FlameAudio.bgm.stop(); } catch (_) {}
  }

  void toggleSound(bool enabled) {
    _soundEnabled = enabled;
    if (!enabled) stopBackgroundMusic();
  }

  void toggleMusic(bool enabled) {
    _musicEnabled = enabled;
    if (!enabled) {
      stopBackgroundMusic();
    } else {
      startBackgroundMusic();
    }
  }

  /// Lit un réglage son spécifique depuis Hive
  bool _getSpecific(String key) {
    try {
      return HiveService().getSetting<bool>(key) ?? true;
    } catch (_) {
      return true;
    }
  }
}

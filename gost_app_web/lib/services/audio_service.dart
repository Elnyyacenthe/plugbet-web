import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'hive_service.dart';

class AudioService {
  static final AudioService instance = AudioService._();

  AudioService._();

  bool _soundEnabled = true;
  bool _musicEnabled = true;
  double _sfxVolume = 0.8;
  double _musicVolume = 0.5;
  bool _settingsLoaded = false;

  static const String _defaultGame = 'ludo';
  String _currentGame = _defaultGame;
  final Set<String> _loadedGames = <String>{};

  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;
  String get currentGame => _currentGame;

  static const Map<String, List<String>> _gameAssets = {
    'ludo': [
      'bg_music.mp3',
      'dice_roll.mp3',
      'pawn_move.mp3',
      'capture.mp3',
      'win.mp3'
    ],
    'ludo_v2': [
      'bg_music.mp3',
      'dice_roll.mp3',
      'pawn_move.mp3',
      'capture.mp3',
      'win.mp3'
    ],
    'cora_dice': [
      'bg_music.mp3',
      'dice_roll.mp3',
      'land.mp3',
      'lose.mp3',
      'win.mp3'
    ],
    'penalty': [
      'bg_music.mp3',
      'kick.mp3',
      'save.mp3',
      'win.mp3',
      'whistle.mp3'
    ],
    'apple_fortune': [
      'bg_music.mp3',
      'spin.mp3',
      'land.mp3',
      'lose.mp3',
      'win.mp3'
    ],
    'aviator': [
      'bg_music.mp3',
      'climb.mp3',
      'crash.mp3',
      'plane_takeoff.mp3',
      'win.mp3'
    ],
    'blackjack': [
      'bg_music.mp3',
      'card_flip.mp3',
      'chip_place.mp3',
      'lose.mp3',
      'win.mp3'
    ],
    'checkers': [
      'bg_music.mp3',
      'capture.mp3',
      'jump.mp3',
      'piece_move.mp3',
      'win.mp3'
    ],
    'coinflip': ['bg_music.mp3', 'coin_flip.mp3', 'result.mp3', 'win.mp3'],
    'mines': [
      'bg_music.mp3',
      'click.mp3',
      'explosion.mp3',
      'safe.mp3',
      'win.mp3'
    ],
    'roulette': [
      'bg_music.mp3',
      'ball_rolling.mp3',
      'land.mp3',
      'spin_start.mp3',
      'win.mp3'
    ],
    'slots_777': [
      'bg_music.mp3',
      'jackpot.mp3',
      'reel_stop.mp3',
      'spin.mp3',
      'win.mp3'
    ],
    'solitaire': [
      'bg_music.mp3',
      'card_flip.mp3',
      'complete.mp3',
      'valid_move.mp3'
    ],
    'wheel': ['bg_music.mp3', 'land.mp3', 'lose.mp3', 'spin.mp3', 'win.mp3'],
  };

  static const Map<String, Map<String, String>> _gameSoundAssets = {
    'default': {
      'dice_roll': 'dice_roll.mp3',
      'pawn_move': 'pawn_move.mp3',
      'capture': 'capture.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
      'spin': 'spin.mp3',
      'land': 'land.mp3',
      'lose': 'lose.mp3',
      'click': 'click.mp3',
      'card_flip': 'card_flip.mp3',
      'chip_place': 'chip_place.mp3',
      'coin_flip': 'coin_flip.mp3',
      'result': 'result.mp3',
      'jump': 'jump.mp3',
      'piece_move': 'piece_move.mp3',
      'reel_stop': 'reel_stop.mp3',
      'jackpot': 'jackpot.mp3',
      'ball_rolling': 'ball_rolling.mp3',
      'spin_start': 'spin_start.mp3',
      'valid_move': 'valid_move.mp3',
      'complete': 'complete.mp3',
      'safe': 'safe.mp3',
      'explosion': 'explosion.mp3',
      'climb': 'climb.mp3',
      'crash': 'crash.mp3',
      'plane_takeoff': 'plane_takeoff.mp3',
      'move': 'piece_move.mp3',
      'flip': 'card_flip.mp3',
      'start': 'spin.mp3',
      'bet': 'chip_place.mp3',
    },
    'penalty': {
      'dice_roll': 'kick.mp3',
      'capture': 'save.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
      'spin': 'kick.mp3',
      'start': 'kick.mp3',
    },
    'apple_fortune': {
      'spin': 'spin.mp3',
      'land': 'land.mp3',
      'lose': 'lose.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
    },
    'aviator': {
      'spin': 'plane_takeoff.mp3',
      'land': 'climb.mp3',
      'lose': 'crash.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
      'start': 'plane_takeoff.mp3',
      'plane_takeoff': 'plane_takeoff.mp3',
      'climb': 'climb.mp3',
      'crash': 'crash.mp3',
    },
    'blackjack': {
      'flip': 'card_flip.mp3',
      'bet': 'chip_place.mp3',
      'lose': 'lose.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
      'card_flip': 'card_flip.mp3',
      'chip_place': 'chip_place.mp3',
    },
    'checkers': {
      'move': 'piece_move.mp3',
      'capture': 'capture.mp3',
      'jump': 'jump.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
      'pawn_move': 'piece_move.mp3',
    },
    'coinflip': {
      'spin': 'coin_flip.mp3',
      'result': 'result.mp3',
      'win': 'win.mp3',
      'lose': 'result.mp3',
      'bg_music': 'bg_music.mp3',
    },
    'mines': {
      'click': 'click.mp3',
      'lose': 'explosion.mp3',
      'safe': 'safe.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
    },
    'roulette': {
      'spin': 'spin_start.mp3',
      'land': 'ball_rolling.mp3',
      'lose': 'land.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
    },
    'slots_777': {
      'spin': 'spin.mp3',
      'win': 'win.mp3',
      'jackpot': 'jackpot.mp3',
      'reel_stop': 'reel_stop.mp3',
      'bg_music': 'bg_music.mp3',
    },
    'solitaire': {
      'flip': 'card_flip.mp3',
      'valid_move': 'valid_move.mp3',
      'complete': 'complete.mp3',
      'win': 'complete.mp3',
      'bg_music': 'bg_music.mp3',
      'card_flip': 'card_flip.mp3',
      'move': 'valid_move.mp3',
    },
    'wheel': {
      'spin': 'spin.mp3',
      'land': 'land.mp3',
      'lose': 'lose.mp3',
      'win': 'win.mp3',
      'bg_music': 'bg_music.mp3',
    },
  };

  Future<void> init({String defaultGame = _defaultGame}) async {
    await _loadSettings();
    await configureGame(defaultGame);
  }

  Future<void> configureGame(String gameKey) async {
    final normalized = gameKey.trim();
    final effectiveGame =
        _gameAssets.containsKey(normalized) ? normalized : _defaultGame;
    if (_currentGame == effectiveGame && _loadedGames.contains(effectiveGame)) {
      return;
    }

    _currentGame = effectiveGame;
    await _loadSettings();

    await _loadAssetsForGame(effectiveGame);
  }

  Future<void> _loadSettings() async {
    if (_settingsLoaded) return;

    try {
      final hive = HiveService();
      _soundEnabled = hive.getSetting<bool>('sound_enabled') ?? true;
      _musicEnabled = hive.getSetting<bool>('music_enabled') ??
          hive.getSetting<bool>('sound_enabled') ??
          true;
      _sfxVolume =
          (hive.getSetting<double>('sfx_volume') ?? 0.8).clamp(0.0, 1.0);
      _musicVolume =
          (hive.getSetting<double>('music_volume') ?? 0.5).clamp(0.0, 1.0);
    } catch (_) {}

    _settingsLoaded = true;
  }

  Future<void> _loadAssetsForGame(String gameKey) async {
    if (_loadedGames.contains(gameKey)) return;

    final files = _gameAssets[gameKey] ?? _gameAssets['ludo']!;
    final paths = files.map((file) => _assetPath(gameKey, file)).toList();

    try {
      await FlameAudio.audioCache.loadAll(paths);
      _loadedGames.add(gameKey);
    } catch (e) {
      debugPrint(
          'AudioService init skipped for "$gameKey" (fichiers audio manquants): $e');
    }
  }

  String _assetPath(String gameKey, String fileName) {
    return 'games/$gameKey/$fileName';
  }

  void reloadSettings() {
    try {
      final hive = HiveService();
      _soundEnabled = hive.getSetting<bool>('sound_enabled') ?? true;
      _musicEnabled = hive.getSetting<bool>('music_enabled') ??
          hive.getSetting<bool>('sound_enabled') ??
          true;
      _sfxVolume =
          (hive.getSetting<double>('sfx_volume') ?? 0.8).clamp(0.0, 1.0);
      _musicVolume =
          (hive.getSetting<double>('music_volume') ?? 0.5).clamp(0.0, 1.0);

      if (!_soundEnabled || !_musicEnabled) {
        stopBackgroundMusic();
      } else {
        try {
          if (FlameAudio.bgm.isPlaying) {
            FlameAudio.bgm.audioPlayer.setVolume(_musicVolume);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void playDiceRoll() {
    if (!_soundEnabled) return;
    final enabled = _getSpecific('sound_dice');
    if (!enabled) return;
    playSound('dice_roll');
  }

  void playPawnMove() {
    if (!_soundEnabled) return;
    playSound('pawn_move', volumeMultiplier: 0.6);
  }

  void playCapture() {
    if (!_soundEnabled) return;
    final enabled = _getSpecific('sound_capture');
    if (!enabled) return;
    playSound('capture');
  }

  void playWin() {
    if (!_soundEnabled) return;
    final enabled = _getSpecific('sound_victory');
    if (!enabled) return;
    playSound('win');
  }

  void playSound(String soundKey, {double volumeMultiplier = 1.0}) {
    if (!_soundEnabled) return;
    try {
      FlameAudio.play(_soundFile(soundKey),
              volume: _sfxVolume * volumeMultiplier)
          .then((_) {})
          .catchError((e) {
        debugPrint('[AUDIO] $e');
      });
    } catch (_) {}
  }

  void playSpin() => playSound('spin');
  void playLand() => playSound('land');
  void playLose() => playSound('lose');
  void playClick() => playSound('click');
  void playCardFlip() => playSound('card_flip');
  void playChipPlace() => playSound('chip_place');
  void playCoinFlip() => playSound('coin_flip');
  void playResult() => playSound('result');
  void playJump() => playSound('jump');
  void playPieceMove() => playSound('piece_move');
  void playReelStop() => playSound('reel_stop');
  void playJackpot() => playSound('jackpot');
  void playBallRolling() => playSound('ball_rolling');
  void playSpinStart() => playSound('spin_start');
  void playValidMove() => playSound('valid_move');
  void playComplete() => playSound('complete');
  void playSafe() => playSound('safe');
  void playExplosion() => playSound('explosion');
  void playClimb() => playSound('climb');
  void playCrash() => playSound('crash');
  void playPlaneTakeoff() => playSound('plane_takeoff');

  Future<void> startBackgroundMusic() async {
    if (!_musicEnabled) return;
    try {
      await FlameAudio.bgm.play(_soundFile('bg_music'), volume: _musicVolume);
    } catch (e) {
      debugPrint('[AUDIO] BGM non disponible: $e');
    }
  }

  void stopBackgroundMusic() {
    try {
      FlameAudio.bgm.stop().catchError((_) {});
    } catch (_) {}
    try {
      FlameAudio.bgm.audioPlayer.stop().catchError((_) {});
    } catch (_) {}
  }

  void toggleSound(bool enabled) {
    _soundEnabled = enabled;
    if (!enabled) {
      stopBackgroundMusic();
    }
  }

  void toggleMusic(bool enabled) {
    _musicEnabled = enabled;
    if (!enabled) {
      stopBackgroundMusic();
    } else {
      startBackgroundMusic();
    }
  }

  String _soundFile(String key) {
    final map = _gameSoundAssets[_currentGame] ?? _gameSoundAssets['default']!;
    final fileName = map[key] ?? _gameSoundAssets['default']![key]!;
    return _assetPath(_currentGame, fileName);
  }

  bool _getSpecific(String key) {
    try {
      return HiveService().getSetting<bool>(key) ?? true;
    } catch (_) {
      return true;
    }
  }
}

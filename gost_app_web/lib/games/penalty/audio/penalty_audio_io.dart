// ============================================================
// PenaltyAudio — implémentation mobile/desktop via AudioService
// (FlameAudio). Identique au comportement précédent.
// ============================================================

import '../../../ludo/services/audio_service.dart';

class PenaltyAudio {
  PenaltyAudio._();

  static void startAmbient() {
    try { AudioService.instance.startBackgroundMusic(); } catch (_) {}
  }

  static void stopAmbient() {
    try { AudioService.instance.stopBackgroundMusic(); } catch (_) {}
  }

  static void playKick() {
    try { AudioService.instance.playDiceRoll(); } catch (_) {}
  }

  static void playGoal() {
    try { AudioService.instance.playWin(); } catch (_) {}
  }

  static void playSave() {
    try { AudioService.instance.playCapture(); } catch (_) {}
  }
}

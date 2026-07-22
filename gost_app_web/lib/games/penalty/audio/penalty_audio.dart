// ============================================================
// PenaltyAudio — façade audio cross-platform pour Penalty
// ============================================================
// Imports conditionnels : sur mobile/desktop on délègue à AudioService
// existant (FlameAudio). Sur Flutter web on utilise dart:html
// AudioElement directement pour contourner le kIsWeb skip d'AudioService.
//
// Cinq sons :
//   * startAmbient() : bg_music.mp3 en boucle (ambiance foule)
//   * stopAmbient()  : arrêt
//   * playKick()     : dice_roll.mp3 (frappe)
//   * playGoal()     : win.mp3 (but)
//   * playSave()     : capture.mp3 (arrêt par le gardien)
// ============================================================

export 'penalty_audio_io.dart';

// ============================================================
// Shorebird — OTA code push service
// 2 modes : silencieux (fond) ou avec dialog "Redemarrer maintenant ?"
// ============================================================
import 'package:flutter/material.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';

class ShorebirdService {
  static final ShorebirdService instance = ShorebirdService._();
  ShorebirdService._();

  static const _log = Logger('SHOREBIRD');
  final _updater = ShorebirdUpdater();

  /// True quand un patch a ete telecharge et attend un redemarrage.
  bool _patchReady = false;
  bool get patchReady => _patchReady;

  bool get isAvailable => _updater.isAvailable;

  /// Numero du patch actuellement installe (null si base release).
  Future<int?> currentPatchNumber() async {
    if (!isAvailable) return null;
    try {
      final patch = await _updater.readCurrentPatch();
      return patch?.number;
    } catch (e, s) {
      _log.error('currentPatchNumber', e, s);
      return null;
    }
  }

  /// Verifie et telecharge silencieusement un nouveau patch.
  /// Le patch sera applique au prochain redemarrage de l'app.
  Future<void> checkForUpdate() async {
    if (!isAvailable) {
      _log.info('Shorebird indisponible (debug ou build non patchable)');
      return;
    }
    try {
      final status = await _updater.checkForUpdate();
      switch (status) {
        case UpdateStatus.outdated:
          _log.info('Patch disponible — telechargement...');
          await _updater.update();
          _patchReady = true;
          _log.info('Patch telecharge. Applique au prochain redemarrage.');
          break;
        case UpdateStatus.restartRequired:
          _patchReady = true;
          break;
        case UpdateStatus.upToDate:
          _log.info('App a jour');
          break;
        case UpdateStatus.unavailable:
          break;
      }
    } catch (e, s) {
      _log.error('checkForUpdate', e, s);
    }
  }

  /// Affiche un dialog "Mise a jour prete — Redemarrer ?" si un patch
  /// a ete telecharge. A appeler apres le 1er frame depuis un Widget.
  Future<void> showRestartDialogIfReady(BuildContext context) async {
    if (!_patchReady || !context.mounted) return;
    final t = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.system_update, color: AppColors.neonGreen, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t.updateAvailableTitle,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          t.updateAvailableMessage,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.updateLater, style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Le patch s'applique au prochain redemarrage —
              // on ne peut pas killer l'app proprement depuis Dart.
              // L'utilisateur doit fermer/rouvrir manuellement.
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(
              t.updateRestartNow,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

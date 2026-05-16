// ============================================================
// NetworkLostOverlay — Page perte-réseau réutilisable (neutre)
// ============================================================
// Recouvre n'importe quel écran d'une page plein-écran sobre quand
// ConnectivityService passe hors-ligne, et la retire automatiquement
// au retour online (l'écran sous-jacent garde son état : aucune
// reconstruction/teardown).
//
// Politique : NEUTRE (pas d'emblème par jeu). Ludo V2 et Dames gardent
// leurs pages thématisées dédiées ; tous les autres jeux utilisent
// cette page commune.
//
// Usage : return NetworkLostOverlay(child: Scaffold(...));
//   - onRetry (optionnel) : action de re-fetch propre à l'écran.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';

class NetworkLostOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback? onRetry;

  const NetworkLostOverlay({super.key, required this.child, this.onRetry});

  @override
  State<NetworkLostOverlay> createState() => _NetworkLostOverlayState();
}

class _NetworkLostOverlayState extends State<NetworkLostOverlay> {
  late final StreamSubscription<bool> _sub;
  late bool _offline;

  @override
  void initState() {
    super.initState();
    _offline = !ConnectivityService.instance.isOnline;
    _sub = ConnectivityService.instance.online$.listen((online) {
      if (!mounted) return;
      setState(() => _offline = !online);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_offline)
          Positioned.fill(
            child: _NeutralNetworkPage(onRetry: widget.onRetry),
          ),
      ],
    );
  }
}

class _NeutralNetworkPage extends StatelessWidget {
  final VoidCallback? onRetry;
  const _NeutralNetworkPage({this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgDark,
      child: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.bgElevated,
                      border: Border.all(
                        color: AppColors.divider.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: Icon(Icons.wifi_off_rounded,
                        size: 44, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Connexion perdue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Vérifie ta connexion internet.\nReconnexion automatique en cours…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 26),
                    ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.bgElevated,
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      label: const Text('Réessayer',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

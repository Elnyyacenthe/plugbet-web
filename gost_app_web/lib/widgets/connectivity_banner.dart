// ============================================================
// ConnectivityBanner — Banner persistant en haut des ecrans de jeu
// ============================================================
// Affiche :
//   - Banner rouge "Hors ligne" si ConnectivityService.isOnline == false
//   - Banner vert flash 1.5s "Reconnecte" a la transition offline->online
//   - Rien sinon
//
// A wrapper autour du body du jeu (ou placer en haut de Column).
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';

class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  late StreamSubscription<bool> _sub;
  bool _showReconnected = false;
  Timer? _reconnectedTimer;

  @override
  void initState() {
    super.initState();
    _sub = ConnectivityService.instance.online$.listen((online) {
      if (!mounted) return;
      if (online) {
        // Transition offline -> online : flash vert 1.5s puis hide
        setState(() => _showReconnected = true);
        _reconnectedTimer?.cancel();
        _reconnectedTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _showReconnected = false);
        });
      } else {
        // Offline : on rebuild pour afficher le banner rouge
        setState(() => _showReconnected = false);
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _reconnectedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = ConnectivityService.instance.isOnline;

    if (!online) {
      return _banner(
        color: AppColors.neonRed,
        icon: Icons.wifi_off_rounded,
        text: 'Hors ligne — tentative de reconnexion…',
      );
    }
    if (_showReconnected) {
      return _banner(
        color: AppColors.neonGreen,
        icon: Icons.wifi_rounded,
        text: 'Reconnecte',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _banner({required Color color, required IconData icon, required String text}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: color.withValues(alpha: 0.15),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

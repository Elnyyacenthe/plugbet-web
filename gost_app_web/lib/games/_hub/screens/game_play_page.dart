// ============================================================
// GamePlayPage — page de session active (placeholder Phase 2)
// ============================================================
// Phase 2 : shell complet (header, countdown, back-confirm). La
// WebView elle-même arrive en Phase 3 (zone WebViewPlaceholder).
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/network_lost_overlay.dart';
import '../providers/games_hub_provider.dart';

class GamePlayPage extends StatelessWidget {
  const GamePlayPage({super.key});

  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    return Consumer<GamesHubProvider>(
      builder: (_, prov, __) {
        final session = prov.activeSession;

        // Session terminée -> auto-pop
        if (session == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }

        final r = session.remaining;
        final mm = r.inMinutes.toString().padLeft(2, '0');
        final ss = (r.inSeconds % 60).toString().padLeft(2, '0');

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final leave = await _confirmLeave(context, r);
            if (leave == true && context.mounted) {
              await prov.endSession(reason: 'user_exit');
              if (context.mounted) Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.bgDark,
            appBar: AppBar(
              backgroundColor: AppColors.bgBlueNight,
              title: Text(session.game.title,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              actions: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$mm:$ss',
                      style: TextStyle(
                        color: AppColors.neonGreen,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                  ),
                ),
              ],
            ),
            body: const _WebViewPlaceholder(),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmLeave(BuildContext context, Duration remaining) {
    final mm = remaining.inMinutes;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Quitter la partie ?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Il te reste ~$mm min payées. Si tu quittes, la session est perdue (pas de remboursement).',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Continuer à jouer',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Quitter',
                style: TextStyle(
                    color: AppColors.neonRed,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _WebViewPlaceholder extends StatelessWidget {
  const _WebViewPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppColors.bgGradient),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sports_esports_rounded,
                  size: 64, color: AppColors.textMuted),
              const SizedBox(height: 18),
              Text('WebView arrive en Phase 3',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Ta session est active et débitée. Le rendu du jeu sera branché à la phase suivante (webview_flutter + injection JS).',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ExternalGameLauncher — point d'entrée pay-to-play
// ============================================================
// Pushable directement (ex. depuis le tab Jeux du bottom-nav).
// Au premier frame : trouve le GameModel dans le catalogue, vérifie
// le solde, montre le dialog de confirmation, puis :
//   - si OK -> startSession + pushReplacement GamePlayPage
//   - si KO -> snackbar + pop
// Réutilisable pour tout futur jeu WebView (on passe juste gameId).
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../models/game_model.dart';
import '../providers/games_hub_provider.dart';
import 'game_play_page.dart';

class ExternalGameLauncher extends StatefulWidget {
  final String gameId;
  const ExternalGameLauncher({super.key, required this.gameId});

  @override
  State<ExternalGameLauncher> createState() => _ExternalGameLauncherState();
}

class _ExternalGameLauncherState extends State<ExternalGameLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  Future<void> _launch() async {
    if (!mounted) return;
    final prov = context.read<GamesHubProvider>();
    final wallet = context.read<WalletProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Cherche le jeu dans le catalogue
    GameModel? game;
    for (final g in prov.all) {
      if (g.id == widget.gameId) { game = g; break; }
    }
    if (game == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Jeu introuvable dans le catalogue'),
      ));
      navigator.pop();
      return;
    }

    // Pré-check solde
    if (game.entryPriceCoins > 0 && wallet.coins < game.entryPriceCoins) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.neonRed,
        content: Text('Solde insuffisant (${game.entryPriceCoins} coins requis)'),
      ));
      navigator.pop();
      return;
    }

    final confirmed = await _confirmPay(context, game);
    if (!mounted) return;
    if (confirmed != true) {
      navigator.pop();
      return;
    }

    final ok = await prov.startSession(game);
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(SnackBar(
        backgroundColor: AppColors.neonRed,
        content: const Text('Impossible de démarrer la session'),
      ));
      navigator.pop();
      return;
    }

    try { await wallet.refresh(); } catch (_) {}
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const GamePlayPage()),
    );
  }

  Future<bool?> _confirmPay(BuildContext context, GameModel game) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(game.title,
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          game.entryPriceCoins == 0
              ? 'Session gratuite de ${game.sessionDurationMinutes} min. Lancer ?'
              : 'Payer ${game.entryPriceCoins} coins pour ${game.sessionDurationMinutes} min de jeu ?\n\nLa mise n\'est pas remboursable.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: AppColors.bgDark,
            ),
            child: Text(game.entryPriceCoins == 0 ? 'Jouer' : 'Payer & jouer',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.neonGreen),
      ),
    );
  }
}

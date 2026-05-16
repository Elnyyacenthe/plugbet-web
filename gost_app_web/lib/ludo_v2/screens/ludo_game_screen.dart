// ============================================================
// LUDO V2 — Game Screen
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/matches_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../models/ludo_models.dart';
import '../providers/ludo_game_provider.dart';
import '../widgets/dice_widget.dart';
import '../widgets/ludo_board_widget.dart';
import 'ludo_result_screen.dart';
import '../../ludo/services/audio_service.dart';
import '../../widgets/connectivity_banner.dart';

class LudoV2GameScreen extends StatefulWidget {
  final String gameId;
  const LudoV2GameScreen({super.key, required this.gameId});

  /// [F2] Garde anti-empilement : vrai tant qu'un écran de partie Ludo V2
  /// est monté. La reprise de session (main.dart) ne re-navigue pas si
  /// une partie est déjà affichée.
  static bool isOnScreen = false;

  @override
  State<LudoV2GameScreen> createState() => _LudoV2GameScreenState();
}

class _LudoV2GameScreenState extends State<LudoV2GameScreen> {
  bool _diceAnimating = false;
  int? _lastDice;
  String? _message;
  bool _left = false; // évite double forfait

  @override
  void initState() {
    super.initState();
    LudoV2GameScreen.isOnScreen = true; // [F2]
    // Pause tout le polling réseau pendant le jeu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try { context.read<MatchesProvider>().pausePolling(); } catch (_) {}
      final prov = context.read<LudoV2GameProvider>();
      prov.loadGame(widget.gameId);
      prov.onMoveResult = _onMoveResult;
      prov.onGameOver = _onGameOver;
    });
  }

  @override
  void dispose() {
    LudoV2GameScreen.isOnScreen = false; // [F2]
    // [F3] NE PAS forfaiter au dispose : le dispose n'est pas un signal
    // fiable d'intention (recréation d'arbre sur changement thème/langue,
    // pushReplacement externe...). L'abandon ne se fait QUE via une
    // intention explicite confirmée (_onWillPop -> _forfeitIfNeeded).
    // L'absence du joueur est déjà gérée serveur (register_timeout /
    // claim_idle_win).
    try {
      context.read<MatchesProvider>().resumePolling();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _forfeitIfNeeded() async {
    if (_left) return;
    _left = true;
    try {
      final prov = context.read<LudoV2GameProvider>();
      if (prov.game != null && prov.game!.status == 'playing') {
        await prov.forfeit();
      }
    } catch (_) {}
  }

  Future<bool> _onWillPop() async {
    final game = context.read<LudoV2GameProvider>().game;
    if (game == null || game.status != 'playing') return true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(AppLocalizations.of(context)!.ludoQuitQuestion, style: const TextStyle(color: Colors.white)),
        content: Text(AppLocalizations.of(context)!.ludoForfeitMessage, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.gameStay)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.gameForfeit, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _forfeitIfNeeded();
      return true;
    }
    return false;
  }

  void _onMoveResult(bool captured, bool won, bool extraTurn) {
    if (!mounted) return;
    // SFX : capture > win > pawn_move (priorite)
    if (won) {
      AudioService.instance.playWin();
    } else if (captured) {
      AudioService.instance.playCapture();
    } else {
      AudioService.instance.playPawnMove();
    }
    String? msg;
    if (won) msg = 'Victoire !';
    else if (captured) msg = 'Pion capturé !';
    else if (extraTurn) msg = 'Encore un tour !';

    if (msg != null) {
      setState(() => _message = msg);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _message = null);
      });
    }
  }

  void _onGameOver(String winnerId) {
    if (!mounted) return;
    _left = true; // Empêcher le forfait au dispose

    // Rafraîchir le wallet immédiatement
    try { context.read<WalletProvider>().refresh(); } catch (_) {}

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      final prov = context.read<LudoV2GameProvider>();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LudoV2ResultScreen(
            game: prov.game!,
            myId: prov.myId,
          ),
        ),
      );
    });
  }

  Future<void> _rollDice(LudoV2GameProvider prov) async {
    setState(() => _diceAnimating = true);
    AudioService.instance.playDiceRoll();
    final dice = await prov.rollDice();
    if (dice != null) _lastDice = dice;
    // Animation dure 600ms, on attend la fin
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _diceAnimating = false);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: context.read<LudoV2GameProvider>(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) Navigator.of(context).pop();
        },
        child: Scaffold(
        backgroundColor: AppColors.bgDark,
        appBar: AppBar(
          backgroundColor: AppColors.bgBlueNight,
          title: Text(AppLocalizations.of(context)!.ludoTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
          centerTitle: true,
          actions: [
            Consumer<LudoV2GameProvider>(
              builder: (_, prov, __) {
                final game = prov.game;
                if (game == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.neonGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Pot: ${game.betAmount * game.turnOrder.length}',
                        style: TextStyle(color: AppColors.neonGreen, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Consumer<LudoV2GameProvider>(
          builder: (_, prov, __) {
            if (prov.loading) {
              return Center(child: CircularProgressIndicator(color: AppColors.neonGreen));
            }
            if (prov.error != null) {
              // Page d'erreur/réseau IDENTITAIRE LUDO (couvre Ludo) —
              // remplace le Text brut bloquant (audit ANO-9).
              return _LudoErrorView(
                message: prov.error!,
                onRetry: () => prov.loadGame(widget.gameId),
              );
            }
            final game = prov.game;
            if (game == null) {
              return Center(child: Text(AppLocalizations.of(context)!.commonLoading, style: TextStyle(color: AppColors.textSecondary)));
            }

            final isMyTurn = prov.isMyTurn;
            final needsRoll = isMyTurn && !game.diceRolled && !_diceAnimating;
            final canTapPawn = isMyTurn && game.diceRolled && !_diceAnimating;

            return Column(
              children: [
                const ConnectivityBanner(),
                // Status bar
                _buildStatusBar(game, prov),

                // [F5] Bouton "Réclamer la victoire" si l'adversaire est
                // AFK > 90s. canClaimIdleWin est rafraîchi toutes les 5s
                // par _startIdleClaimWatcher. Sans ce bouton (régression
                // vs Checkers), le joueur présent finissait par forfaiter
                // une partie où l'adversaire était absent.
                if (prov.canClaimIdleWin)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    color: AppColors.neonOrange.withValues(alpha: 0.12),
                    child: Row(
                      children: [
                        Icon(Icons.timer_off,
                            color: AppColors.neonOrange, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Adversaire absent depuis ${prov.adversaryIdleSeconds()}s',
                            style: TextStyle(
                                color: AppColors.neonOrange, fontSize: 12),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            // Capturer le messenger AVANT l'await (évite
                            // use_build_context_synchronously).
                            final messenger =
                                ScaffoldMessenger.of(context);
                            final won = await prov.claimIdleWin();
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(won
                                    ? 'Victoire réclamée !'
                                    : 'Impossible de réclamer pour le moment.'),
                                backgroundColor: won
                                    ? AppColors.neonGreen
                                    : AppColors.neonRed,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.neonOrange,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          child: const Text('Réclamer la victoire'),
                        ),
                      ],
                    ),
                  ),

                // Message flottant
                if (_message != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    color: AppColors.neonGreen.withValues(alpha: 0.15),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.neonGreen, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),

                // Plateau
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LudoV2BoardWidget(
                      game: game,
                      previousGame: prov.previousGame,
                      myId: prov.myId,
                      playableMoves: canTapPawn ? prov.playableMoves : [],
                      onPawnTap: canTapPawn ? (i) => prov.playMove(i) : null,
                    ),
                  ),
                ),

                // Barre du bas : joueurs + dé
                _buildBottomBar(game, prov, needsRoll),
              ],
            );
          },
        ),
      ),
      ),
    );
  }

  Widget _buildStatusBar(LudoV2Game game, LudoV2GameProvider prov) {
    final isMyTurn = prov.isMyTurn;
    final turnColor = _colorForPlayer(game, game.currentTurn);
    final seconds = prov.secondsLeft;
    final lives = prov.timeoutsLeft;  // serveur : timeouts restants avant forfait

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: turnColor.withValues(alpha: 0.15),
        border: Border(bottom: BorderSide(color: turnColor.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          // Vies (coeurs)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (i) => Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                i < lives ? Icons.favorite : Icons.favorite_border,
                size: 14,
                color: i < lives ? Colors.redAccent : Colors.grey,
              ),
            )),
          ),
          const SizedBox(width: 8),

          // Status
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: turnColor),
                ),
                const SizedBox(width: 6),
                Text(
                  isMyTurn ? 'Ton tour !' : 'Adversaire...',
                  style: TextStyle(
                    color: isMyTurn ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (game.diceValue != null && game.diceRolled) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Dé: ${game.diceValue}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Countdown
          if (isMyTurn && seconds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: seconds <= 5
                    ? Colors.red.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${seconds}s',
                style: TextStyle(
                  color: seconds <= 5 ? Colors.redAccent : Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(LudoV2Game game, LudoV2GameProvider prov, bool needsRoll) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        color: AppColors.bgBlueNight,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          // Joueurs à gauche
          Expanded(child: _buildPlayerList(game, prov, true)),

          // Dé au centre
          LudoV2DiceWidget(
            value: _lastDice ?? game.diceValue,
            enabled: needsRoll,
            rolling: _diceAnimating,
            onTap: needsRoll ? () => _rollDice(prov) : null,
          ),

          // Joueurs à droite
          Expanded(child: _buildPlayerList(game, prov, false)),
        ],
      ),
    );
  }

  Widget _buildPlayerList(LudoV2Game game, LudoV2GameProvider prov, bool leftSide) {
    final players = game.turnOrder;
    final half = (players.length / 2).ceil();
    final subset = leftSide ? players.take(half) : players.skip(half);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: leftSide ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: subset.map((uid) {
        final color = _colorForPlayer(game, uid);
        final isActive = game.currentTurn == uid;
        final isMe = uid == prov.myId;
        final progress = (game.myPawns(uid).where((s) => s >= 58).length * 25);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: isActive ? Border.all(color: Colors.white, width: 2) : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isMe ? 'Toi' : 'J${game.turnOrder.indexOf(uid) + 1}',
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$progress%',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _colorForPlayer(LudoV2Game game, String uid) {
    final idx = game.colorMap[uid] ?? 0;
    const colors = [Color(0xFFE53935), Color(0xFF43A047), Color(0xFF1E88E5), Color(0xFFFDD835)];
    return colors[idx.clamp(0, 3)];
  }
}

/// Page d'erreur / perte réseau IDENTITAIRE LUDO (rendue dans l'écran
/// Ludo uniquement — le filet global main.dart est neutre). Emblème
/// 4 pions Ludo + détection réseau + Réessayer.
class _LudoErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LudoErrorView({required this.message, required this.onRetry});

  bool get _isNetwork {
    final m = message.toLowerCase();
    return m.contains('socketexception') ||
        m.contains('failed host lookup') ||
        m.contains('connection') ||
        m.contains('network') ||
        m.contains('timed out') ||
        m.contains('timeout');
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isNetwork ? AppColors.neonOrange : AppColors.neonRed;
    final pawns = [
      AppColors.neonRed,
      AppColors.neonGreen,
      AppColors.neonBlue,
      AppColors.neonYellow,
    ];
    return Container(
      decoration: BoxDecoration(gradient: AppColors.bgGradient),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 116,
                height: 116,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        gradient: AppColors.cardGradient,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: accent.withValues(alpha: 0.35), width: 1.5),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: GridView.count(
                        crossAxisCount: 2,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        children: [
                          for (final c in pawns)
                            Container(
                              decoration: BoxDecoration(
                                color: c.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.bgDark,
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 2),
                        ),
                        child: Icon(
                          _isNetwork
                              ? Icons.wifi_off_rounded
                              : Icons.error_outline_rounded,
                          size: 22,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Text(
                _isNetwork ? 'Connexion perdue' : 'Souci sur la partie',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isNetwork
                    ? 'Ta partie de Ludo est en sécurité. Reconnecte-toi : '
                        'tu reprends là où tu t\'es arrêté.'
                    : 'Un imprévu est survenu. Réessaie — ta mise et ta '
                        'progression sont sauvegardées.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  label: const Text('Réessayer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

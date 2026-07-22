// ============================================================
// LUDO V2 — Game Screen (premium redesign)
// ============================================================

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../services/audio_service.dart';
import 'package:provider/provider.dart';
import '../../providers/matches_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/network_lost_overlay.dart';
import '../models/ludo_models.dart';
import '../providers/ludo_game_provider.dart';
import '../widgets/dice_widget.dart';
import '../widgets/ludo_board_widget.dart';
import 'ludo_result_screen.dart';
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
    _initAudio();
    LudoV2GameScreen.isOnScreen = true; // [F2]
    // Pause tout le polling réseau pendant le jeu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<MatchesProvider>().pausePolling();
      } catch (_) {}
      final prov = context.read<LudoV2GameProvider>();
      prov.loadGame(widget.gameId);
      prov.onMoveResult = _onMoveResult;
      prov.onGameOver = _onGameOver;
    });
  }

  Future<void> _initAudio() async {
    await AudioService.instance.configureGame('ludo_v2');
    AudioService.instance.startBackgroundMusic();
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
    AudioService.instance.stopBackgroundMusic();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(AppLocalizations.of(context)!.ludoQuitQuestion,
            style: const TextStyle(color: Colors.white)),
        content: Text(AppLocalizations.of(context)!.ludoForfeitMessage,
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context)!.gameStay)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.gameForfeit,
                style: const TextStyle(color: Colors.red)),
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
    if (won)
      msg = 'Victoire !';
    else if (captured)
      msg = 'Pion capturé !';
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
    try {
      context.read<WalletProvider>().refresh();
    } catch (_) {}

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
        child: NetworkLostOverlay(
          onRetry: () {
            try {
              context.read<LudoV2GameProvider>().loadGame(widget.gameId);
            } catch (_) {}
          },
          child: Scaffold(
            backgroundColor: AppColors.bgDark,
            extendBodyBehindAppBar: false,
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.bgBlueNight,
                      Color.lerp(AppColors.bgBlueNight, AppColors.bgDark, 0.5)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: Text(AppLocalizations.of(context)!.ludoTitle,
                      style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  centerTitle: true,
                  actions: [
                    Consumer<LudoV2GameProvider>(
                      builder: (_, prov, __) {
                        final game = prov.game;
                        if (game == null) return const SizedBox.shrink();
                        final pot = game.betAmount * game.turnOrder.length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.neonGreen.withValues(alpha: 0.22),
                                    AppColors.neonGreen.withValues(alpha: 0.08),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.5)),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.neonGreen.withValues(alpha: 0.25),
                                    blurRadius: 10,
                                    spreadRadius: 0.5,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.savings_rounded, size: 14, color: AppColors.neonGreen),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Pot: $pot',
                                    style: TextStyle(
                                        color: AppColors.neonGreen,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            body: Stack(
              children: [
                // Fond dégradé + halos néon d'ambiance (profondeur)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: AppColors.bgGradient),
                  ),
                ),
                Positioned(
                  top: -70,
                  right: -60,
                  child: _glowBlob(AppColors.neonGreen, 220),
                ),
                Positioned(
                  bottom: 30,
                  left: -70,
                  child: _glowBlob(AppColors.neonBlue, 210),
                ),
                Consumer<LudoV2GameProvider>(
              builder: (_, prov, __) {
                if (prov.loading) {
                  return Center(
                      child:
                          CircularProgressIndicator(color: AppColors.neonGreen));
                }
                // Page plein écran UNIQUEMENT en vrai échec de chargement
                // (aucune partie à afficher). Une erreur d'ACTION (lancer de
                // dés / coup) ne doit PAS remplacer tout le plateau : la
                // partie reste valide côté serveur et resync via realtime/
                // polling. Sinon un hoquet de lancer = perte visuelle de la
                // partie alors que mise/progression sont intactes.
                if (prov.error != null && prov.game == null) {
                  return _LudoErrorView(
                    message: prov.error!,
                    onRetry: () => prov.loadGame(widget.gameId),
                  );
                }
                final game = prov.game;
                if (game == null) {
                  return Center(
                      child: Text(AppLocalizations.of(context)!.commonLoading,
                          style: TextStyle(color: AppColors.textSecondary)));
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
                        margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.neonOrange.withValues(alpha: 0.18),
                              AppColors.neonOrange.withValues(alpha: 0.06),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.neonOrange.withValues(alpha: 0.4)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.neonOrange.withValues(alpha: 0.18),
                              blurRadius: 12,
                              spreadRadius: 0.5,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.timer_off,
                                color: AppColors.neonOrange, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Adversaire absent depuis ${prov.adversaryIdleSeconds()}s',
                                style: TextStyle(
                                    color: AppColors.neonOrange,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12),
                              ),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.neonOrange,
                                    Color.lerp(AppColors.neonOrange, Colors.black, 0.15)!,
                                  ],
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () async {
                                    // Capturer le messenger AVANT l'await (évite
                                    // use_build_context_synchronously).
                                    final messenger = ScaffoldMessenger.of(context);
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
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                      ),
                                    );
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                    child: Text(
                                      'Réclamer la victoire',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Message flottant
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: anim, child: child),
                      ),
                      child: _message != null
                          ? Container(
                              key: ValueKey(_message),
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.neonGreen.withValues(alpha: 0.22),
                                    AppColors.neonGreen.withValues(alpha: 0.08),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.45)),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.neonGreen.withValues(alpha: 0.25),
                                    blurRadius: 12,
                                    spreadRadius: 0.5,
                                  ),
                                ],
                              ),
                              child: Text(
                                _message!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppColors.neonGreen,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // Plateau (cadre bois biseauté + halo)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF3A2000),
                                    Color(0xFF7A4F00),
                                    Color(0xFF3A2000),
                                  ],
                                ),
                                border: Border.all(
                                    color: AppColors.neonOrange
                                        .withValues(alpha: 0.5),
                                    width: 1.4),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.neonOrange
                                        .withValues(alpha: 0.25),
                                    blurRadius: 24,
                                    spreadRadius: 1,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: LudoV2BoardWidget(
                                  game: game,
                                  previousGame: prov.previousGame,
                                  myId: prov.myId,
                                  playableMoves:
                                      canTapPawn ? prov.playableMoves : [],
                                  onPawnTap: canTapPawn
                                      ? (i) => prov.playMove(i)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Barre du bas : joueurs + dé
                    _buildBottomBar(game, prov, needsRoll),
                  ],
                );
              },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Halo néon flou d'ambiance (décoratif, aucune interaction).
  Widget _glowBlob(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(LudoV2Game game, LudoV2GameProvider prov) {
    final isMyTurn = prov.isMyTurn;
    final turnColor = _colorForPlayer(game, game.currentTurn);
    final seconds = prov.secondsLeft;
    final lives =
        prov.timeoutsLeft; // serveur : timeouts restants avant forfait

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            turnColor.withValues(alpha: 0.20),
            turnColor.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: turnColor.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: turnColor.withValues(alpha: 0.18),
            blurRadius: 10,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        children: [
          // Vies (coeurs)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
                5,
                (i) => Padding(
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
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: turnColor,
                    boxShadow: [
                      BoxShadow(
                        color: turnColor.withValues(alpha: 0.7),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      'Dé: ${game.diceValue}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Countdown
          if (isMyTurn && seconds > 0)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: seconds <= 5
                    ? Colors.red.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                boxShadow: seconds <= 5
                    ? [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.45),
                          blurRadius: 10,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
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

  Widget _buildBottomBar(
      LudoV2Game game, LudoV2GameProvider prov, bool needsRoll) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.bgBlueNight.withValues(alpha: 0.92),
                AppColors.bgDark.withValues(alpha: 0.96),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: AppColors.divider)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
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
        ),
      ),
    );
  }

  Widget _buildPlayerList(
      LudoV2Game game, LudoV2GameProvider prov, bool leftSide) {
    final players = game.turnOrder;
    final half = (players.length / 2).ceil();
    final subset = leftSide ? players.take(half) : players.skip(half);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          leftSide ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: subset.map((uid) {
        final color = _colorForPlayer(game, uid);
        final isActive = game.currentTurn == uid;
        final isMe = uid == prov.myId;
        final progress = (game.myPawns(uid).where((s) => s >= 58).length * 25);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? color.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: isActive
                  ? Border.all(color: color.withValues(alpha: 0.4))
                  : null,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color.lerp(color, Colors.white, 0.3)!, color],
                    ),
                    border: isActive
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                    boxShadow: isActive
                        ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 5)]
                        : null,
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
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$progress%',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _colorForPlayer(LudoV2Game game, String uid) {
    final idx = game.colorMap[uid] ?? 0;
    const colors = [
      Color(0xFFE53935),
      Color(0xFF43A047),
      Color(0xFF1E88E5),
      Color(0xFFFDD835)
    ];
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
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.2),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ],
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
                                gradient: RadialGradient(
                                  colors: [
                                    Color.lerp(c, Colors.white, 0.25)!.withValues(alpha: 0.9),
                                    c.withValues(alpha: 0.85),
                                  ],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 6),
                                ],
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
                          boxShadow: [
                            BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 1),
                          ],
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
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [AppColors.neonGreen, Color.lerp(AppColors.neonGreen, Colors.black, 0.15)!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonGreen.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 1,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onRetry,
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh_rounded, size: 19, color: Colors.black),
                            SizedBox(width: 8),
                            Text(
                              'Réessayer',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
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

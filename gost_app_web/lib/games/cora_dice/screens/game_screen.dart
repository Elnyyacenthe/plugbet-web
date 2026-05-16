// ============================================================
// CORA DICE - Écran de jeu
// Plateau, dés animés, tour par tour, résultats
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../providers/matches_provider.dart';
import '../../../services/live_score_manager.dart';
// lobby_screen import removed - not needed
import '../../../ludo/services/audio_service.dart';
import '../models/cora_models.dart';
import '../services/cora_service.dart';
import '../components/dice_animation.dart';
import '../../../services/network_retry.dart';
import '../../../widgets/connectivity_banner.dart';

class CoraGameScreen extends StatefulWidget {
  final String gameId;

  const CoraGameScreen({super.key, required this.gameId});

  /// [Cora #1] Anti-empilement : vrai tant qu'une partie Cora est affichée.
  /// Lu par main.dart (_checkActiveCoraSession) pour ne PAS re-naviguer une
  /// 2e CoraGameScreen au retour foreground (sinon double subscription
  /// realtime + double turn-timer + double forfait au dispose sur une
  /// room d'argent). Même pattern que CheckersGameScreen / LudoV2GameScreen.
  static bool isOnScreen = false;

  @override
  State<CoraGameScreen> createState() => _CoraGameScreenState();
}

class _CoraGameScreenState extends State<CoraGameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final CoraService _service = CoraService();
  CoraGame? _game;
  bool _isLoading = true;
  bool _isRolling = false;
  DiceRoll? _lastRoll;
  String? _loadError;
  // Notifier pour que le dialog de fin réagisse aux updates realtime
  // (notamment l'arrivée de votes rematch des autres joueurs).
  final ValueNotifier<CoraGame?> _gameNotifier = ValueNotifier<CoraGame?>(null);
  bool _resultDialogOpen = false;
  bool _rematchNavigated = false;
  // [Cora #6] Vrai dès qu'un forfait serveur explicite a été émis
  // (kick inactivité ou bouton quitter) → évite le re-forfait redondant
  // au dispose et fiabilise l'abandon (ne dépend plus d'un effet de bord).
  bool _forfeitDone = false;

  // Turn timer
  static const int _turnSeconds = 12;
  int _turnCountdown = _turnSeconds;
  Timer? _turnTimer;
  int _consecutiveTimeouts = 0;
  String? _lastTurnPlayerId; // to detect turn changes

  RealtimeChannel? _gameChannel;
  Timer? _pollTimer; // fallback realtime mort

  // Animations
  late AnimationController _diceController;
  late AnimationController _coraController;
  late AnimationController _sevenController;

  @override
  void initState() {
    super.initState();
    CoraGameScreen.isOnScreen = true;
    _diceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _coraController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _sevenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    WidgetsBinding.instance.addObserver(this);
    _loadGame();
    _subscribeToGame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try { context.read<MatchesProvider>().pausePolling(); } catch (_) {}
        try { context.read<LiveScoreManager>().pauseTracking(); } catch (_) {}
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed
        && !(_game?.gameState.isFinished ?? false)) {
      _refetchNow();
    }
  }

  Future<void> _refetchNow() async {
    final fresh = await _service.getGame(widget.gameId);
    if (fresh != null && mounted) _onGameUpdate(fresh);
  }

  @override
  void dispose() {
    CoraGameScreen.isOnScreen = false;
    WidgetsBinding.instance.removeObserver(this);
    _turnTimer?.cancel();
    _diceController.dispose();
    _coraController.dispose();
    _sevenController.dispose();
    _gameNotifier.dispose();
    _pollTimer?.cancel();
    if (_gameChannel != null) _service.unsubscribe(_gameChannel!);
    // [Cora #2] Forfait silencieux si on quitte une partie en cours.
    // Le RPC est idempotent (si déjà finie : no-op). MAIS on ne forfait
    // QUE sur un retour arrière in-app volontaire (lifecycle == resumed)
    // et PAS lors d'une navigation vers la revanche. Si l'app est
    // backgroundée / tuée par l'OS (paused/inactive/detached/hidden), on
    // NE forfait PAS : la perte de mise serait involontaire. Dans ce cas
    // le serveur gère l'abandon (cron cora_cleanup_stuck_games +
    // _cora_force_clean_user) et la session est reprise au retour
    // foreground via _checkActiveCoraSession.
    final game = _game;
    final isResumed = WidgetsBinding.instance.lifecycleState ==
        AppLifecycleState.resumed;
    if (game != null &&
        game.status == CoraRoomStatus.playing &&
        !game.gameState.isFinished &&
        !_rematchNavigated &&
        !_forfeitDone &&
        isResumed) {
      // ignore: discarded_futures
      _service.forfeit(widget.gameId);
    }
    try { context.read<MatchesProvider>().resumePolling(); } catch (_) {}
    try { context.read<LiveScoreManager>().resumeTracking(); } catch (_) {}
    super.dispose();
  }

  Future<void> _loadGame() async {
    setState(() { _isLoading = true; _loadError = null; });
    try {
      final g = await _service.getGame(widget.gameId);
      if (!mounted) return;
      if (g == null) {
        setState(() {
          _isLoading = false;
          _loadError = 'Partie introuvable. Elle a peut-être été annulée ou tu n\'es pas un participant.';
        });
        return;
      }
      setState(() {
        _game = g;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Erreur de chargement : $e';
      });
    }
  }

  void _subscribeToGame() {
    _gameChannel = _service.subscribeGame(
      widget.gameId,
      _onGameUpdate,
      onConnectionLost: _startPollingFallback,
    );
  }

  /// Polling 2s si le realtime meurt. Auto-stop quand fini.
  void _startPollingFallback() {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted || (_game?.gameState.isFinished ?? false)) {
        t.cancel();
        _pollTimer = null;
        return;
      }
      final fresh = await _service.getGame(widget.gameId);
      if (fresh != null) _onGameUpdate(fresh);
    });
  }

  void _onGameUpdate(CoraGame game) {
      if (!mounted) return;
      setState(() => _game = game);
      _gameNotifier.value = game;

      // Start/reset turn timer when turn changes
      final currentTurnId = game.gameState.currentTurn;
      if (currentTurnId != _lastTurnPlayerId && !game.gameState.isFinished) {
        _lastTurnPlayerId = currentTurnId;
        _startTurnTimer(currentTurnId);
      }

      // Animer si un joueur vient de lancer
      final myId = _service.currentUserId;
      if (myId != null) {
        final me = game.gameState.players[myId];
        if (me != null && me.hasRolled && me.roll != _lastRoll) {
          _lastRoll = me.roll;
          _animateRoll(me.roll!);
        }
      }

      // Si rematch accepté → naviguer vers la nouvelle game
      final rm = game.gameState.rematch;
      if (rm != null && rm.isAccepted && rm.newGameId != null && !_rematchNavigated) {
        _rematchNavigated = true;
        // Ferme le dialog si ouvert puis navigate
        if (_resultDialogOpen && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CoraGameScreen(gameId: rm.newGameId!),
          ),
        );
        return;
      }

      // Si partie terminée, afficher résultat après 2s
      if (game.gameState.isFinished && !_resultDialogOpen) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_resultDialogOpen) _showResultDialog();
        });
      }
  }

  void _animateRoll(DiceRoll roll) {
    _diceController.forward(from: 0);

    if (roll.isCora) {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _coraController.forward(from: 0);
      });
    } else if (roll.isSeven) {
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _sevenController.forward(from: 0);
      });
    } else {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen),
        ),
      );
    }
    if (_game == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: AppColors.neonRed, size: 64),
                const SizedBox(height: 16),
                Text(
                  _loadError ?? 'Impossible de charger la partie',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Retour',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _loadGame,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonGreen,
                        foregroundColor: AppColors.bgDark,
                      ),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final myId = _service.currentUserId;
    final me = myId != null ? _game!.gameState.players[myId] : null;
    final isMyTurn = _game!.gameState.currentTurn == myId;

    // [Cora #8] Le geste retour système ne doit PAS contourner la
    // confirmation de forfait. canPop:false → on route vers _confirmExit
    // (qui pop directement si la partie est finie, sinon dialog "tu
    // perdras ta mise"). Même pattern que Ludo/Checkers.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              const ConnectivityBanner(),
              // Header
              _buildHeader(),

              // Scores des joueurs
              _buildScoresBar(),

              // Zone centrale: dés
              Expanded(
                child: Center(
                  child: _buildDiceZone(isMyTurn, me),
                ),
              ),

              // Bouton lancer
              if (!_game!.gameState.isFinished)
                _buildRollButton(isMyTurn, me),

              SizedBox(height: 16),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => _confirmExit(),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CORA DICE',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Pot: ${_game!.potAmount} FCFA',
                  style: TextStyle(
                    color: AppColors.neonYellow,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, color: AppColors.neonGreen, size: 16),
                SizedBox(width: 4),
                Text(
                  '${_game!.playerCount}',
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoresBar() {
    return Container(
      height: 100,
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _game!.gameState.players.length,
        itemBuilder: (context, index) {
          final player = _game!.gameState.players.values.elementAt(index);
          final isCurrentTurn = _game!.gameState.currentTurn == player.userId;
          final isMe = player.userId == _service.currentUserId;

          return _buildPlayerScore(player, isCurrentTurn, isMe);
        },
      ),
    );
  }

  Widget _buildPlayerScore(CoraPlayer player, bool isCurrentTurn, bool isMe) {
    Color borderColor = AppColors.divider;
    if (isCurrentTurn && !_game!.gameState.isFinished) {
      borderColor = AppColors.neonGreen;
    } else if (isMe) {
      borderColor = AppColors.neonBlue;
    }

    return Container(
      width: 90,
      margin: EdgeInsets.only(right: 12),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: isMe
            ? LinearGradient(
                colors: [
                  AppColors.neonBlue.withValues(alpha: 0.2),
                  AppColors.neonGreen.withValues(alpha: 0.1),
                ],
              )
            : AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor:
                player.hasRolled ? AppColors.neonGreen : AppColors.bgElevated,
            child: Text(
              player.username.isNotEmpty ? player.username[0].toUpperCase() : '?',
              style: TextStyle(
                color: player.hasRolled ? AppColors.bgDark : AppColors.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(height: 4),
          Text(
            player.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe ? AppColors.neonBlue : AppColors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 2),
          if (player.hasRolled)
            Text(
              player.hasCora
                  ? 'CORA!'
                  : player.hasSeven
                      ? '7 ❌'
                      : '${player.roll!.total}',
              style: TextStyle(
                color: player.hasCora
                    ? AppColors.neonGreen
                    : player.hasSeven
                        ? AppColors.neonRed
                        : AppColors.neonYellow,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            )
          else
            Text(
              isCurrentTurn ? '⏳' : '...',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiceZone(bool isMyTurn, CoraPlayer? me) {
    if (_game!.gameState.isFinished) {
      return _buildFinishedView();
    }

    if (me != null && me.hasRolled) {
      // Montrer mes dés
      return DiceAnimationWidget(
        dice1: me.roll!.dice1,
        dice2: me.roll!.dice2,
        controller: _diceController,
        isCora: me.hasCora,
        isSeven: me.hasSeven,
        coraController: _coraController,
        sevenController: _sevenController,
      );
    }

    if (isMyTurn) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.casino,
            size: 80,
            color: AppColors.neonGreen.withValues(alpha: 0.5),
          ),
          SizedBox(height: 16),
          Text(
            'À votre tour !',
            style: TextStyle(
              color: AppColors.neonGreen,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Lancez les dés',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    // En attente
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppColors.neonGreen),
        SizedBox(height: 16),
        Text(
          'En attente...',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFinishedView() {
    final result = _game!.gameState.result ?? 'Partie terminée';
    final myId = _service.currentUserId;
    final isWinner = _game!.gameState.winners.contains(myId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isWinner ? Icons.emoji_events : Icons.sentiment_neutral,
          size: 100,
          color: isWinner ? AppColors.neonYellow : AppColors.textMuted,
        ),
        SizedBox(height: 24),
        Text(
          isWinner ? '🎉 VICTOIRE ! 🎉' : result,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isWinner ? AppColors.neonYellow : AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildRollButton(bool isMyTurn, CoraPlayer? me) {
    final canRoll = isMyTurn && (me == null || !me.hasRolled) && !_isRolling;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton(
          onPressed: canRoll ? _rollDice : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.neonGreen,
            foregroundColor: AppColors.bgDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: canRoll ? 10 : 0,
          ),
          child: _isRolling
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.bgDark,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.casino, size: 32),
                    SizedBox(width: 12),
                    Text(
                      'LANCER LES DÉS',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _startTurnTimer(String? turnPlayerId) {
    _turnTimer?.cancel();
    if (!mounted) return;
    setState(() => _turnCountdown = _turnSeconds);
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _turnCountdown--);
      if (_turnCountdown <= 0) {
        t.cancel();
        _onTurnTimeout(turnPlayerId);
      }
    });
  }

  void _onTurnTimeout(String? turnPlayerId) {
    if (_game == null || _game!.gameState.isFinished) return;
    final myId = _service.currentUserId;
    // Only act when it's my own turn
    if (turnPlayerId != myId) return;
    final me = _game!.gameState.players[myId];
    if (me == null || me.hasRolled) return;

    _consecutiveTimeouts++;
    if (_consecutiveTimeouts >= 4) {
      unawaited(_handleForfeit());
      return;
    }
    // [Cora #3] Auto-roll sur timeout : la mise est DÉJÀ engagée au début
    // de la partie, lancer ne coûte rien de plus et évite de figer la
    // partie. Le SERVEUR génère les dés (anti-cheat) — le client ne peut
    // pas biaiser le résultat. L'ancien _generateBiasedRoll() était du
    // code mort trompeur (passé en forcedRoll puis ignoré côté serveur).
    _rollDice(isAuto: true);
  }

  Future<void> _handleForfeit() async {
    _turnTimer?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.gameInactivityKicked),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
    // [Cora #6] Forfait serveur EXPLICITE (idempotent) — ne plus dépendre
    // de l'effet de bord du dispose. Puis refresh wallet pour que le
    // joueur voie son solde à jour immédiatement.
    _forfeitDone = true;
    try { await _service.forfeit(widget.gameId); } catch (_) {}
    if (!mounted) return;
    try { context.read<WalletProvider>().refresh(); } catch (_) {}
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _rollDice({bool isAuto = false}) async {
    if (_isRolling) return; // Anti double-tap
    if (!isAuto) _consecutiveTimeouts = 0;
    setState(() => _isRolling = true);
    AudioService.instance.playDiceRoll();

    // request_id STABLE hors du closure -> idempotence wrapper sur retry
    final reqId = '${_service.currentUserId ?? "anon"}-${widget.gameId}-roll-${DateTime.now().microsecondsSinceEpoch}';
    try {
      // ANTI-CHEAT : le SERVEUR genere les des. Le client recoit le resultat
      // et l'utilise uniquement pour l'animation (impossible de forcer un
      // lancer cote serveur). Retry auto sur erreur reseau.
      final serverRoll = await NetworkRetry.run(
        () => _service.submitRollAndGetServerDice(
          gameId: widget.gameId, requestId: reqId),
        label: 'cora_submit_roll',
      );
      if (serverRoll != null) _animateRoll(serverRoll);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.neonRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRolling = false);
      }
    }
  }

  void _showResultDialog() {
    final myId = _service.currentUserId;
    final isWinner = _game!.gameState.winners.contains(myId);
    final result = _game!.gameState.result ?? 'Partie terminée';
    final isCancelled = _game!.gameState.isCancelled;
    if (!isCancelled && isWinner) {
      AudioService.instance.playWin();
    }
    // Cora double le pot SEULEMENT s'il y a exactement 1 Cora (pas annulé si plusieurs)
    final prize = isWinner
        ? (_game!.gameState.coraCount == 1 ? _game!.potAmount * 2 : _game!.potAmount)
        : 0;

    // Rafraîchir le wallet immédiatement
    try { context.read<WalletProvider>().refresh(); } catch (_) {}

    // Enregistrer XP / stats (sauf partie annulée)
    if (!isCancelled) {
      try {
        context.read<PlayerProvider>().recordGameResult(
          gameType: 'cora',
          result: isWinner ? 'win' : 'loss',
          coinsChange: isWinner ? prize : -(_game!.betAmount),
        );
      } catch (_) {}
    }

    final betAmount = _game!.betAmount;
    final myUid = _service.currentUserId ?? '';

    _resultDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<CoraGame?>(
        valueListenable: _gameNotifier,
        builder: (ctx, game, _) {
          final rematch = game?.gameState.rematch;
          final iVoted = rematch?.didIVote(myUid) ?? false;
          final iAccepted = rematch?.didIAccept(myUid) ?? false;
          final acceptedCount = rematch?.acceptedIds.length ?? 0;
          final totalNeeded = game?.playerCount ?? 2;
          final isPending = rematch?.isPending ?? false;
          final isRefused = rematch?.isRefused ?? false;
          final isExpired = rematch?.isExpired ?? false;

          return AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              Icon(
                isWinner
                    ? Icons.emoji_events
                    : (isCancelled ? Icons.refresh : Icons.info_outline),
                color: isWinner
                    ? AppColors.neonYellow
                    : (isCancelled ? AppColors.neonBlue : AppColors.textSecondary),
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isWinner
                      ? 'Victoire !'
                      : (isCancelled ? 'Partie annulée' : 'Partie terminée'),
                  style: TextStyle(
                    color: isWinner ? AppColors.neonYellow : AppColors.textPrimary,
                    fontSize: 18,
                  ),
                ),
              ),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(result,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
              if (isWinner) ...[
                const SizedBox(height: 12),
                Text('+$prize FCFA',
                    style: TextStyle(
                      color: AppColors.neonYellow,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    )),
              ] else if (!isCancelled) ...[
                const SizedBox(height: 12),
                Text('-$betAmount FCFA',
                    style: TextStyle(
                      color: AppColors.neonRed,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    )),
              ],
              const SizedBox(height: 12),
              Consumer<WalletProvider>(
                builder: (_, w, __) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.divider.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_wallet,
                          color: AppColors.neonYellow, size: 18),
                      const SizedBox(width: 8),
                      Text('Solde : ${w.coins} FCFA',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          )),
                    ],
                  ),
                ),
              ),
              // Section rematch — visible une fois que quelqu'un a voté
              if (rematch != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isRefused || isExpired
                        ? AppColors.neonRed.withValues(alpha: 0.15)
                        : AppColors.neonGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isRefused || isExpired
                          ? AppColors.neonRed.withValues(alpha: 0.4)
                          : AppColors.neonGreen.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    isRefused
                        ? 'Revanche refusée par un joueur.'
                        : isExpired
                            ? 'Délai écoulé. Revanche annulée.'
                            : isPending
                                ? (iAccepted
                                    ? 'En attente des autres joueurs… ($acceptedCount/$totalNeeded prêts)'
                                    : 'Revanche proposée. Acceptes-tu de rejouer ?')
                                : '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ]),
            actions: _buildResultActions(
              ctx, betAmount, rematch, iVoted, iAccepted, isPending,
              isRefused, isExpired,
            ),
          );
        },
      ),
    ).whenComplete(() => _resultDialogOpen = false);
  }

  List<Widget> _buildResultActions(
    BuildContext ctx,
    int betAmount,
    CoraRematchState? rematch,
    bool iVoted,
    bool iAccepted,
    bool isPending,
    bool isRefused,
    bool isExpired,
  ) {
    // Cas terminal : refusé ou expiré → seul "Quitter"
    if (isRefused || isExpired) {
      return [
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.neonRed,
            foregroundColor: Colors.white,
          ),
          child: const Text('Quitter', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ];
    }

    // Cas pending et j'ai déjà voté accept → juste attendre + bouton Annuler
    if (isPending && iAccepted) {
      return [
        TextButton(
          onPressed: () async {
            await _voteRematch(false);
          },
          child: Text('Annuler ma revanche',
              style: TextStyle(color: AppColors.neonRed)),
        ),
      ];
    }

    // Cas pending mais quelqu'un d'autre a proposé → Refuser + Accepter
    if (isPending && !iVoted) {
      return [
        TextButton(
          onPressed: () async {
            await _voteRematch(false);
          },
          child: Text('Refuser', style: TextStyle(color: AppColors.neonRed)),
        ),
        Consumer<WalletProvider>(
          builder: (_, w, __) {
            final canReplay = w.coins >= betAmount * 2;
            return ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: canReplay ? () async => await _voteRematch(true) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                disabledBackgroundColor: AppColors.bgElevated,
                disabledForegroundColor: AppColors.textMuted,
              ),
              label: Text(canReplay ? 'Accepter' : 'Solde insuffisant',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            );
          },
        ),
      ];
    }

    // Cas initial (pas encore de rematch demandé) → Quitter + Rejouer
    return [
      TextButton(
        onPressed: () { Navigator.pop(ctx); Navigator.pop(context); },
        child: Text(AppLocalizations.of(context)!.gameQuit,
            style: TextStyle(color: AppColors.neonRed, fontWeight: FontWeight.w700)),
      ),
      Consumer<WalletProvider>(
        builder: (_, w, __) {
          final canReplay = w.coins >= betAmount * 2;
          return ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: canReplay ? () async => await _voteRematch(true) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: AppColors.bgDark,
              disabledBackgroundColor: AppColors.bgElevated,
              disabledForegroundColor: AppColors.textMuted,
            ),
            label: Text(
              canReplay ? 'Rejouer ($betAmount FCFA)' : 'Solde insuffisant',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          );
        },
      ),
    ];
  }

  /// Vote pour la revanche (accept=true ou refuse=false).
  /// Met à jour le state via realtime — le dialog se rebuild tout seul
  /// grâce au ValueListenableBuilder + _gameNotifier.
  Future<void> _voteRematch(bool accept) async {
    try {
      final res = await _service.requestRematch(widget.gameId, accept: accept);
      if (!mounted) return;
      // Si le serveur a finalisé immédiatement (ex: tous ont accepté en même temps),
      // l'event realtime UPDATE arrivera et on naviguera. Mais on peut aussi
      // déclencher la navigation tout de suite si la réponse contient new_game_id.
      if (res != null && res['status'] == 'accepted' && res['new_game_id'] != null) {
        _rematchNavigated = true;
        if (Navigator.canPop(context)) Navigator.pop(context); // close dialog
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CoraGameScreen(gameId: res['new_game_id'] as String),
          ),
        );
      } else if (res != null && res['status'] == 'refused' && !accept) {
        // J'ai refusé → ferme tout et retourne à l'écran principal
        if (Navigator.canPop(context)) Navigator.pop(context);
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur revanche : $e'),
          backgroundColor: AppColors.neonRed,
        ),
      );
    }
  }

  void _confirmExit() {
    if (_game!.gameState.isFinished) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(AppLocalizations.of(context)!.gameLeaveQuestion,
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Cette action sera considérée comme un forfait et tu perdras ta mise.\nConfirmer ?',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel,
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Forfait explicite côté serveur AVANT de naviguer hors de l'écran
              // pour que l'utilisateur voie immédiatement son solde mis à jour.
              // [Cora #6] marque le forfait fait → pas de re-forfait au dispose.
              _forfeitDone = true;
              try {
                await _service.forfeit(widget.gameId);
              } catch (_) {}
              if (!mounted) return;
              try { context.read<WalletProvider>().refresh(); } catch (_) {}
              if (mounted) Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.gameForfeit,
                style: TextStyle(color: AppColors.neonRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CORA DICE - Écran de jeu
// Plateau, dés animés, tour par tour, résultats
// ============================================================

import 'dart:async';
import 'dart:math';
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
import '../../../services/game_settings.dart';
import '../models/cora_models.dart';
import '../services/cora_service.dart';
import '../components/dice_animation.dart';

class CoraGameScreen extends StatefulWidget {
  final String gameId;

  const CoraGameScreen({super.key, required this.gameId});

  @override
  State<CoraGameScreen> createState() => _CoraGameScreenState();
}

class _CoraGameScreenState extends State<CoraGameScreen>
    with TickerProviderStateMixin {
  final CoraService _service = CoraService();
  CoraGame? _game;
  bool _isLoading = true;
  bool _isRolling = false;
  DiceRoll? _lastRoll;

  // Turn timer
  static const int _turnSeconds = 12;
  int _turnCountdown = _turnSeconds;
  Timer? _turnTimer;
  int _consecutiveTimeouts = 0;
  String? _lastTurnPlayerId; // to detect turn changes

  RealtimeChannel? _gameChannel;

  // Animations
  late AnimationController _diceController;
  late AnimationController _coraController;
  late AnimationController _sevenController;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _turnTimer?.cancel();
    _diceController.dispose();
    _coraController.dispose();
    _sevenController.dispose();
    if (_gameChannel != null) _service.unsubscribe(_gameChannel!);
    try { context.read<MatchesProvider>().resumePolling(); } catch (_) {}
    try { context.read<LiveScoreManager>().resumeTracking(); } catch (_) {}
    super.dispose();
  }

  Future<void> _loadGame() async {
    _game = await _service.getGame(widget.gameId);
    if (mounted) setState(() => _isLoading = false);
  }

  void _subscribeToGame() {
    _gameChannel = _service.subscribeGame(widget.gameId, (game) {
      if (mounted) setState(() => _game = game);

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

      // Si partie terminée, afficher résultat après 2s
      if (game.gameState.isFinished) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _showResultDialog();
        });
      }
    });
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
    if (_isLoading || _game == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen),
        ),
      );
    }

    final myId = _service.currentUserId;
    final me = myId != null ? _game!.gameState.players[myId] : null;
    final isMyTurn = _game!.gameState.currentTurn == myId;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
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
                  'Pot: ${_game!.potAmount} coins',
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
      _handleForfeit();
      return;
    }
    // Auto-roll biaisé vers les mauvais lancers
    _rollDice(forcedRoll: _generateBiasedRoll());
  }

  /// 65% mauvais (7 ou total faible), 35% bon (total élevé)
  DiceRoll _generateBiasedRoll() {
    final rng = Random();
    // Biais lié à la difficulté IA : Facile=75% bad, Moyen=55%, Difficile=25%
    final badChance = 1.0 - GameSettings.instance.aiBestMoveChance;
    if (rng.nextDouble() < badChance) {
      // Mauvais : 7 (perd des points) ou total bas
      const bad = [[1,6],[2,5],[3,4],[4,3],[5,2],[6,1],[1,2],[2,1],[1,3],[3,1],[2,2]];
      final pair = bad[rng.nextInt(bad.length)];
      return DiceRoll(dice1: pair[0], dice2: pair[1], timestamp: DateTime.now());
    } else {
      // Bon : total élevé
      const good = [[4,6],[6,4],[5,5],[5,6],[6,5],[6,6]];
      final pair = good[rng.nextInt(good.length)];
      return DiceRoll(dice1: pair[0], dice2: pair[1], timestamp: DateTime.now());
    }
  }

  void _handleForfeit() {
    _turnTimer?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.gameInactivityKicked),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _rollDice({DiceRoll? forcedRoll}) async {
    if (_isRolling) return; // Anti double-tap
    // Reset timeout counter quand le joueur joue manuellement
    if (forcedRoll == null) _consecutiveTimeouts = 0;
    setState(() => _isRolling = true);

    try {
      // Lancer les dés (ou utiliser un lancer forcé pour l'auto-play)
      final roll = forcedRoll ?? await _service.rollDice();

      // Animer
      _animateRoll(roll);

      // Soumettre au serveur
      await _service.submitRoll(gameId: widget.gameId, roll: roll);
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
    final isCancelled = result.contains('annulé') || result.contains('Cancelled');
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final autoTimer = Timer(Duration(seconds: 5), () {
          if (mounted) _coraAutoContinue(ctx);
        });
        return PopScope(
          onPopInvokedWithResult: (_, __) => autoTimer.cancel(),
          child: AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              Icon(isWinner ? Icons.emoji_events : Icons.info_outline,
                color: isWinner ? AppColors.neonYellow : AppColors.textSecondary, size: 32),
              SizedBox(width: 12),
              Text(isWinner ? 'Victoire !' : 'Partie terminée',
                style: TextStyle(color: isWinner ? AppColors.neonYellow : AppColors.textPrimary)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(result, textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
              if (isWinner) ...[
                SizedBox(height: 12),
                Text('+${_game!.gameState.coraCount == 1 ? _game!.potAmount * 2 : _game!.potAmount} coins',
                  style: TextStyle(color: AppColors.neonYellow, fontSize: 24, fontWeight: FontWeight.w900)),
              ],
              SizedBox(height: 8),
              Text(AppLocalizations.of(context)!.gameNextRound, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ]),
            actions: [
              TextButton(
                onPressed: () { autoTimer.cancel(); Navigator.pop(ctx); Navigator.pop(context); },
                child: Text(AppLocalizations.of(context)!.gameQuit, style: TextStyle(color: AppColors.neonRed))),
            ],
          ),
        );
      },
    );
  }

  Future<void> _coraAutoContinue(BuildContext ctx) async {
    if (!mounted) return;
    try {
      final result = await _service.autoContinue(widget.gameId);
      if (!mounted) return;
      try { Navigator.pop(ctx); } catch (_) {}
      if (result == 'ended') {
        Navigator.pop(context);
      } else {
        try { context.read<WalletProvider>().refresh(); } catch (_) {}
        await _loadGame();
      }
    } catch (_) {
      if (mounted) { try { Navigator.pop(ctx); } catch (_) {} Navigator.pop(context); }
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
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.gameForfeit,
                style: TextStyle(color: AppColors.neonRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

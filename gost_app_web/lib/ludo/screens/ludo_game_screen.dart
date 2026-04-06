// ============================================================
// LUDO MODULE - Game Screen
// Plateau Flame anime, de, pions, chat, sons, tour par tour
// Layout : Board en haut, barre [You] [Dice] [Com] en bas
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../models/ludo_models.dart';
import '../providers/ludo_provider.dart';
import '../widgets/ludo_flame_widget.dart';
import '../widgets/ludo_dice_widget.dart';
import '../widgets/ludo_chat_widget.dart';
import '../game/ludo_board_colors.dart';
import '../services/audio_service.dart';
import '../services/vibration_service.dart';

class LudoGameScreen extends StatefulWidget {
  final String gameId;

  const LudoGameScreen({super.key, required this.gameId});

  @override
  State<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends State<LudoGameScreen> {
  int? _diceValue;
  bool _isRolling = false;
  bool _hasRolled = false;
  int? _selectedPawn;

  String _player1Name = 'Joueur 1';
  String _player2Name = 'Joueur 2';

  int _syncErrorCount = 0;
  static const int _maxSyncErrors = 3;

  // Turn timer – 8s par joueur
  static const int _turnSeconds = 8;
  int _turnCountdown = _turnSeconds;
  Timer? _turnTimer;
  int _consecutiveTimeouts = 0;
  bool _lastKnownIsMyTurn = false;

  @override
  void initState() {
    super.initState();
    _loadGame();
    AudioService.instance.startBackgroundMusic();
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    AudioService.instance.stopBackgroundMusic();
    super.dispose();
  }

  Future<void> _loadGame() async {
    try {
      final ludo = context.read<LudoProvider>();
      await ludo.loadGame(widget.gameId);
      if (mounted) _loadPlayerNames();
    } catch (e) {
      debugPrint('Erreur loadGame: $e');
    }
  }

  Future<void> _loadPlayerNames() async {
    try {
      final ludo = context.read<LudoProvider>();
      final game = ludo.currentGame;
      if (game == null) return;

      final p1 = await ludo.getPlayerProfile(game.player1);
      final p2 = await ludo.getPlayerProfile(game.player2);
      if (mounted) {
        setState(() {
          _player1Name = p1?.username ?? 'Joueur 1';
          _player2Name = p2?.username ?? 'Joueur 2';
        });
      }
    } catch (e) {
      debugPrint('Erreur loadPlayerNames: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text('Ludo'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: _confirmExit,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.chat_bubble_outline, size: 22),
            onPressed: () => _openChat(),
          ),
          Consumer<LudoProvider>(
            builder: (_, ludo, __) {
              final game = ludo.currentGame;
              if (game == null) return SizedBox();
              return Padding(
                padding: EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monetization_on,
                        color: AppColors.neonYellow, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Pot: ${game.betAmount * 2}',
                      style: TextStyle(
                        color: AppColors.neonYellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<LudoProvider>(
        builder: (context, ludo, _) {
          final game = ludo.currentGame;

          if (game == null) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.neonGreen),
            );
          }

          final myId = ludo.userId!;
          final isMyTurn = game.isMyTurn(myId);

          // Start/reset turn timer when turn changes
          if (isMyTurn != _lastKnownIsMyTurn) {
            _lastKnownIsMyTurn = isMyTurn;
            if (isMyTurn) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _startTurnTimer());
            } else {
              _turnTimer?.cancel();
            }
          }

          // Verifier si la partie est terminee
          if (game.status == GameStatus.finished) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showGameOverDialog(game, myId);
            });
          }

          if (game.status == GameStatus.cancelled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showCancelledDialog(game);
            });
          }

          final isPlayer1 = myId == game.player1;
          final myName = isPlayer1 ? _player1Name : _player2Name;
          final oppName = isPlayer1 ? _player2Name : _player1Name;
          final myColor = isPlayer1 ? LudoBoardColors.red : LudoBoardColors.blue;
          final oppColor = isPlayer1 ? LudoBoardColors.blue : LudoBoardColors.red;

          return Container(
            decoration: BoxDecoration(gradient: AppColors.bgGradient),
            child: Column(
              children: [
                // Status message
                _buildStatusMessage(isMyTurn),

                // Plateau Flame anime
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: LudoFlameWidget(
                      gameState: game.gameState,
                      player1Id: game.player1,
                      player2Id: game.player2,
                      currentPlayerId: isMyTurn ? myId : null,
                      selectedPawn: _selectedPawn,
                      diceValue: _hasRolled ? _diceValue : null,
                      onPawnTap: isMyTurn && _hasRolled
                          ? (pawnIndex) => _onPawnTap(pawnIndex, ludo)
                          : null,
                    ),
                  ),
                ),

                // Barre du bas : [You] [Dice] [Com]
                _buildBottomBar(ludo, game, myId, isMyTurn, myName, oppName, myColor, oppColor),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusMessage(bool isMyTurn) {
    String text;
    Color color;

    if (!isMyTurn) {
      text = 'Tour de l\'adversaire...';
      color = AppColors.neonOrange;
    } else if (!_hasRolled) {
      text = 'Appuyez sur le de pour lancer';
      color = AppColors.textPrimary;
    } else {
      text = 'Selectionnez un pion';
      color = AppColors.neonGreen;
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 6),
      color: color.withValues(alpha: 0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isMyTurn)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
              ),
            ),
          Text(text,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildBottomBar(
    LudoProvider ludo,
    LudoGame game,
    String myId,
    bool isMyTurn,
    String myName,
    String oppName,
    Color myColor,
    Color oppColor,
  ) {
    final canMove = _hasRolled &&
        _diceValue != null &&
        game.gameState.canMove(myId, _diceValue!);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // You chip
                Expanded(
                  child: _playerBottomChip(
                    'You',
                    myColor,
                    isActive: isMyTurn,
                  ),
                ),

                // Dice au centre
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: LudoDiceWidget(
                    value: _diceValue,
                    isRolling: _isRolling,
                    enabled: isMyTurn && !_hasRolled && !_isRolling,
                    onTap: isMyTurn && !_hasRolled ? () => _rollDice(ludo) : null,
                  ),
                ),

                // Com chip
                Expanded(
                  child: _playerBottomChip(
                    'Com',
                    oppColor,
                    isActive: !isMyTurn,
                  ),
                ),
              ],
            ),

            // Skip button si pas de mouvement possible
            if (isMyTurn && _hasRolled && !canMove)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _skipTurn(ludo),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonOrange,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('Aucun mouvement — Passer',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _playerBottomChip(String label, Color color, {required bool isActive}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.2) : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color : Colors.transparent,
          width: 2,
        ),
        boxShadow: isActive
            ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8)]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pin icon
          Icon(Icons.location_on, color: color, size: 20),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _openChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LudoChatWidget(gameId: widget.gameId),
    );
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    if (!mounted) return;
    setState(() => _turnCountdown = _turnSeconds);
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _turnCountdown--);
      if (_turnCountdown <= 0) {
        t.cancel();
        _onTurnTimeout();
      }
    });
  }

  void _onTurnTimeout() {
    if (!mounted) return;
    final ludo = context.read<LudoProvider>();
    final game = ludo.currentGame;
    if (game == null || game.status == GameStatus.finished) return;

    _consecutiveTimeouts++;
    if (_consecutiveTimeouts >= 4) {
      _handleForfeit();
      return;
    }
    // Auto-roll then auto-move
    if (!_hasRolled) {
      _rollDice(ludo);
    } else {
      // Auto-move first valid pawn
      _autoMove(ludo);
    }
  }

  void _autoMove(LudoProvider ludo) {
    final game = ludo.currentGame;
    final myId = ludo.userId;
    if (game == null || myId == null || _diceValue == null) return;

    // Collecter tous les pions valides
    final validPawns = <int>[];
    for (int i = 0; i < 4; i++) {
      if (game.gameState.canMovePawn(myId, i, _diceValue!)) {
        validPawns.add(i);
      }
    }
    if (validPawns.isEmpty) { _skipTurn(ludo); return; }

    // Biais 65% vers un pion sous-optimal (ordre inversé = moins avancé)
    final rng = Random();
    final shuffled = [...validPawns]..shuffle(rng);
    int chosen;
    if (shuffled.length > 1 && rng.nextDouble() < 0.65) {
      final worse = shuffled.sublist((shuffled.length / 2).ceil());
      chosen = worse[rng.nextInt(worse.length)];
    } else {
      chosen = shuffled[rng.nextInt(shuffled.length)];
    }
    _onPawnTap(chosen, ludo);
  }

  void _handleForfeit() {
    _turnTimer?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Trop d\'inactivité – tu as été exclu de la partie'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _rollDice(LudoProvider ludo) async {
    setState(() {
      _isRolling = true;
      _selectedPawn = null;
    });

    AudioService.instance.playDiceRoll();
    VibrationService.light();

    await Future.delayed(const Duration(milliseconds: 600));

    final value = ludo.rollDice();
    setState(() {
      _diceValue = value;
      _isRolling = false;
      _hasRolled = true;
    });

    final game = ludo.currentGame;
    if (game != null) {
      final myId = ludo.userId!;
      if (!game.gameState.canMove(myId, value)) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) _skipTurn(ludo);
      }
    }
  }

  void _onPawnTap(int pawnIndex, LudoProvider ludo) {
    final game = ludo.currentGame;
    final myId = ludo.userId;
    if (game == null || myId == null || _diceValue == null) return;

    if (!game.gameState.canMovePawn(myId, pawnIndex, _diceValue!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ce pion ne peut pas bouger'),
          duration: Duration(seconds: 1),
          backgroundColor: AppColors.neonRed,
        ),
      );
      return;
    }

    setState(() => _selectedPawn = pawnIndex);
    _executeMove(pawnIndex, ludo);
  }

  Future<void> _executeMove(int pawnIndex, LudoProvider ludo) async {
    final game = ludo.currentGame;
    final myId = ludo.userId;
    if (game == null || myId == null || _diceValue == null) return;

    final opponentIds = game.opponentsOf(myId);
    final moveResult = game.gameState.applyMove(myId, pawnIndex, _diceValue!, opponentIds);

    final success = await ludo.makeMove(pawnIndex, _diceValue!);

    if (success) {
      _syncErrorCount = 0;

      if (moveResult.captured) {
        AudioService.instance.playCapture();
        VibrationService.medium();
      }
      if (moveResult.won) {
        AudioService.instance.playWin();
        VibrationService.heavy();
      }

      setState(() {
        _hasRolled = false;
        _diceValue = null;
        _selectedPawn = null;
      });
    } else {
      _syncErrorCount++;
      if (_syncErrorCount >= _maxSyncErrors && mounted) {
        _showSystemErrorDialog(ludo);
      }
    }
  }

  Future<void> _skipTurn(LudoProvider ludo) async {
    await ludo.skipTurn();
    setState(() {
      _hasRolled = false;
      _diceValue = null;
      _selectedPawn = null;
    });
  }

  bool _gameOverShown = false;

  void _showGameOverDialog(LudoGame game, String myId) {
    if (_gameOverShown) return;
    _gameOverShown = true;

    final isWinner = game.winnerId == myId;
    final pot = game.betAmount * 2;

    if (isWinner) {
      AudioService.instance.playWin();
      VibrationService.heavy();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWinner ? Icons.emoji_events : Icons.sentiment_dissatisfied,
              size: 64,
              color: isWinner ? AppColors.neonYellow : AppColors.neonRed,
            ),
            SizedBox(height: 16),
            Text(
              isWinner ? 'Victoire !' : 'Defaite...',
              style: TextStyle(
                color: isWinner ? AppColors.neonGreen : AppColors.neonRed,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 12),
            if (isWinner) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.monetization_on,
                      color: AppColors.neonYellow, size: 24),
                  SizedBox(width: 6),
                  Text('+$pot coins',
                      style: TextStyle(
                          color: AppColors.neonYellow,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ] else ...[
              Text('-${game.betAmount} coins',
                  style: TextStyle(
                      color: AppColors.neonRed,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ],
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                final ludo = context.read<LudoProvider>();
                ludo.leaveGame();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Retour au lobby',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  void _showSystemErrorDialog(LudoProvider ludo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Probleme technique',
            style: TextStyle(color: AppColors.neonOrange)),
        content: Text(
            'Plusieurs erreurs de synchronisation detectees. '
            'Voulez-vous annuler la partie ? Les deux joueurs seront rembourses.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _syncErrorCount = 0;
            },
            child: Text('Reessayer',
                style: TextStyle(color: AppColors.neonGreen)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ludo.cancelGame();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonOrange,
              foregroundColor: Colors.white,
            ),
            child: Text('Annuler et rembourser'),
          ),
        ],
      ),
    );
  }

  bool _cancelledShown = false;

  void _showCancelledDialog(LudoGame game) {
    if (_cancelledShown) return;
    _cancelledShown = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 64, color: AppColors.neonOrange),
            SizedBox(height: 16),
            Text(
              'Partie annulee',
              style: TextStyle(
                color: AppColors.neonOrange,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'La partie a ete annulee en raison d\'un probleme technique. Vos mises ont ete remboursees.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.monetization_on,
                    color: AppColors.neonGreen, size: 24),
                SizedBox(width: 6),
                Text('+${game.betAmount} coins rembourses',
                    style: TextStyle(
                        color: AppColors.neonGreen,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                final ludo = context.read<LudoProvider>();
                ludo.leaveGame();
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Retour au lobby',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmExit() {
    final ludo = context.read<LudoProvider>();
    final game = ludo.currentGame;

    if (game == null || game.status != GameStatus.playing) {
      ludo.leaveGame();
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Quitter la partie ?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
            'Si vous quittez, vous perdrez la partie et votre mise.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Rester',
                style: TextStyle(color: AppColors.neonGreen)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ludo.abandonGame();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonRed,
              foregroundColor: Colors.white,
            ),
            child: Text('Abandonner'),
          ),
        ],
      ),
    );
  }
}

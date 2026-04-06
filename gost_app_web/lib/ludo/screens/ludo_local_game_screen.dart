// ============================================================
// LUDO MODULE - Local Game Screen
// Même UI que le mode en ligne, sans Supabase
// 2 ou 4 joueurs, tour par tour, timer 8s, auto-play
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../game/ludo_board_colors.dart';
import '../providers/local_ludo_provider.dart';
import '../widgets/ludo_flame_widget.dart';
import '../widgets/ludo_dice_widget.dart';
import '../services/audio_service.dart';
import '../services/vibration_service.dart';

class LudoLocalGameScreen extends StatefulWidget {
  final int playerCount;

  const LudoLocalGameScreen({super.key, required this.playerCount});

  @override
  State<LudoLocalGameScreen> createState() => _LudoLocalGameScreenState();
}

class _LudoLocalGameScreenState extends State<LudoLocalGameScreen> {
  bool _isRolling = false;
  int? _selectedPawn;

  // Turn timer – 8s par joueur
  static const int _turnSeconds = 8;
  int _turnCountdown = _turnSeconds;
  Timer? _turnTimer;
  int _consecutiveTimeouts = 0;
  String _lastKnownTurnPlayerId = '';

  bool _winnerShown = false;
  LocalLudoProvider? _gameRef;

  @override
  void initState() {
    super.initState();
    try {
      AudioService.instance.startBackgroundMusic();
    } catch (_) {}
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    try {
      AudioService.instance.stopBackgroundMusic();
    } catch (_) {}
    super.dispose();
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
    if (!mounted || _gameRef == null) return;
    final game = _gameRef!;
    if (game.winner != null) return;

    _consecutiveTimeouts++;
    if (_consecutiveTimeouts >= 4) {
      _handleForfeit();
      return;
    }

    if (!game.hasRolled) {
      _rollDice(game);
    } else {
      _autoMove(game);
    }
  }

  void _autoMove(LocalLudoProvider game) {
    final validPawns = <int>[];
    for (int i = 0; i < 4; i++) {
      if (game.canMovePawn(i)) validPawns.add(i);
    }
    if (validPawns.isEmpty) {
      game.rollDice(); // force next turn (no-move skip)
      _startTurnTimer();
      return;
    }

    final rng = Random();
    final shuffled = [...validPawns]..shuffle(rng);
    int chosen;
    if (shuffled.length > 1 && rng.nextDouble() < 0.65) {
      final worse = shuffled.sublist((shuffled.length / 2).ceil());
      chosen = worse[rng.nextInt(worse.length)];
    } else {
      chosen = shuffled[rng.nextInt(shuffled.length)];
    }
    _onPawnTap(chosen, game);
  }

  void _handleForfeit() {
    _turnTimer?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Trop d\'inactivité – joueur exclu de la partie'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
    _gameRef?.forfeit();
  }

  Future<void> _rollDice(LocalLudoProvider game) async {
    if (game.hasRolled || _isRolling) return;
    setState(() {
      _isRolling = true;
      _selectedPawn = null;
    });

    try {
      AudioService.instance.playDiceRoll();
      VibrationService.light();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 600));

    game.rollDice();
    setState(() => _isRolling = false);

    // Reset consecutive timeouts on manual roll
    _consecutiveTimeouts = 0;
    _startTurnTimer();
  }

  void _onPawnTap(int pawnIndex, LocalLudoProvider game) {
    if (!game.hasRolled) return;
    if (!game.canMovePawn(pawnIndex)) {
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
    _consecutiveTimeouts = 0;

    game.selectPawn(pawnIndex);
    game.movePawn();

    try {
      AudioService.instance.playPawnMove();
      VibrationService.light();
    } catch (_) {}

    setState(() => _selectedPawn = null);

    // Le provider a changé de tour – le timer redémarre au prochain build
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LocalLudoProvider(playerCount: widget.playerCount),
      builder: (providerContext, _) => _buildScaffold(providerContext),
    );
  }

  Widget _buildScaffold(BuildContext providerContext) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text('Ludo – ${widget.playerCount} joueurs'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: _confirmExit,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _confirmRestart,
          ),
        ],
      ),
      body: Consumer<LocalLudoProvider>(
        builder: (context, game, _) {
          _gameRef = game; // Stocker la ref pour les timers
          // Détecter changement de tour → redémarrer timer
          final currentId = game.currentPlayerId;
          if (currentId != _lastKnownTurnPlayerId) {
            _lastKnownTurnPlayerId = currentId;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && game.winner == null) _startTurnTimer();
            });
          }

          // Victoire
          if (game.winner != null && !_winnerShown) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showWinnerDialog(game);
            });
          }

          final gameState = game.toGameState();
          return Container(
            decoration: BoxDecoration(gradient: AppColors.bgGradient),
            child: Column(
              children: [
                // Barre de statut
                _buildStatusMessage(game),

                // Plateau Flame animé
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: LudoFlameWidget(
                      gameState: gameState,
                      playerIds: widget.playerCount == 2
                          ? const ['player1', 'player2']
                          : const ['player1', 'player2', 'player3', 'player4'],
                      currentPlayerId: game.currentPlayerId,
                      selectedPawn: _selectedPawn,
                      diceValue: game.hasRolled ? game.lastDice : null,
                      onPawnTap: game.hasRolled && !_isRolling
                          ? (i) => _onPawnTap(i, game)
                          : null,
                    ),
                  ),
                ),

                // Barre du bas
                _buildBottomBar(game),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusMessage(LocalLudoProvider game) {
    final Color color;
    final String text;

    if (!game.hasRolled) {
      color = AppColors.textPrimary;
      text = '${game.currentPlayerName} – Lancez le dé';
    } else {
      color = AppColors.neonGreen;
      text = '${game.currentPlayerName} – Sélectionnez un pion';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 6),
      color: color.withValues(alpha: 0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Compte à rebours
          SizedBox(
            width: 28,
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _turnCountdown / _turnSeconds,
                  strokeWidth: 3,
                  backgroundColor: Colors.white12,
                  color: _turnCountdown <= 3
                      ? AppColors.neonRed
                      : AppColors.neonGreen,
                ),
                Text(
                  '$_turnCountdown',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _turnCountdown <= 3
                        ? AppColors.neonRed
                        : AppColors.neonGreen,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10),
          Text(text,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildBottomBar(LocalLudoProvider game) {
    if (widget.playerCount == 2) {
      return _buildBottomBar2Players(game);
    } else {
      return _buildBottomBar4Players(game);
    }
  }

  Widget _buildBottomBar2Players(LocalLudoProvider game) {
    final isJ1Turn = game.currentTurn == PlayerColor.red ||
        game.currentTurn == PlayerColor.yellow;

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
        child: Row(
          children: [
            Expanded(
              child: _playerChip(
                'Joueur 1',
                LudoBoardColors.red,
                isActive: isJ1Turn,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: LudoDiceWidget(
                value: game.lastDice == 0 ? null : game.lastDice,
                isRolling: _isRolling,
                enabled: !game.hasRolled && !_isRolling,
                onTap: !game.hasRolled && !_isRolling
                    ? () => _rollDice(game)
                    : null,
              ),
            ),
            Expanded(
              child: _playerChip(
                'Joueur 2',
                LudoBoardColors.blue,
                isActive: !isJ1Turn,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar4Players(LocalLudoProvider game) {
    final colors4 = [
      LudoBoardColors.red,
      LudoBoardColors.green,
      LudoBoardColors.blue,
      LudoBoardColors.yellow,
    ];
    final colorEnums = [
      PlayerColor.red,
      PlayerColor.green,
      PlayerColor.blue,
      PlayerColor.yellow,
    ];

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
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (i) {
                final isActive = game.currentTurn == colorEnums[i];
                return _playerChipSmall(
                  'J${i + 1}',
                  colors4[i],
                  isActive: isActive,
                );
              }),
            ),
            SizedBox(height: 10),
            Center(
              child: LudoDiceWidget(
                value: game.lastDice == 0 ? null : game.lastDice,
                isRolling: _isRolling,
                enabled: !game.hasRolled && !_isRolling,
                onTap: !game.hasRolled && !_isRolling
                    ? () => _rollDice(game)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerChip(String label, Color color, {required bool isActive}) {
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

  Widget _playerChipSmall(String label, Color color, {required bool isActive}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.2) : AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : AppColors.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }

  void _showWinnerDialog(LocalLudoProvider game) {
    if (_winnerShown) return;
    _winnerShown = true;
    _turnTimer?.cancel();

    final winnerColor = game.winner!;
    final colorValue = _getColor(winnerColor);
    final winnerName = LocalLudoProvider.playerName(winnerColor, widget.playerCount);

    try {
      AudioService.instance.playWin();
      VibrationService.heavy();
    } catch (_) {}

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events, size: 64, color: colorValue),
            SizedBox(height: 16),
            Text(
              'Victoire !',
              style: TextStyle(
                color: AppColors.neonGreen,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 8),
            Text(
              winnerName,
              style: TextStyle(
                color: colorValue,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  child: Text('Quitter',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _winnerShown = false;
                    _gameRef?.resetGame();
                    setState(() {
                      _selectedPawn = null;
                      _isRolling = false;
                      _consecutiveTimeouts = 0;
                      _lastKnownTurnPlayerId = '';
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonGreen,
                    foregroundColor: AppColors.bgDark,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Rejouer',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getColor(PlayerColor color) {
    switch (color) {
      case PlayerColor.red:    return LudoBoardColors.red;
      case PlayerColor.green:  return LudoBoardColors.green;
      case PlayerColor.blue:   return LudoBoardColors.blue;
      case PlayerColor.yellow: return LudoBoardColors.yellow;
    }
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Quitter la partie ?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
            'La partie en cours sera perdue.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Rester',
                style: TextStyle(color: AppColors.neonGreen)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonRed,
              foregroundColor: Colors.white,
            ),
            child: Text('Quitter'),
          ),
        ],
      ),
    );
  }

  void _confirmRestart() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Recommencer ?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('La partie en cours sera réinitialisée.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _winnerShown = false;
              _gameRef?.resetGame();
              setState(() {
                _selectedPawn = null;
                _isRolling = false;
                _consecutiveTimeouts = 0;
                _lastKnownTurnPlayerId = '';
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: AppColors.bgDark,
            ),
            child: Text('Recommencer',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

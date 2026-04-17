// ============================================================
// Checkers – Écran de jeu (plateau interactif 8x8)
// ============================================================
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../providers/matches_provider.dart';
import '../../../services/live_score_manager.dart';
import '../../../services/game_settings.dart';
import '../models/checkers_models.dart';
import '../game/checkers_logic.dart';
import '../services/checkers_service.dart';

class CheckersGameScreen extends StatefulWidget {
  final CheckersRoom room;
  final PieceColor myColor;
  const CheckersGameScreen({super.key, required this.room, required this.myColor});
  @override
  State<CheckersGameScreen> createState() => _CheckersGameScreenState();
}

class _CheckersGameScreenState extends State<CheckersGameScreen>
    with SingleTickerProviderStateMixin {
  final CheckersService _service = CheckersService();
  late CheckersGameState _gameState;
  BoardPos? _selected;
  List<CheckerMove> _possibleMoves = [];
  bool _myTurn = false;
  bool _gameOver = false;
  late AnimationController _pulseCtrl;

  // Timer de tour : 8 secondes par joueur
  static const int _turnSeconds = 8;
  int _turnCountdown = _turnSeconds;
  Timer? _turnTimer;
  int _consecutiveTimeouts = 0;

  @override
  void initState() {
    super.initState();
    _gameState = CheckersGameState.initial();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _updateTurn();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try { context.read<MatchesProvider>().pausePolling(); } catch (_) {}
        try { context.read<LiveScoreManager>().pauseTracking(); } catch (_) {}
      }
    });

    // Écoute Supabase si multijoueur réel
    if (!widget.room.isAI && widget.room.guestId != null) {
      _service.subscribeToRoom(widget.room.id, (updated) {
        final state = updated.gameState;
        if (state != null && mounted) {
          setState(() {
            _gameState = state;
            _updateTurn();
          });
          // Détecter la fin de partie envoyée par l'adversaire (forfait)
          if (state.isGameOver && !_gameOver) {
            _handleGameOver(state);
          }
        }
      });
    }
  }

  void _updateTurn() {
    _myTurn = _gameState.currentTurn == widget.myColor;
    if (!_gameState.isGameOver) _startTurnTimer();
    if (!_myTurn && !_gameState.isGameOver && widget.room.isAI) _scheduleAIMove();
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
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
    if (_gameOver || _gameState.isGameOver) return;
    // En multi, ne gérer que mes propres timeouts. En IA, gérer les deux.
    if (!_myTurn && !widget.room.isAI) return;
    _consecutiveTimeouts++;
    if (_consecutiveTimeouts >= 4) {
      _handleForfeit();
      return;
    }
    // Jouer un coup automatique biaisé vers les mauvais déplacements
    final moves = CheckersLogic.getLegalMoves(_gameState.board, _gameState.currentTurn);
    if (moves.isNotEmpty) {
      _applyMove(_pickAutoMove(moves));
    }
  }

  void _handleForfeit() {
    if (_gameOver) return;
    _gameOver = true;
    _turnTimer?.cancel();
    try { context.read<WalletProvider>().refresh(); } catch (_) {}
    final isMultiplayer = !widget.room.isAI && widget.room.guestId != null;
    if (isMultiplayer) {
      final myId = _service.currentUserId ?? '';
      final winnerId = myId == widget.room.hostId ? widget.room.guestId : widget.room.hostId;
      final opponentColor = widget.myColor == PieceColor.red ? PieceColor.black : PieceColor.red;
      // Envoyer le game_state final pour que l'adversaire voit le résultat
      final forfeitState = CheckersGameState(
        board: _gameState.board,
        currentTurn: _gameState.currentTurn,
        isGameOver: true,
        winner: opponentColor,
        winnerUserId: winnerId,
        redCount: _gameState.redCount,
        blackCount: _gameState.blackCount,
      );
      _service.distributeWinnings(
        roomId: widget.room.id,
        winnerId: winnerId,
        hostId: widget.room.hostId,
        guestId: widget.room.guestId,
        pot: widget.room.betAmount * 2,
        finalState: forfeitState,
      );
    }
    try {
      context.read<PlayerProvider>().recordGameResult(
        gameType: 'checkers',
        result: 'loss',
        coinsChange: -widget.room.betAmount,
        isPractice: widget.room.isAI,
        opponentName: widget.room.guestUsername ?? 'IA',
      );
    } catch (_) {}
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _GameOverDialog(
          isWin: false, isDraw: false, prize: 0,
          onBack: () { Navigator.pop(context); Navigator.pop(context); },
        ),
      );
    }
  }

  /// Sélection biaisée : 65% vers les coups sous-optimaux, 35% aléatoire
  CheckerMove _pickAutoMove(List<CheckerMove> moves) {
    if (moves.length == 1) return moves.first;
    final rng = Random();
    final shuffled = [...moves]..shuffle(rng);
    final badChance = 1.0 - GameSettings.instance.aiBestMoveChance;
    if (shuffled.length > 2 && rng.nextDouble() < badChance) {
      final worse = shuffled.sublist((shuffled.length / 2).ceil());
      if (worse.isNotEmpty) return worse[rng.nextInt(worse.length)];
    }
    return shuffled[rng.nextInt(shuffled.length)];
  }

  void _scheduleAIMove() {
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _gameState.isGameOver) return;
      final aiColor = widget.myColor == PieceColor.red ? PieceColor.black : PieceColor.red;
      final move = CheckersLogic.getBestMove(_gameState, aiColor, depth: 3);
      if (move != null) _applyMove(move);
    });
  }

  void _onCellTap(int row, int col) {
    if (!_myTurn || _gameState.isGameOver) return;
    final piece = _gameState.board[row][col];
    final tappedPos = BoardPos(row, col);

    if (_selected == null) {
      if (piece?.color == widget.myColor) {
        final legal = CheckersLogic.getLegalMoves(_gameState.board, widget.myColor)
            .where((m) => m.from == tappedPos)
            .toList();
        setState(() { _selected = tappedPos; _possibleMoves = legal; });
      }
    } else {
      final move = _possibleMoves.firstWhere(
        (m) => m.to == tappedPos,
        orElse: () => CheckerMove(from: _selected!, to: _selected!),
      );
      if (move.to != _selected) {
        _consecutiveTimeouts = 0;
        _applyMove(move);
      } else if (piece?.color == widget.myColor) {
        final legal = CheckersLogic.getLegalMoves(_gameState.board, widget.myColor)
            .where((m) => m.from == tappedPos)
            .toList();
        setState(() { _selected = tappedPos; _possibleMoves = legal; });
      } else {
        setState(() { _selected = null; _possibleMoves = []; });
      }
    }
  }

  void _applyMove(CheckerMove move) {
    final newState = CheckersLogic.applyMove(_gameState, move);
    setState(() {
      _gameState = newState;
      _selected = null;
      _possibleMoves = [];
    });
    _updateTurn();

    if (!widget.room.isAI && widget.room.guestId != null) {
      _service.updateGameState(widget.room.id, newState);
    }

    if (newState.isGameOver) _handleGameOver(newState);
  }

  void _confirmExit() {
    if (_gameOver) {
      Navigator.pop(context);
      return;
    }
    final isMultiplayer = widget.room.guestId != null && widget.room.guestId != 'AI';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context)!.gameLeaveQuestion,
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          isMultiplayer
              ? 'Cette action sera considérée comme un forfait et tu perdras ta mise.\nConfirmer ?'
              : 'Abandonner la partie en cours ?\nTu perdras ta mise.',
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

  void _handleGameOver(CheckersGameState state) {
    if (_gameOver) return;
    _gameOver = true;
    try { context.read<WalletProvider>().refresh(); } catch (_) {}
    final uid = _service.currentUserId ?? '';
    final isWin = state.winner == widget.myColor;
    final isDraw = state.winner == null;

    if (widget.room.isAI) {
      if (isWin) _service.addCoins(widget.room.betAmount * 2);
    } else {
      String? winnerId;
      if (!isDraw) {
        winnerId = isWin ? uid
            : (uid == widget.room.hostId ? widget.room.guestId : widget.room.hostId);
      }
      _service.distributeWinnings(
        roomId: widget.room.id,
        winnerId: winnerId,
        hostId: widget.room.hostId,
        guestId: widget.room.guestId,
        pot: widget.room.betAmount * 2,
        finalState: state,
      );
    }

    // Enregistrer le résultat pour XP / stats
    try {
      context.read<PlayerProvider>().recordGameResult(
        gameType: 'checkers',
        result: isWin ? 'win' : (isDraw ? 'draw' : 'loss'),
        coinsChange: isWin ? widget.room.betAmount * 2 : -widget.room.betAmount,
        isPractice: widget.room.isAI,
        opponentName: widget.room.isAI ? 'IA' : widget.room.guestUsername,
      );
    } catch (_) {}

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GameOverDialog(
        isWin: isWin,
        isDraw: isDraw,
        prize: isWin ? widget.room.betAmount * 2 : 0,
        onBack: () { Navigator.pop(context); Navigator.pop(context); },
      ),
    );
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    _pulseCtrl.dispose();
    _service.unsubscribe();
    try { context.read<MatchesProvider>().resumePolling(); } catch (_) {}
    try { context.read<LiveScoreManager>().resumeTracking(); } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              const Spacer(),
              _buildBoard(),
              const Spacer(),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
            onPressed: () => _confirmExit(),
          ),
          Expanded(
            child: Column(children: [
              Text('DAMES',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary, letterSpacing: 2)),
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Text(
                  _gameState.isGameOver ? 'Partie terminée'
                      : (_myTurn ? '● Votre tour' : 'Tour adversaire'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _myTurn
                        ? Color.lerp(AppColors.neonGreen, Colors.white, _pulseCtrl.value * 0.3)!
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
          // Pot
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.neonYellow.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events, color: AppColors.neonYellow, size: 14),
              SizedBox(width: 4),
              Text('${widget.room.betAmount * 2}',
                  style: TextStyle(color: AppColors.neonYellow, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
          SizedBox(width: 8),
          // Countdown
          if (!_gameState.isGameOver)
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_turnCountdown <= 3
                    ? AppColors.neonRed
                    : _myTurn ? AppColors.neonGreen : AppColors.bgCard)
                    .withValues(alpha: 0.15),
                border: Border.all(
                  color: _turnCountdown <= 3
                      ? AppColors.neonRed
                      : _myTurn ? AppColors.neonGreen : AppColors.textMuted,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '$_turnCountdown',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _turnCountdown <= 3
                        ? AppColors.neonRed
                        : _myTurn ? AppColors.neonGreen : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    final boardSize = MediaQuery.of(context).size.width - 32;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      width: boardSize,
      height: boardSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.neonOrange.withValues(alpha: 0.5), width: 2),
        boxShadow: [BoxShadow(color: AppColors.neonOrange.withValues(alpha: 0.1), blurRadius: 16)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
          itemCount: 64,
          itemBuilder: (_, idx) => _buildCell(idx ~/ 8, idx % 8, boardSize / 8),
        ),
      ),
    );
  }

  Widget _buildCell(int row, int col, double size) {
    final isDark = (row + col) % 2 == 1;
    final piece = _gameState.board[row][col];
    final pos = BoardPos(row, col);
    final isSelected = _selected == pos;
    final isTarget = _possibleMoves.any((m) => m.to == pos);

    Color bg = isDark ? const Color(0xFF8B5E3C) : const Color(0xFFF0D9B5);
    if (isSelected) bg = AppColors.neonGreen.withValues(alpha: 0.55);
    if (isTarget && isDark) bg = AppColors.neonGreen.withValues(alpha: 0.35);

    return GestureDetector(
      onTap: () => _onCellTap(row, col),
      child: Container(
        color: bg,
        child: Center(
          child: isTarget && piece == null
              ? Container(
                  width: size * 0.28, height: size * 0.28,
                  decoration: BoxDecoration(color: AppColors.neonGreen, shape: BoxShape.circle),
                )
              : piece != null
                  ? _buildPiece(piece, size, isSelected)
                  : null,
        ),
      ),
    );
  }

  Widget _buildPiece(CheckerPiece piece, double size, bool isSelected) {
    final isRed = piece.color == PieceColor.red;
    final pieceColor = isRed ? Colors.red.shade700 : const Color(0xFF1A1A1A);
    final rimColor = isRed ? Colors.red.shade300 : Colors.grey.shade600;

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, child) => Transform.scale(
        scale: isSelected ? (0.88 + _pulseCtrl.value * 0.12) : 1.0,
        child: child,
      ),
      child: Container(
        width: size * 0.78, height: size * 0.78,
        decoration: BoxDecoration(
          color: pieceColor,
          shape: BoxShape.circle,
          border: Border.all(color: rimColor, width: 2),
          boxShadow: [const BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 2))],
        ),
        child: piece.isKing
            ? Center(child: Text('♛', style: TextStyle(fontSize: 14, color: Colors.amber)))
            : null,
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _PieceCounter(color: PieceColor.red, count: _gameState.redCount, myColor: widget.myColor),
          Container(width: 1, height: 40, color: AppColors.divider),
          _PieceCounter(color: PieceColor.black, count: _gameState.blackCount, myColor: widget.myColor),
        ],
      ),
    );
  }
}

class _PieceCounter extends StatelessWidget {
  final PieceColor color;
  final int count;
  final PieceColor myColor;
  const _PieceCounter({required this.color, required this.count, required this.myColor});

  @override
  Widget build(BuildContext context) {
    final isMe = color == myColor;
    final c = color == PieceColor.red ? Colors.red.shade400 : Colors.grey.shade400;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: isMe ? AppColors.neonGreen : Colors.transparent, width: 2),
        ),
      ),
      SizedBox(height: 4),
      Text('$count', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
      Text(isMe ? 'Vous' : 'Adv.', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
    ]);
  }
}

class _GameOverDialog extends StatelessWidget {
  final bool isWin, isDraw;
  final int prize;
  final VoidCallback onBack;
  const _GameOverDialog({required this.isWin, required this.isDraw, required this.prize, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final color = isDraw ? AppColors.neonOrange : (isWin ? AppColors.neonGreen : AppColors.neonRed);
    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(isDraw ? '🤝' : (isWin ? '🏆' : '😞'), style: TextStyle(fontSize: 52)),
        SizedBox(height: 12),
        Text(isDraw ? 'Égalité !' : (isWin ? 'Victoire !' : 'Défaite'),
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
        if (isWin) ...[
          SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.monetization_on, color: AppColors.neonYellow),
            SizedBox(width: 6),
            Text('+$prize coins',
                style: TextStyle(color: AppColors.neonYellow, fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
        ],
        SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onBack,
            style: ElevatedButton.styleFrom(
              backgroundColor: color, foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(AppLocalizations.of(context)!.gameBack, style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

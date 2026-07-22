// ============================================================
// Checkers – Écran de jeu (plateau interactif 8x8)
// ============================================================
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../services/audio_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
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
import '../../../widgets/connectivity_banner.dart';
import '../../../widgets/network_lost_overlay.dart';

class CheckersGameScreen extends StatefulWidget {
  final CheckersRoom room;
  final PieceColor myColor;
  const CheckersGameScreen(
      {super.key, required this.room, required this.myColor});

  /// [A2] Garde anti-empilement : vrai tant qu'un écran de partie
  /// Checkers est monté. La reprise de session (main.dart) ne
  /// re-navigue pas si une partie est déjà affichée (port du
  /// correctif Ludo F2).
  static bool isOnScreen = false;

  @override
  State<CheckersGameScreen> createState() => _CheckersGameScreenState();
}

class _CheckersGameScreenState extends State<CheckersGameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final CheckersService _service = CheckersService();
  late CheckersGameState _gameState;
  BoardPos? _selected;
  List<CheckerMove> _possibleMoves = [];
  bool _myTurn = false;
  bool _gameOver = false;
  // [A3] Verrou de clôture UNIQUE, posé avant tout await de fin de
  // partie et JAMAIS ré-armé : empêche forfait + game-over realtime
  // concurrents de re-déclencher distributeWinnings / re-rentrer.
  bool _endInFlight = false;
  bool _moving = false; // verrou anti double-clic pendant l'attente serveur
  BoardPos? _serverJumpFrom; // multi-capture en cours (envoyé par serveur)
  bool _reconnecting = false; // true pendant retry reseau
  DateTime? _opponentTurnStartedAt; // pour anti-AFK adversaire
  Timer? _afkCheckTimer;
  bool _claimingIdle = false;
  static const int _idleClaimSeconds = 90; // match serveur
  late AnimationController _pulseCtrl;

  // Timer de tour : 8 secondes par joueur
  static const int _turnSeconds = 8;
  int _turnCountdown = _turnSeconds;
  Timer? _turnTimer;
  int _consecutiveTimeouts = 0;
  // [A5] Auto-jeu au timeout : on GARDE le coup aléatoire, mais on
  // décompte. À _maxAutoPlays auto-jeux consécutifs SANS action
  // manuelle -> forfait. L'UI affiche les "cœurs" restants ; un coup
  // manuel recharge le compteur (joueur de nouveau actif).
  static const int _maxAutoPlays = 5;
  int _autoPlays = 0;

  // Fallback polling : si realtime ne livre pas (RLS, ws, ...), on re-fetch
  // la room toutes les 2 secondes pour ne pas rester bloque sur un coup
  // ou sur la fin de partie envoyee par l'adversaire.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initAudio();
    CheckersGameScreen.isOnScreen = true; // [A2]
    WidgetsBinding.instance.addObserver(this); // [A1]
    _gameState = CheckersGameState.initial();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _updateTurn();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          context.read<MatchesProvider>().pausePolling();
        } catch (_) {}
        try {
          context.read<LiveScoreManager>().pauseTracking();
        } catch (_) {}
      }
    });

    // Écoute Supabase si multijoueur réel
    if (!widget.room.isAI && widget.room.guestId != null) {
      _service.subscribeToRoom(widget.room.id, _handleRemoteRoomUpdate);
      // Fallback polling toutes les 2s au cas ou le realtime ne livre pas
      _pollTimer =
          Timer.periodic(const Duration(milliseconds: 1500), (_) async {
        if (!mounted || _gameOver) return;
        final fresh = await _service.getRoom(widget.room.id);
        if (fresh != null) _handleRemoteRoomUpdate(fresh);
      });
    }
  }

  Future<void> _refetchRoom() async {
    if (!mounted || _gameOver) return;
    try {
      final fresh = await _service.getRoom(widget.room.id);
      if (fresh != null) _handleRemoteRoomUpdate(fresh);
    } catch (_) {}
  }

  Future<void> _initAudio() async {
    await AudioService.instance.configureGame('checkers');
    AudioService.instance.startBackgroundMusic();
  }

  bool _boardEqual(List<List<CheckerPiece?>> a, List<List<CheckerPiece?>> b) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final pa = a[r][c];
        final pb = b[r][c];
        if (pa == null && pb == null) continue;
        if (pa == null || pb == null) return false;
        if (pa.color != pb.color || pa.type != pb.type) return false;
      }
    }
    return true;
  }

  void _handleRemoteRoomUpdate(CheckersRoom updated) {
    if (!mounted || _gameOver) return;
    final state = updated.gameState;
    if (state == null) return;

    final jumpFrom = updated.currentJumpFrom;
    final isMyTurn = state.currentTurn == widget.myColor;
    final turnChanged = state.currentTurn != _gameState.currentTurn;
    final boardChanged = !_boardEqual(state.board, _gameState.board);
    final gameOverChanged = state.isGameOver != _gameState.isGameOver;
    final jumpChanged = _serverJumpFrom != jumpFrom;
    final realChange =
        turnChanged || boardChanged || gameOverChanged || jumpChanged;

    if (!realChange) {
      // Polling tick sans changement : ne PAS toucher au selected/timer
      return;
    }

    setState(() {
      _gameState = state;
      _serverJumpFrom = jumpFrom;
      _moving = false;
      if (jumpFrom != null && isMyTurn) {
        _selected = jumpFrom;
        _possibleMoves =
            CheckersLogic.getLegalMoves(state.board, widget.myColor)
                .where((m) => m.from == jumpFrom)
                .toList();
      } else if (turnChanged || boardChanged) {
        // Tour a change ou board a change : reset selection
        _selected = null;
        _possibleMoves = [];
      }
    });

    // Restart timer SEULEMENT si le tour a vraiment change
    if (turnChanged) {
      _updateTurn();
      // Anti-AFK : reset timer adversaire
      if (!isMyTurn && !state.isGameOver) {
        _opponentTurnStartedAt = DateTime.now();
        _startAfkCheck();
      } else {
        _opponentTurnStartedAt = null;
        _afkCheckTimer?.cancel();
      }
    }

    if (state.isGameOver && !_gameOver) {
      AudioService.instance.playWin();
      _handleGameOver(state);
    }
  }

  void _updateTurn() {
    _myTurn = _gameState.currentTurn == widget.myColor;
    if (!_gameState.isGameOver) _startTurnTimer();
    // PROD : pas d'auto-play AI cote client. L'IA tourne via cron serveur
    // (ou via une RPC dediee qu'on declenche explicitement, jamais en
    // reaction passive a un Realtime update).
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    setState(() => _turnCountdown = _turnSeconds);
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _turnCountdown--);
      if (_turnCountdown <= 0) {
        t.cancel();
        _onTurnTimeout();
      }
    });
  }

  Future<void> _onTurnTimeout() async {
    if (_gameOver || _gameState.isGameOver) return;
    if (!_myTurn) return; // jamais agir pour l'autre joueur
    if (_moving) return; // un move est deja en cours d'envoi

    var legalMoves =
        CheckersLogic.getLegalMoves(_gameState.board, widget.myColor);
    if (_serverJumpFrom != null) {
      legalMoves = legalMoves.where((m) => m.from == _serverJumpFrom).toList();
    }
    if (legalMoves.isNotEmpty) {
      final randomMove = legalMoves[Random().nextInt(legalMoves.length)];
      _consecutiveTimeouts = 0;
      // [A5] Décompte des auto-jeux : à _maxAutoPlays consécutifs sans
      // coup manuel -> forfait (au lieu d'auto-jouer indéfiniment).
      setState(() => _autoPlays++);
      if (_autoPlays >= _maxAutoPlays) {
        _handleForfeit();
        return;
      }
      _applyMove(randomMove);
      return;
    }

    if (!widget.room.isAI && widget.room.guestId != null) {
      try {
        final r = await _service.registerTimeout(widget.room.id);
        if (r['forfeited'] == true) return;
      } catch (e) {
        debugPrint('[CHECKERS] registerTimeout error: $e');
      }
    } else {
      _consecutiveTimeouts++;
      if (_consecutiveTimeouts >= 4) _handleForfeit();
    }
  }

  Future<void> _handleForfeit() async {
    if (_endInFlight || _gameOver) return; // [A3]
    _endInFlight = true; // [A3] jamais ré-armé
    _gameOver = true;
    _turnTimer?.cancel();
    final isMultiplayer = !widget.room.isAI && widget.room.guestId != null;

    if (isMultiplayer) {
      final myId = _service.currentUserId ?? '';
      final winnerId =
          myId == widget.room.hostId ? widget.room.guestId : widget.room.hostId;
      final opponentColor =
          widget.myColor == PieceColor.red ? PieceColor.black : PieceColor.red;
      final forfeitState = CheckersGameState(
        board: _gameState.board,
        currentTurn: _gameState.currentTurn,
        isGameOver: true,
        winner: opponentColor,
        winnerUserId: winnerId,
        redCount: _gameState.redCount,
        blackCount: _gameState.blackCount,
      );
      try {
        await _service.distributeWinnings(
          roomId: widget.room.id,
          winnerId: winnerId,
          hostId: widget.room.hostId,
          guestId: widget.room.guestId,
          pot: widget.room.betAmount * 2,
          finalState: forfeitState,
        );
      } catch (e) {
        final msg = e.toString();
        final alreadyClosed = msg.contains('ROOM_NOT_PLAYING') ||
            msg.contains('ROOM_ALREADY_FINISHED') ||
            msg.contains('already finished');
        if (!alreadyClosed) {
          // [A3] Vraie erreur (réseau...) : on NE ré-arme PAS _gameOver/
          // _endInFlight (sinon forfait + game-over realtime se
          // re-déclenchent en boucle). La partie reste fermée localement ;
          // côté serveur, le cron timeout/cleanup gère l'abandon.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Erreur forfait : $e'),
              backgroundColor: AppColors.neonRed,
              duration: const Duration(seconds: 5),
            ));
          }
          return;
        }
        // [A3] ROOM_NOT_PLAYING/ALREADY_FINISHED = l'adversaire a déjà
        // clôturé : succès idempotent -> on continue vers l'écran de fin.
      }
    }

    try {
      await context.read<WalletProvider>().refresh();
    } catch (_) {} // [A7] solde à jour avant l'écran de fin
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
          isWin: false,
          isDraw: false,
          prize: 0,
          onBack: () {
            Navigator.of(context).pop(); // ferme le dialog
            if (Navigator.of(context).canPop()) {
              // [A11] anti over-pop / écran figé
              Navigator.of(context).pop(); // quitte l'écran de jeu
            }
          },
        ),
      );
    }
  }

  // _pickAutoMove + _scheduleAIMove supprimes : auto-play retire en V2 prod.
  // L'IA tourne uniquement en mode solo (`widget.room.isAI`) via les actions
  // explicites du joueur, pas en reaction passive aux Realtime updates.

  void _onCellTap(int row, int col) {
    if (!_myTurn || _gameState.isGameOver) return;
    if (_moving) return; // serveur en cours de validation, ignore les taps
    final piece = _gameState.board[row][col];
    final tappedPos = BoardPos(row, col);

    // Si multi-capture en cours cote serveur, seule la piece a current_jump_from
    // peut bouger. On force la selection sur cette case.
    if (_serverJumpFrom != null && tappedPos != _serverJumpFrom) {
      if (_selected == null && piece?.color == widget.myColor) {
        // Pas le bon pion — ignorer le tap au lieu de bloquer le serveur
        return;
      }
    }

    if (_selected == null) {
      if (piece?.color == widget.myColor) {
        final legal = _legalMovesFromHere(tappedPos);
        setState(() {
          _selected = tappedPos;
          _possibleMoves = legal;
        });
      }
    } else {
      final move = _possibleMoves.firstWhere(
        (m) => m.to == tappedPos,
        orElse: () => CheckerMove(from: _selected!, to: _selected!),
      );
      if (move.to != _selected) {
        _consecutiveTimeouts = 0;
        _autoPlays = 0; // [A5] coup manuel -> recharge les cœurs
        _applyMove(move);
      } else if (piece?.color == widget.myColor) {
        final legal = _legalMovesFromHere(tappedPos);
        setState(() {
          _selected = tappedPos;
          _possibleMoves = legal;
        });
      } else {
        setState(() {
          _selected = null;
          _possibleMoves = [];
        });
      }
    }
  }

  // Anti-AFK : verifie toutes les secondes si l'adversaire est inactif
  // depuis trop longtemps. Auto-reclame la victoire au seuil serveur (90s).
  void _startAfkCheck() {
    _afkCheckTimer?.cancel();
    _afkCheckTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted || _gameOver || _gameState.isGameOver) {
        t.cancel();
        return;
      }
      if (_opponentTurnStartedAt == null) {
        t.cancel();
        return;
      }
      final isMyTurn = _gameState.currentTurn == widget.myColor;
      if (isMyTurn) {
        t.cancel();
        return;
      }
      final elapsed =
          DateTime.now().difference(_opponentTurnStartedAt!).inSeconds;
      if (elapsed >= _idleClaimSeconds && !_claimingIdle) {
        t.cancel();
        await _claimIdleWin();
      } else if (mounted) {
        setState(() {}); // refresh banner countdown
      }
    });
  }

  Future<void> _claimIdleWin() async {
    if (_claimingIdle || _gameOver) return;
    setState(() => _claimingIdle = true);
    try {
      await _service.claimIdleWin(widget.room.id);
      // Le serveur a marque la room finished + paye. Le realtime va arriver
      // et declencher _handleGameOver.
    } catch (e) {
      debugPrint('[CHECKERS] claimIdleWin error: $e');
      if (mounted) setState(() => _claimingIdle = false);
    }
  }

  // Wrapper retry pour playMove : robustesse perte reseau.
  // Reessaie jusqu'a 8 fois avec backoff (1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s).
  // Affiche un indicateur 'reconnexion' pendant les retries.
  // Echoue uniquement si > 2 min sans reseau.
  Future<Map<String, dynamic>> _playMoveWithRetry({
    required int fromRow,
    required int fromCol,
    required int toRow,
    required int toCol,
  }) async {
    // S19 : un seul requestId pour tout le retry. L'idempotence serveur
    // (checkers_play_move via p_request_id) detecte les retries et ne
    // ré-applique pas un coup déjà exécuté.
    final reqId = const Uuid().v4();
    const delays = [1, 2, 4, 8, 16, 30, 30, 30];
    for (int attempt = 0; attempt < delays.length; attempt++) {
      try {
        final r = await _service.playMove(
          roomId: widget.room.id,
          fromRow: fromRow,
          fromCol: fromCol,
          toRow: toRow,
          toCol: toCol,
          requestId: reqId,
        );
        if (_reconnecting && mounted) {
          setState(() => _reconnecting = false);
        }
        return r;
      } catch (e) {
        final msg = e.toString();
        final isNetwork = msg.contains('SocketException') ||
            msg.contains('Failed host lookup') ||
            msg.contains('Network is unreachable') ||
            msg.contains('Connection timed out') ||
            msg.contains('Connection failed');
        if (!isNetwork) rethrow; // erreur metier serveur -> remonte
        if (mounted && !_reconnecting) {
          setState(() => _reconnecting = true);
        }
        if (attempt == delays.length - 1) rethrow;
        await Future.delayed(Duration(seconds: delays[attempt]));
        if (!mounted) rethrow;
      }
    }
    throw Exception('UNREACHABLE');
  }

  // Renvoie les moves legaux depuis tappedPos.
  // Si le serveur impose une multi-capture en cours, on filtre uniquement
  // les moves depuis _serverJumpFrom.
  List<CheckerMove> _legalMovesFromHere(BoardPos tappedPos) {
    final all = CheckersLogic.getLegalMoves(_gameState.board, widget.myColor);
    if (_serverJumpFrom != null) {
      return all.where((m) => m.from == _serverJumpFrom).toList();
    }
    return all.where((m) => m.from == tappedPos).toList();
  }

  Future<void> _applyMove(CheckerMove move) async {
    if (_moving) return; // anti double-click serveur-authoritative

    if (widget.room.isAI || widget.room.guestId == null) {
      // Mode AI/solo : le moteur reste local (pas d'argent reel impacte
      // par le multi-joueur). Le moteur SQL ne gere que le multi.
      final newState = CheckersLogic.applyMove(_gameState, move);
      AudioService.instance.playPieceMove();
      setState(() {
        _gameState = newState;
        _selected = null;
        _possibleMoves = [];
      });
      _updateTurn();
      if (newState.isGameOver) {
        AudioService.instance.playWin();
        _handleGameOver(newState);
      }
      return;
    }

    // MULTIJOUEUR : envoie au serveur. Pour multi-capture, decompose la chaine
    // en sauts individuels (le serveur valide 1 saut a la fois).
    setState(() {
      _moving = true;
    });
    try {
      if (move.captured.length <= 1) {
        await _playMoveWithRetry(
          fromRow: move.from.row,
          fromCol: move.from.col,
          toRow: move.to.row,
          toCol: move.to.col,
        );
      } else {
        BoardPos current = move.from;
        for (final cap in move.captured) {
          final landingR = 2 * cap.row - current.row;
          final landingC = 2 * cap.col - current.col;
          final r = await _playMoveWithRetry(
            fromRow: current.row,
            fromCol: current.col,
            toRow: landingR,
            toCol: landingC,
          );
          current = BoardPos(landingR, landingC);
          if (r['must_continue'] != true) break;
        }
      }
      _consecutiveTimeouts = 0;
      AudioService.instance.playPieceMove();
      if (mounted)
        setState(() {
          _moving = false;
        });
    } catch (e) {
      debugPrint('[CHECKERS] playMove error: $e');
      if (mounted) {
        setState(() {
          _moving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Coup invalide : $e'
              .replaceAll('PostgrestException(message: ', '')
              .replaceAll(',', '')),
          backgroundColor: AppColors.neonRed,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  void _confirmExit() {
    if (_gameOver) {
      Navigator.pop(context);
      return;
    }
    final isMultiplayer =
        widget.room.guestId != null && widget.room.guestId != 'AI';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context)!.gameLeaveQuestion,
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
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
              if (isMultiplayer) {
                // Forfait : declenche la fin de partie cote serveur (payout
                // adversaire) AVANT de quitter l'ecran.
                _handleForfeit();
              } else {
                Navigator.pop(context);
              }
            },
            child: Text(AppLocalizations.of(context)!.gameForfeit,
                style: TextStyle(
                    color: AppColors.neonRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleGameOver(CheckersGameState state) async {
    if (_endInFlight || _gameOver) return; // [A3] verrou unique partagé
    _endInFlight = true; // [A3] jamais ré-armé
    _gameOver = true;
    final uid = _service.currentUserId ?? '';
    final isWin = state.winner == widget.myColor;
    final isDraw = state.winner == null;

    // Distribution treasury (multi ET solo IA passent par les memes RPCs).
    // Seul cas ou on n'appelle pas le RPC : si la room est deja 'finished'
    // (l'autre joueur l'a deja cloturee, on est juste informe via realtime).
    final shouldDistribute =
        !widget.room.isAI || (widget.room.isAI && widget.room.betAmount > 0);

    if (shouldDistribute && uid.isNotEmpty) {
      // [A4] Fin multijoueur : le SERVEUR a déjà clôturé + payé
      // (checkers_play_move étape 21 / timeout / claim_idle_win). Les
      // 2 clients appelaient checkers_finish_game -> redondant et
      // fragile (double-crédit évité seulement par idempotence serveur).
      // On ne distribue plus côté client en multi. On garde uniquement :
      //  - IA solo gagnante (aucun settlement serveur),
      //  - match nul multi (play_move ne rembourse pas les nuls),
      //  - IA perd (fermer la room).
      String? winnerId;
      if (!isDraw && widget.room.isAI) {
        winnerId = isWin ? uid : null; // pas de payout si IA gagne
      }
      try {
        if (widget.room.isAI && winnerId != null) {
          await _service.distributeWinnings(
            roomId: widget.room.id,
            winnerId: winnerId,
            hostId: widget.room.hostId,
            guestId: widget.room.guestId,
            pot: widget.room.betAmount * 2,
            finalState: state,
          );
        } else if (isDraw && !widget.room.isAI) {
          // Match nul multi : refund 100%
          await _service.distributeWinnings(
            roomId: widget.room.id,
            winnerId: null,
            hostId: widget.room.hostId,
            guestId: widget.room.guestId,
            pot: widget.room.betAmount * 2,
            finalState: state,
          );
        } else if (widget.room.isAI && !isWin && !isDraw) {
          // IA gagne : on doit marquer la room finished pour eviter
          // qu'elle reste 'playing'. Mais pas de payout.
          await Supabase.instance.client.from('checkers_rooms').update({
            'status': 'finished',
            'winner_id': null,
            'game_state': state.toJson(),
          }).eq('id', widget.room.id);
        }
      } catch (e) {
        // La RPC a peut-etre deja ete appelee par l'adversaire : ignore
        // ROOM_NOT_PLAYING. Pour le reste : afficher l'erreur.
        final msg = e.toString();
        final alreadyClosed = msg.contains('ROOM_NOT_PLAYING') ||
            msg.contains('ROOM_ALREADY_FINISHED') ||
            msg.contains('already finished');
        if (!alreadyClosed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Erreur distribution : $e'),
              backgroundColor: AppColors.neonRed,
              duration: const Duration(seconds: 5),
            ));
          }
        }
      }
    }

    try {
      await context.read<WalletProvider>().refresh();
    } catch (_) {} // [A7] solde à jour avant l'écran de fin

    // Enregistrer le résultat pour XP / stats
    try {
      context.read<PlayerProvider>().recordGameResult(
            gameType: 'checkers',
            result: isWin ? 'win' : (isDraw ? 'draw' : 'loss'),
            coinsChange:
                isWin ? widget.room.betAmount * 2 : -widget.room.betAmount,
            isPractice: widget.room.isAI,
            opponentName: widget.room.isAI ? 'IA' : widget.room.guestUsername,
          );
    } catch (_) {}

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GameOverDialog(
        isWin: isWin,
        isDraw: isDraw,
        // Affiche le gain NET (apres 10% commission caisse)
        prize: isWin ? (widget.room.betAmount * 2 * 0.90).floor() : 0,
        onBack: () {
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    CheckersGameScreen.isOnScreen = false; // [A2]
    WidgetsBinding.instance.removeObserver(this); // [A1]
    _turnTimer?.cancel();
    _pollTimer?.cancel();
    _afkCheckTimer?.cancel();
    _pulseCtrl.dispose();
    _service.unsubscribe();
    try {
      context.read<MatchesProvider>().resumePolling();
    } catch (_) {}
    try {
      context.read<LiveScoreManager>().resumeTracking();
    } catch (_) {}
    AudioService.instance.stopBackgroundMusic();
    super.dispose();
  }

  /// [A1] Cycle de vie : sans ça, le timer de tour 8 s continue de
  /// décompter en arrière-plan (appel, lock écran, switch app) et,
  /// au retour, _onTurnTimeout joue un coup ALÉATOIRE ou forfaite
  /// avec de l'argent réel. On coupe les timers en arrière-plan et
  /// on re-synchronise l'état autoritaire au retour.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_gameOver) return;
      if (!widget.room.isAI && widget.room.guestId != null) {
        _service.getRoom(widget.room.id).then((fresh) {
          if (fresh != null && mounted) _handleRemoteRoomUpdate(fresh);
        });
        _pollTimer?.cancel();
        _pollTimer =
            Timer.periodic(const Duration(milliseconds: 1500), (_) async {
          if (!mounted || _gameOver) return;
          final fresh = await _service.getRoom(widget.room.id);
          if (fresh != null) _handleRemoteRoomUpdate(fresh);
        });
      }
      // Repart d'un compte à rebours plein (jamais d'expiration
      // instantanée au retour) si c'est mon tour.
      if (!_gameState.isGameOver && _myTurn) _startTurnTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _turnTimer?.cancel();
      _pollTimer?.cancel();
      _afkCheckTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _gameOver,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExit();
      },
      child: NetworkLostOverlay(
        onRetry: _refetchRoom,
        child: Scaffold(
          // Page perte réseau IDENTITAIRE DAMES (rendue dans l'écran Dames
          // uniquement ; le filet global main.dart est neutre).
          body: _reconnecting
              ? const _CheckersNetworkView()
              : Container(
                  decoration: BoxDecoration(gradient: AppColors.bgGradient),
                  child: Stack(
                    children: [
                      // Halos neon ambiants — purement decoratifs, ne
                      // captent aucun geste, n'affectent aucune logique.
                      Positioned(
                        top: -60,
                        right: -40,
                        child: _ambientBlob(
                            AppColors.neonOrange.withValues(alpha: 1), 180),
                      ),
                      Positioned(
                        bottom: 40,
                        left: -50,
                        child: _ambientBlob(
                            AppColors.neonGreen.withValues(alpha: 1), 170),
                      ),
                      SafeArea(
                        child: Column(
                          children: [
                            _buildTopBar(),
                            const ConnectivityBanner(),
                            if (_reconnecting) _buildReconnectingBanner(),
                            if (_buildAfkRemainingSeconds() != null)
                              _buildAfkBanner(),
                            const Spacer(),
                            _buildBoard(),
                            const Spacer(),
                            _buildBottomBar(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  /// Tache de lumiere floue purement decorative (glassmorphism ambiant).
  Widget _ambientBlob(Color color, double size) {
    return IgnorePointer(
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
          ),
        ),
      ),
    );
  }

  // Renvoie les secondes restantes avant auto-claim (0..30), sinon null
  int? _buildAfkRemainingSeconds() {
    if (_opponentTurnStartedAt == null || _gameOver || _gameState.isGameOver)
      return null;
    final isMyTurn = _gameState.currentTurn == widget.myColor;
    if (isMyTurn) return null;
    final elapsed =
        DateTime.now().difference(_opponentTurnStartedAt!).inSeconds;
    final remaining = _idleClaimSeconds - elapsed;
    // On affiche le banner seulement les 30 dernieres secondes
    if (remaining > 30) return null;
    return remaining.clamp(0, _idleClaimSeconds);
  }

  Widget _buildAfkBanner() {
    final remaining = _buildAfkRemainingSeconds() ?? 0;
    final claiming = _claimingIdle;
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.neonOrange.withValues(alpha: 0.22),
                    AppColors.neonOrange.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.neonOrange.withValues(alpha: 0.55),
                    width: 1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonOrange.withValues(alpha: 0.25),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      claiming
                          ? Icons.emoji_events
                          : Icons.warning_amber_rounded,
                      color: AppColors.neonOrange,
                      size: 16),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      claiming
                          ? 'Reclamation de la victoire...'
                          : 'Adversaire inactif. Victoire dans ${remaining}s.',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.neonOrange,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReconnectingBanner() {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.neonYellow.withValues(alpha: 0.22),
                    AppColors.neonYellow.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.neonYellow.withValues(alpha: 0.55),
                    width: 1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonYellow.withValues(alpha: 0.25),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.neonYellow),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Reconnexion au serveur...',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.neonYellow,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
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
              ShaderMask(
                shaderCallback: (r) => LinearGradient(
                  colors: [
                    AppColors.textPrimary,
                    AppColors.neonOrange.withValues(alpha: 0.9),
                  ],
                ).createShader(r),
                child: Text('DAMES',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 3)),
              ),
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Text(
                  _gameState.isGameOver
                      ? 'Partie terminée'
                      : (_myTurn ? '● Votre tour' : 'Tour adversaire'),
                  style: TextStyle(
                    fontSize: 12,
                    color: _myTurn
                        ? Color.lerp(AppColors.neonGreen, Colors.white,
                            _pulseCtrl.value * 0.3)!
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
          // Pot
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.neonYellow.withValues(alpha: 0.18),
                      AppColors.neonYellow.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.neonYellow.withValues(alpha: 0.45),
                      width: 0.9),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonYellow.withValues(alpha: 0.22),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.emoji_events,
                      color: AppColors.neonYellow, size: 14),
                  SizedBox(width: 4),
                  Text('${widget.room.betAmount * 2}',
                      style: TextStyle(
                          color: AppColors.neonYellow,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
          SizedBox(width: 8),
          // [A5] Cœurs : auto-jeux restants avant forfait
          if (!_gameState.isGameOver) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < _maxAutoPlays; i++)
                  AnimatedScale(
                    scale: i < (_maxAutoPlays - _autoPlays) ? 1.0 : 0.85,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      i < (_maxAutoPlays - _autoPlays)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 12,
                      color: i < (_maxAutoPlays - _autoPlays)
                          ? AppColors.neonRed
                          : AppColors.textMuted,
                    ),
                  ),
              ],
            ),
            SizedBox(width: 8),
          ],
          // Countdown
          if (!_gameState.isGameOver)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (_turnCountdown <= 3
                            ? AppColors.neonRed
                            : _myTurn
                                ? AppColors.neonGreen
                                : AppColors.bgCard)
                        .withValues(alpha: 0.28),
                    (_turnCountdown <= 3
                            ? AppColors.neonRed
                            : _myTurn
                                ? AppColors.neonGreen
                                : AppColors.bgCard)
                        .withValues(alpha: 0.08),
                  ],
                ),
                border: Border.all(
                  color: _turnCountdown <= 3
                      ? AppColors.neonRed
                      : _myTurn
                          ? AppColors.neonGreen
                          : AppColors.textMuted,
                  width: 2,
                ),
                boxShadow: [
                  if (_turnCountdown <= 3 || _myTurn)
                    BoxShadow(
                      color: (_turnCountdown <= 3
                              ? AppColors.neonRed
                              : AppColors.neonGreen)
                          .withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                ],
              ),
              child: Center(
                child: Text(
                  '$_turnCountdown',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _turnCountdown <= 3
                        ? AppColors.neonRed
                        : _myTurn
                            ? AppColors.neonGreen
                            : AppColors.textSecondary,
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
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF3A2000),
            const Color(0xFF7A4F00),
            const Color(0xFF3A2000),
          ],
        ),
        border: Border.all(
            color: AppColors.neonOrange.withValues(alpha: 0.55), width: 1.4),
        boxShadow: [
          BoxShadow(
              color: AppColors.neonOrange.withValues(alpha: 0.28),
              blurRadius: 26,
              spreadRadius: 1),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8),
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

    // Degrade premium calcule a partir de la meme couleur de base (bg),
    // pour un rendu "case en bois/onyx poli" sans changer la logique
    // isDark/isSelected/isTarget ci-dessus.
    final lightShade = Color.lerp(bg, Colors.white, 0.12)!;
    final darkShade = Color.lerp(bg, Colors.black, 0.18)!;

    return GestureDetector(
      onTap: () => _onCellTap(row, col),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [lightShade, bg, darkShade],
          ),
          border: isSelected
              ? Border.all(
                  color: AppColors.neonGreen.withValues(alpha: 0.9),
                  width: 2)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.neonGreen.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: isTarget && piece == null
              ? AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(
                    width: size * (0.24 + _pulseCtrl.value * 0.06),
                    height: size * (0.24 + _pulseCtrl.value * 0.06),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [
                        Color.lerp(
                            AppColors.neonGreen, Colors.white, 0.35)!,
                        AppColors.neonGreen,
                      ]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonGreen.withValues(alpha: 0.6),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
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
    final highlightColor =
        isRed ? Colors.red.shade200 : const Color(0xFF6A6A6A);

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, child) => Transform.scale(
        scale: isSelected ? (0.88 + _pulseCtrl.value * 0.12) : 1.0,
        child: child,
      ),
      child: Container(
        width: size * 0.78,
        height: size * 0.78,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 1.0,
            colors: [highlightColor, pieceColor, Colors.black],
            stops: const [0, 0.55, 1],
          ),
          shape: BoxShape.circle,
          border: Border.all(color: rimColor, width: 2),
          boxShadow: [
            const BoxShadow(
                color: Colors.black45, blurRadius: 6, offset: Offset(1, 3)),
            if (isSelected)
              BoxShadow(
                color: AppColors.neonGreen.withValues(alpha: 0.55),
                blurRadius: 12,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Fraisage 3D du jeton (rainures concentriques + cabochon)
            const Positioned.fill(
              child: CustomPaint(painter: _CheckerRidgePainter()),
            ),
            if (piece.isKing)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.3, -0.4),
                    colors: [
                      Color(0xFFFFF9E1),
                      Color(0xFFFFC107),
                      Color(0xFF9A6A00),
                    ],
                    stops: [0, 0.6, 1],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD600).withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                    const BoxShadow(
                        color: Colors.black45,
                        blurRadius: 3,
                        offset: Offset(0, 1)),
                  ],
                ),
                child: const Text('♛',
                    style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5A3D00),
                        fontWeight: FontWeight.w900)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _PieceCounter(
              color: PieceColor.red,
              count: _gameState.redCount,
              myColor: widget.myColor),
          Container(width: 1, height: 40, color: AppColors.divider),
          _PieceCounter(
              color: PieceColor.black,
              count: _gameState.blackCount,
              myColor: widget.myColor),
        ],
      ),
    );
  }
}

class _PieceCounter extends StatelessWidget {
  final PieceColor color;
  final int count;
  final PieceColor myColor;
  const _PieceCounter(
      {required this.color, required this.count, required this.myColor});

  @override
  Widget build(BuildContext context) {
    final isMe = color == myColor;
    final c =
        color == PieceColor.red ? Colors.red.shade400 : Colors.grey.shade400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? AppColors.neonGreen.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: isMe
            ? [
                BoxShadow(
                  color: AppColors.neonGreen.withValues(alpha: 0.25),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            gradient: RadialGradient(colors: [
              Color.lerp(c, Colors.white, 0.3)!,
              c,
            ]),
            shape: BoxShape.circle,
            border: Border.all(
                color: isMe ? AppColors.neonGreen : Colors.transparent,
                width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 2)),
            ],
          ),
        ),
        SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Text('$count',
              key: ValueKey(count),
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
        ),
        Text(isMe ? 'Vous' : 'Adv.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ]),
    );
  }
}

class _GameOverDialog extends StatelessWidget {
  final bool isWin, isDraw;
  final int prize;
  final VoidCallback onBack;
  const _GameOverDialog(
      {required this.isWin,
      required this.isDraw,
      required this.prize,
      required this.onBack});

  @override
  Widget build(BuildContext context) {
    final color = isDraw
        ? AppColors.neonOrange
        : (isWin ? AppColors.neonGreen : AppColors.neonRed);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.bgCard.withValues(alpha: 0.96),
                  AppColors.bgDark.withValues(alpha: 0.98),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 34),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    color.withValues(alpha: 0.35),
                    color.withValues(alpha: 0.05),
                  ]),
                  border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Center(
                  child: Text(isDraw ? '🤝' : (isWin ? '🏆' : '😞'),
                      style: TextStyle(fontSize: 46)),
                ),
              ),
              SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (r) => LinearGradient(
                  colors: [color, Color.lerp(color, Colors.white, 0.4)!],
                ).createShader(r),
                child: Text(
                    isDraw ? 'Égalité !' : (isWin ? 'Victoire !' : 'Défaite'),
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ),
              if (isWin) ...[
                SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.neonYellow.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.neonYellow.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.monetization_on,
                            color: AppColors.neonYellow),
                        SizedBox(width: 6),
                        Text('+$prize FCFA',
                            style: TextStyle(
                                color: AppColors.neonYellow,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                      ]),
                ),
              ],
              SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onBack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.black,
                    elevation: 6,
                    shadowColor: color.withValues(alpha: 0.6),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(AppLocalizations.of(context)!.gameBack,
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Page perte réseau IDENTITAIRE DAMES (rendue dans l'écran Dames
/// uniquement — le filet global main.dart est neutre). Emblème damier
/// + pions + état réseau ; la reconnexion est automatique (spinner).
class _CheckersNetworkView extends StatelessWidget {
  const _CheckersNetworkView();

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.neonOrange;
    return Container(
      decoration: BoxDecoration(gradient: AppColors.bgGradient),
      child: SafeArea(
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
                      // Damier 4x4 (identité Dames)
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.35),
                              width: 1.5),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: GridView.count(
                          crossAxisCount: 4,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (int i = 0; i < 16; i++)
                              Container(
                                color: ((i ~/ 4) + i) % 2 == 0
                                    ? AppColors.bgElevated
                                    : AppColors.bgCard,
                                child: (i == 5)
                                    ? Center(child: _Disc(AppColors.neonRed))
                                    : (i == 10)
                                        ? const Center(
                                            child: _Disc(Colors.white70))
                                        : null,
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
                          child: Icon(Icons.wifi_off_rounded,
                              size: 22, color: accent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'Connexion perdue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Reconnexion en cours… Ta partie de Dames est en '
                  'sécurité, tu reprends dès que le réseau revient.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: 26,
                  height: 26,
                  child:
                      CircularProgressIndicator(strokeWidth: 3, color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  final Color color;
  const _Disc(this.color);
  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26, width: 1),
        ),
      );
}

/// Fraisage 3D d'un jeton de dames : rainures concentriques gravées
/// (ombre + lumière) + cabochon central surélevé. Fonctionne sur pion
/// rouge comme noir (n'utilise que blanc/noir translucides).
class _CheckerRidgePainter extends CustomPainter {
  const _CheckerRidgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    // Rainure périphérique (groove) : trait sombre + trait clair décalé
    void groove(double rr) {
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.black.withValues(alpha: 0.32),
      );
      canvas.drawCircle(
        c,
        rr + 1.4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: 0.18),
      );
    }

    groove(r * 0.82);
    groove(r * 0.70);

    // Cabochon central surélevé (disque + liseret + reflet)
    canvas.drawCircle(
      c,
      r * 0.5,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.22),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.5)),
    );
    canvas.drawCircle(
      c,
      r * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withValues(alpha: 0.28),
    );
    // Reflet spéculaire haut-gauche sur le cabochon
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.5),
      3.9, // radians ≈ haut-gauche
      1.4,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  @override
  bool shouldRepaint(covariant _CheckerRidgePainter old) => false;
}
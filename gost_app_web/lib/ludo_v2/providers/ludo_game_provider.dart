// ============================================================
// LUDO V2 — Game Provider (PRODUCTION : debounce, server-lives, recovery)
// ============================================================

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../engine/ludo_engine.dart';
import '../models/ludo_models.dart';
import '../services/ludo_service.dart';
import '../../services/network_retry.dart';

class LudoV2GameProvider extends ChangeNotifier with WidgetsBindingObserver {
  final LudoV2Service _svc = LudoV2Service.instance;
  final _uuid = const Uuid();

  // ── State ──────────────────────────────────────────────
  LudoV2Game? _game;
  LudoV2Game? _previousGame;
  String? _error;
  bool _loading = false;
  bool _rolling = false;
  bool _moving = false;       // anti double-clic playMove
  bool _forfeiting = false;   // anti double-clic forfeit
  bool _observerAdded = false; // [F7] idempotence addObserver
  List<PawnMove> _playableMoves = [];

  // ── Timer + Vies serveur ───────────────────────────────
  RealtimeChannel? _gameChannel;
  Timer? _turnTimer;
  Timer? _countdownTimer;
  Timer? _idleClaimWatcher;   // surveille les adversaires AFK
  Timer? _pollTimer;          // fallback si realtime meurt
  String? _gameId;
  int _secondsLeft = 0;

  // ── Callbacks ──────────────────────────────────────────
  void Function(bool captured, bool won, bool extraTurn)? onMoveResult;
  void Function()? onTurnTimeout;
  void Function(String winnerId)? onGameOver;
  void Function()? onForfeitedByTimeouts;

  // ── Getters ────────────────────────────────────────────
  LudoV2Game? get game => _game;
  LudoV2Game? get previousGame => _previousGame;
  String? get error => _error;
  bool get loading => _loading;
  bool get rolling => _rolling;
  bool get moving => _moving;
  List<PawnMove> get playableMoves => _playableMoves;

  String get myId => _svc.currentUserId ?? '';
  bool get isMyTurn => _game?.isMyTurn(myId) ?? false;
  int get myColor => _game?.myColor(myId) ?? 0;
  List<int> get myPawns => _game?.myPawns(myId) ?? [0, 0, 0, 0];
  int get secondsLeft => _secondsLeft;
  int get timeoutsLeft {
    if (_game == null) return 3;
    final left = 3 - _game!.consecutiveTimeouts;
    if (left < 0) return 0;
    if (left > 3) return 3;
    return left;
  }

  // ── Lifecycle ──────────────────────────────────────────

  Future<void> loadGame(String gameId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _gameId = gameId;
      _game = await _svc.getGame(gameId);
      if (_game == null) throw Exception('Partie introuvable');

      _gameChannel?.let(_svc.unsubscribe);
      _gameChannel = _svc.subscribeGame(
        gameId,
        _onGameUpdate,
        onConnectionLost: _startPollingFallback,
      );
      // [F7] N'enregistrer l'observer qu'une seule fois (sinon
      // didChangeAppLifecycleState -> _refreshGame multiplié).
      if (!_observerAdded) {
        WidgetsBinding.instance.addObserver(this);
        _observerAdded = true;
      }

      _computePlayable();
      _startTurnTimer();
      _startIdleClaimWatcher();
    } catch (e) {
      _error = e.toString();
      debugPrint('[LUDO-V2-PROV] loadGame error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Au resume de l'app, on refetch l'etat (en cas de Realtime perdu).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _game != null && !_game!.isFinished) {
      _refreshGame();
    }
  }

  Future<void> _refreshGame() async {
    if (_game == null) return;
    try {
      final fresh = await _svc.getGame(_game!.id);
      if (fresh != null) _onGameUpdate(fresh);
    } catch (e) {
      debugPrint('[LUDO-V2-PROV] refresh error: $e');
    }
  }

  /// Polling 2s si le realtime meurt (onConnectionLost). Auto-stop fini.
  void _startPollingFallback() {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    debugPrint('[LUDO-V2-PROV] realtime down -> polling fallback ON');
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (_game == null || _game!.isFinished) {
        t.cancel();
        _pollTimer = null;
        return;
      }
      await _refreshGame();
    });
  }

  void _onGameUpdate(LudoV2Game updated) {
    // [F4] Garde monotone : rejeter un snapshot obsolète (réordonnancement
    // entre realtime / _refreshGame / polling 2s) sauf transition
    // terminale 'finished'. turn_number est strictement croissant côté
    // serveur. Sans ça, le plateau "recule" et des coups déjà joués
    // peuvent être rejoués.
    if (_game != null &&
        updated.turnNumber < _game!.turnNumber &&
        !updated.isFinished) {
      return;
    }
    _previousGame = _game;
    _game = updated;
    // [F4] NE PLUS réinitialiser _rolling/_moving ici. Ces flags
    // anti-double-action sont remis à false à la RÉSOLUTION du Future
    // RPC (finally de rollDice/playMove), pas sur un event realtime non
    // lié — sinon le timer d'auto-action peut repartir avant la
    // confirmation serveur => action dupliquée/divergente.
    _computePlayable();
    _startTurnTimer();
    _startIdleClaimWatcher();

    if (updated.isFinished && updated.winnerId != null) {
      onGameOver?.call(updated.winnerId!);
    }

    notifyListeners();
  }

  // ── Actions ────────────────────────────────────────────

  Future<int?> rollDice() async {
    if (_game == null || !isMyTurn || _game!.diceRolled) return null;
    if (_rolling) return null;

    _rolling = true;
    _error = null;
    notifyListeners();

    // [H2] reqId capturé UNE fois ; NetworkRetry rejoue les coupures
    // réseau transitoires avec le MÊME reqId -> le serveur (idempotence
    // ludo_v2_roll_dice via p_request_id) ne ré-applique pas. Les erreurs
    // métier (PostgrestException 4xx) remontent sans retry.
    final reqId = _uuid.v4();
    try {
      final dice = await NetworkRetry.run(
        () => _svc.rollDice(_game!.id, requestId: reqId),
        label: 'ludo_v2_roll_dice',
      );
      debugPrint('[LUDO-V2-PROV] Dice: $dice');
      return dice;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      // [F4] Reset à la résolution du RPC (succès OU échec), pas via realtime.
      _rolling = false;
      notifyListeners();
    }
  }

  Future<LudoV2MoveResult?> playMove(int pawnIndex) async {
    if (_game == null || !isMyTurn || !_game!.diceRolled) return null;
    if (_moving) return null;  // anti double-clic
    final isPlayable = _playableMoves.any((m) => m.pawnIndex == pawnIndex);
    if (!isPlayable) return null;

    _moving = true;
    _error = null;
    notifyListeners();

    // [H2] reqId stable + retry idempotent (cf rollDice).
    final reqId = _uuid.v4();
    try {
      final result = await NetworkRetry.run(
        () => _svc.playMove(_game!.id, pawnIndex, requestId: reqId),
        label: 'ludo_v2_play_move',
      );
      onMoveResult?.call(result.captured, result.won, result.extraTurn);
      return result;
    } catch (e) {
      final msg = e.toString();
      // Ignorer les race conditions de tour silencieusement (Realtime arrive)
      if (!msg.contains('NOT_YOUR_TURN') && !msg.contains('Pas votre tour')) {
        _error = msg;
      }
      debugPrint('[LUDO-V2-PROV] playMove error: $e');
      return null;
    } finally {
      // [F4] Reset à la résolution du RPC, pas via realtime.
      _moving = false;
      notifyListeners();
    }
  }

  Future<void> skipTurn() async {
    if (_game == null || !isMyTurn || !_game!.diceRolled) return;
    // [H2] reqId stable + retry idempotent (cf rollDice).
    final reqId = _uuid.v4();
    try {
      await NetworkRetry.run(
        () => _svc.skipTurn(_game!.id, requestId: reqId),
        label: 'ludo_v2_skip_turn',
      );
    } catch (e) {
      debugPrint('[LUDO-V2-PROV] skipTurn error: $e');
    }
  }

  Future<void> forfeit() async {
    if (_game == null || _game!.status != 'playing') return;
    if (_forfeiting) return;
    _forfeiting = true;
    // [H2] reqId stable + retry idempotent (cf rollDice).
    final reqId = _uuid.v4();
    try {
      await NetworkRetry.run(
        () => _svc.forfeit(_game!.id, requestId: reqId),
        label: 'ludo_v2_forfeit',
      );
    } catch (e) {
      debugPrint('[LUDO-V2-PROV] forfeit error: $e');
    } finally {
      _forfeiting = false;
    }
  }

  /// Reclame une victoire si l'adversaire courant est idle > 90s.
  Future<bool> claimIdleWin() async {
    if (_game == null || _game!.status != 'playing') return false;
    if (_game!.currentTurn == myId) return false;
    try {
      final r = await _svc.claimIdleWin(_game!.id);
      debugPrint('[LUDO-V2-PROV] claimIdleWin: $r');
      return r['claimed'] == true;
    } catch (e) {
      debugPrint('[LUDO-V2-PROV] claimIdleWin error: $e');
      return false;
    }
  }

  // ── Logique interne ────────────────────────────────────

  void _computePlayable() {
    if (_game == null || !isMyTurn || !_game!.diceRolled || _game!.diceValue == null) {
      _playableMoves = [];
      return;
    }

    _playableMoves = LudoEngine.getPlayableMoves(
      myPawns: myPawns,
      dice: _game!.diceValue!,
      myColor: myColor,
      allPawns: _game!.pawns,
      colorMap: _game!.colorMap,
      myId: myId,
    );

    if (_playableMoves.isEmpty && isMyTurn && _game!.diceRolled) {
      Future.delayed(const Duration(seconds: 2), () {
        if (_game != null && isMyTurn && _playableMoves.isEmpty &&
            _game!.diceRolled && !_moving) {
          skipTurn();
        }
      });
    }
  }

  static const int _turnDuration = 15;

  void _startTurnTimer() {
    _turnTimer?.cancel();
    _countdownTimer?.cancel();
    if (_game == null || !isMyTurn || _game!.isFinished) return;

    _secondsLeft = _turnDuration;
    notifyListeners();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        _secondsLeft--;
        notifyListeners();
      }
    });

    _turnTimer = Timer(const Duration(seconds: _turnDuration), () async {
      _countdownTimer?.cancel();
      _secondsLeft = 0;

      if (_game == null || !isMyTurn) return;

      onTurnTimeout?.call();

      // Enregistre le timeout serveur (qui forfait auto a 3 timeouts)
      try {
        final r = await _svc.registerTimeout(_game!.id);
        if (r['forfeited'] == true) {
          onForfeitedByTimeouts?.call();
          return;
        }
      } catch (e) {
        debugPrint('[LUDO-V2-PROV] registerTimeout error: $e');
      }

      // Auto-action : roll si pas roule, sinon move/skip
      if (!_game!.diceRolled) {
        final dice = await rollDice();
        if (dice != null) {
          await Future.delayed(const Duration(seconds: 1));
          if (_game != null && isMyTurn) {
            if (_playableMoves.isEmpty) {
              skipTurn();
            } else {
              playMove(_playableMoves.first.pawnIndex);
            }
          }
        }
      } else if (_playableMoves.isEmpty) {
        skipTurn();
      } else {
        playMove(_playableMoves.first.pawnIndex);
      }
    });
  }

  /// Surveille en local si l'adversaire courant est AFK > 90s
  /// pour proposer un bouton "claim idle win" dans l'UI.
  void _startIdleClaimWatcher() {
    _idleClaimWatcher?.cancel();
    if (_game == null || _game!.isFinished || isMyTurn) return;

    _idleClaimWatcher = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_game == null) return;
      notifyListeners();  // pour rafraichir l'UI qui peut afficher un bouton apres 90s
    });
  }

  /// Calcul cote client : depuis combien de temps le tour de l'adversaire dure.
  int adversaryIdleSeconds() {
    if (_game == null || isMyTurn) return 0;
    return DateTime.now().difference(_game!.turnStartedAt).inSeconds;
  }

  bool get canClaimIdleWin =>
      _game != null && !_game!.isFinished && !isMyTurn &&
      adversaryIdleSeconds() >= 90;

  // ── Cleanup ────────────────────────────────────────────

  @override
  void dispose() {
    if (_observerAdded) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAdded = false;
    }
    _turnTimer?.cancel();
    _countdownTimer?.cancel();
    _idleClaimWatcher?.cancel();
    _pollTimer?.cancel();
    if (_gameChannel != null) _svc.unsubscribe(_gameChannel!);
    super.dispose();
  }
}

extension _NullSafe<T> on T? {
  void let(void Function(T) fn) {
    if (this != null) fn(this as T);
  }
}

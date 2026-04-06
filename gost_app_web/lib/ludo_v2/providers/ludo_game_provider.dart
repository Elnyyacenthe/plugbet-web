// ============================================================
// LUDO V2 — Game Provider (ChangeNotifier)
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../engine/ludo_engine.dart';
import '../models/ludo_models.dart';
import '../services/ludo_service.dart';

class LudoV2GameProvider extends ChangeNotifier {
  final LudoV2Service _svc = LudoV2Service.instance;

  // ── State ──────────────────────────────────────────────
  LudoV2Game? _game;
  LudoV2Game? _previousGame;
  String? _error;
  bool _loading = false;
  bool _rolling = false;
  List<PawnMove> _playableMoves = [];

  // ── Timer + Vies ───────────────────────────────────────
  RealtimeChannel? _gameChannel;
  Timer? _turnTimer;
  Timer? _countdownTimer;
  int _secondsLeft = 0;
  int _lives = 5; // 5 vies, à 0 = forfait auto

  // ── Callbacks ──────────────────────────────────────────
  void Function(bool captured, bool won, bool extraTurn)? onMoveResult;
  void Function()? onTurnTimeout;
  void Function(String winnerId)? onGameOver;

  // ── Getters ────────────────────────────────────────────
  LudoV2Game? get game => _game;
  LudoV2Game? get previousGame => _previousGame;
  String? get error => _error;
  bool get loading => _loading;
  bool get rolling => _rolling;
  List<PawnMove> get playableMoves => _playableMoves;

  String get myId => _svc.currentUserId ?? '';
  bool get isMyTurn => _game?.isMyTurn(myId) ?? false;
  int get myColor => _game?.myColor(myId) ?? 0;
  List<int> get myPawns => _game?.myPawns(myId) ?? [0, 0, 0, 0];
  int get secondsLeft => _secondsLeft;
  int get lives => _lives;

  // ── Lifecycle ──────────────────────────────────────────

  /// Charge une partie et s'abonne aux updates
  Future<void> loadGame(String gameId) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _game = await _svc.getGame(gameId);
      if (_game == null) throw Exception('Partie introuvable');

      // S'abonner au Realtime
      _gameChannel?.let(_svc.unsubscribe);
      _gameChannel = _svc.subscribeGame(gameId, _onGameUpdate);

      _computePlayable();
      _startTurnTimer();
    } catch (e) {
      _error = e.toString();
      debugPrint('[LUDO-V2-PROV] loadGame error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Callback Realtime : le jeu a changé
  void _onGameUpdate(LudoV2Game updated) {
    _previousGame = _game;
    _game = updated;
    _rolling = false;
    _computePlayable();
    _startTurnTimer();

    if (updated.isFinished && updated.winnerId != null) {
      onGameOver?.call(updated.winnerId!);
    }

    notifyListeners();
  }

  // ── Actions ────────────────────────────────────────────

  /// Lancer le dé (serveur uniquement)
  Future<int?> rollDice() async {
    if (_game == null || !isMyTurn || (_game!.diceRolled)) return null;

    _rolling = true;
    _error = null;
    notifyListeners();

    try {
      final dice = await _svc.rollDice(_game!.id);
      debugPrint('[LUDO-V2-PROV] Dice: $dice');

      // On attend l'update Realtime pour mettre à jour l'état
      // Mais on retourne le dé immédiatement pour l'animation
      return dice;
    } catch (e) {
      _error = e.toString();
      _rolling = false;
      notifyListeners();
      return null;
    }
  }

  /// Jouer un pion
  Future<LudoV2MoveResult?> playMove(int pawnIndex) async {
    if (_game == null || !isMyTurn || !_game!.diceRolled) return null;

    // Vérifier que ce pion est jouable
    final isPlayable = _playableMoves.any((m) => m.pawnIndex == pawnIndex);
    if (!isPlayable) return null;

    _error = null;
    try {
      final result = await _svc.playMove(_game!.id, pawnIndex);
      onMoveResult?.call(result.captured, result.won, result.extraTurn);
      return result;
    } catch (e) {
      // Ignorer "Pas votre tour" silencieusement (race condition Realtime)
      final msg = e.toString();
      if (!msg.contains('Pas votre tour')) {
        _error = msg;
        notifyListeners();
      }
      debugPrint('[LUDO-V2-PROV] playMove error: $e');
      return null;
    }
  }

  /// Passer le tour (automatique si aucun coup)
  Future<void> skipTurn() async {
    if (_game == null || !isMyTurn || !_game!.diceRolled) return;

    try {
      await _svc.skipTurn(_game!.id);
    } catch (e) {
      // Ignorer silencieusement les erreurs de tour
      debugPrint('[LUDO-V2-PROV] skipTurn error: $e');
    }
  }

  /// Forfait : le joueur quitte → l'adversaire gagne
  Future<void> forfeit() async {
    if (_game == null || _game!.status != 'playing') return;
    try {
      await _svc.forfeit(_game!.id);
      debugPrint('[LUDO-V2-PROV] Forfait envoyé');
    } catch (e) {
      debugPrint('[LUDO-V2-PROV] forfeit error: $e');
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

    // Auto-skip si aucun coup possible
    if (_playableMoves.isEmpty && isMyTurn && _game!.diceRolled) {
      Future.delayed(const Duration(seconds: 1), () {
        if (_game != null && isMyTurn && _playableMoves.isEmpty) {
          skipTurn();
        }
      });
    }

    // Auto-play si un seul coup possible
    // (optionnel, décommenter si tu veux)
    // if (_playableMoves.length == 1) {
    //   Future.delayed(const Duration(milliseconds: 500), () {
    //     playMove(_playableMoves.first.pawnIndex);
    //   });
    // }
  }

  static const int _turnDuration = 15;

  void _startTurnTimer() {
    _turnTimer?.cancel();
    _countdownTimer?.cancel();
    if (_game == null || !isMyTurn || _game!.isFinished) return;

    // Countdown visuel
    _secondsLeft = _turnDuration;
    notifyListeners();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        _secondsLeft--;
        notifyListeners();
      }
    });

    // Timeout après 15s
    _turnTimer = Timer(const Duration(seconds: _turnDuration), () {
      _countdownTimer?.cancel();
      _secondsLeft = 0;

      if (_game == null || !isMyTurn) return;

      // Perdre une vie
      _lives--;
      debugPrint('[LUDO-V2-PROV] Timeout! Vies restantes: $_lives');
      onTurnTimeout?.call();
      notifyListeners();

      // 0 vies = forfait automatique
      if (_lives <= 0) {
        debugPrint('[LUDO-V2-PROV] Plus de vies → forfait');
        forfeit();
        return;
      }

      // Auto-action
      if (!_game!.diceRolled) {
        rollDice().then((dice) {
          if (dice != null) {
            Future.delayed(const Duration(seconds: 1), () {
              if (_game != null && isMyTurn) {
                if (_playableMoves.isEmpty) {
                  skipTurn();
                } else {
                  playMove(_playableMoves.first.pawnIndex);
                }
              }
            });
          }
        });
      } else if (_playableMoves.isEmpty) {
        skipTurn();
      } else {
        playMove(_playableMoves.first.pawnIndex);
      }
    });
  }

  // ── Cleanup ────────────────────────────────────────────

  @override
  void dispose() {
    _turnTimer?.cancel();
    _countdownTimer?.cancel();
    if (_gameChannel != null) _svc.unsubscribe(_gameChannel!);
    super.dispose();
  }
}

/// Extension pour null-safe let
extension _NullSafe<T> on T? {
  void let(void Function(T) fn) {
    if (this != null) fn(this as T);
  }
}

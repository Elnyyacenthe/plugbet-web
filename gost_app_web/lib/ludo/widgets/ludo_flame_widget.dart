import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../models/ludo_models.dart';
import '../game/ludo_flame_game.dart';

class LudoFlameWidget extends StatefulWidget {
  final LudoGameState gameState;
  final List<String> playerIds;
  final String? currentPlayerId;
  final int? selectedPawn;
  final int? diceValue;
  final void Function(int pawnIndex)? onPawnTap;

  /// Rétro-compatibilité 2 joueurs
  final String? player1Id;
  final String? player2Id;

  const LudoFlameWidget({
    super.key,
    required this.gameState,
    this.playerIds = const [],
    this.player1Id,
    this.player2Id,
    this.currentPlayerId,
    this.selectedPawn,
    this.diceValue,
    this.onPawnTap,
  });

  List<String> get effectivePlayerIds {
    if (playerIds.isNotEmpty) return playerIds;
    return [
      if (player1Id != null) player1Id!,
      if (player2Id != null) player2Id!,
    ];
  }

  /// En 2 joueurs : joueur 1 = Red (index 0), joueur 2 = Blue (index 2)
  /// pour qu'ils soient en face l'un de l'autre sur le plateau
  Map<String, int> get playerIndexOverrides {
    final ids = effectivePlayerIds;
    if (ids.length == 2) {
      return {ids[0]: 0, ids[1]: 2}; // Red vs Blue (opposés)
    }
    return {}; // 4 joueurs : 0,1,2,3 par défaut
  }

  @override
  State<LudoFlameWidget> createState() => _LudoFlameWidgetState();
}

class _LudoFlameWidgetState extends State<LudoFlameWidget> {
  LudoFlameGame? _game;
  bool _gameReady = false;

  @override
  void didUpdateWidget(LudoFlameWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_game == null || !_gameReady) return;

    final stateChanged = !_arePawnsEqual(
      oldWidget.gameState.pawns,
      widget.gameState.pawns,
    );

    if (stateChanged) {
      _pushState(oldWidget.gameState);
    } else {
      _game!.updateGameState(
        newState: widget.gameState,
        playerIds: widget.effectivePlayerIds,
        activePlayerId: widget.currentPlayerId,
        dice: widget.diceValue,
        oldState: widget.gameState,
      );
    }

    if (oldWidget.selectedPawn != widget.selectedPawn) {
      _game!.setSelectedPawn(widget.selectedPawn);
    }

    if (widget.gameState.hasWon(widget.effectivePlayerIds.first) ||
        (widget.effectivePlayerIds.length > 1 &&
            widget.gameState.hasWon(widget.effectivePlayerIds[1]))) {
      _game!.triggerWinEffect();
    }
  }

  void _pushState(LudoGameState? oldState) {
    if (_game == null || !_gameReady) return;

    // Appliquer les overrides d'index pour 2 joueurs
    final overrides = widget.playerIndexOverrides;
    if (overrides.isNotEmpty) {
      for (final entry in overrides.entries) {
        _game!.setPlayerIndex(entry.key, entry.value);
      }
    }

    _game!.updateGameState(
      newState: widget.gameState,
      playerIds: widget.effectivePlayerIds,
      activePlayerId: widget.currentPlayerId,
      dice: widget.diceValue,
      oldState: oldState,
    );

    if (widget.selectedPawn != null) {
      _game!.setSelectedPawn(widget.selectedPawn);
    }
  }

  bool _arePawnsEqual(Map<String, List<int>> a, Map<String, List<int>> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final la = a[key]!;
      final lb = b[key]!;
      if (la.length != lb.length) return false;
      for (int i = 0; i < la.length; i++) {
        if (la[i] != lb[i]) return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, constraints.maxHeight);

        if (_game == null) {
          _game = LudoFlameGame(onPawnTap: widget.onPawnTap);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted && _game != null && _game!.isInitialized) {
                setState(() {
                  _gameReady = true;
                  _pushState(null);
                });
              } else if (mounted) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted && _game != null) {
                    setState(() {
                      _gameReady = true;
                      _pushState(null);
                    });
                  }
                });
              }
            });
          });
        }

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: ClipRect(
              child: _game != null
                  ? GameWidget(game: _game!)
                  : const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00E676),
                        strokeWidth: 2,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

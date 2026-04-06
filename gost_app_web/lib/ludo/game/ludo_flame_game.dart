import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../models/ludo_models.dart';
import 'components/board_component.dart';
import 'components/pawn_component.dart';
import 'effects/capture_effect.dart';
import 'effects/win_effect.dart';
import 'ludo_board_colors.dart';

class LudoFlameGame extends FlameGame with TapCallbacks {
  final void Function(int pawnIndex)? onPawnTap;

  late BoardComponent board;
  late double cellSize;

  // 4 groupes de pions — indexés par playerIndex (0=red,1=green,2=blue,3=yellow)
  late Map<String, List<PawnComponent>> _playerPawns; // playerId → 4 pions
  final Map<String, int> _playerIndexMap = {}; // playerId → playerIndex (0-3)

  String? currentPlayerId;
  int? diceValue;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  static const _colors = [
    LudoBoardColors.red,
    LudoBoardColors.green,
    LudoBoardColors.blue,
    LudoBoardColors.yellow,
  ];

  LudoFlameGame({this.onPawnTap});

  /// Force l'index couleur d'un joueur (utile en 2 joueurs : Red=0, Blue=2)
  void setPlayerIndex(String playerId, int index) {
    _playerIndexMap[playerId] = index;
  }

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!_initialized && size.x > 0) {
      _initBoard(size);
    }
  }

  void _initBoard(Vector2 gameSize) {
    _initialized = true;
    final boardSize = gameSize.x < gameSize.y ? gameSize.x : gameSize.y;
    cellSize = boardSize / 15;

    board = BoardComponent(cellSize: cellSize);
    add(board);

    _playerPawns = {};
  }

  /// Assure que les pions existent pour un joueur donné
  void _ensurePawns(String playerId, int playerIndex) {
    if (_playerPawns.containsKey(playerId)) return;

    _playerIndexMap[playerId] = playerIndex;
    final color = _colors[playerIndex.clamp(0, 3)];

    final pawns = List.generate(4, (i) {
      return PawnComponent(
        color: color,
        playerIndex: playerIndex,
        pawnIndex: i,
        cellSize: cellSize,
        onTap: onPawnTap,
        position: Vector2(7.5 * cellSize, 7.5 * cellSize),
      );
    });

    for (final p in pawns) {
      add(p);
    }
    _playerPawns[playerId] = pawns;
  }

  Vector2 cellToPixel(int row, int col) {
    return Vector2(col * cellSize, row * cellSize);
  }

  /// Met à jour l'état du jeu et anime les pions (supporte 2 ou 4 joueurs)
  void updateGameState({
    required LudoGameState newState,
    required List<String> playerIds,
    String? activePlayerId,
    int? dice,
    LudoGameState? oldState,
  }) {
    currentPlayerId = activePlayerId;
    diceValue = dice;

    // Créer les pions si nécessaire (utiliser l'override d'index si disponible)
    for (int idx = 0; idx < playerIds.length; idx++) {
      final pid = playerIds[idx];
      final pi = _playerIndexMap[pid] ?? idx;
      _ensurePawns(pid, pi);
    }

    // Animer chaque joueur
    for (int idx = 0; idx < playerIds.length; idx++) {
      final pid = playerIds[idx];
      final pi = _playerIndexMap[pid] ?? idx;
      final pawns = _playerPawns[pid]!;
      final newPawns = newState.playerPawns(pid);
      final oldPawns = oldState?.playerPawns(pid);

      for (int i = 0; i < 4; i++) {
        final newStep = newPawns[i];
        final oldStep = oldPawns?[i];
        final targetPos = _stepToPixel(newStep, pi, i);

        if (oldStep != null && oldStep != newStep && !pawns[i].isAnimating) {
          final waypoints = _buildWaypoints(oldStep, newStep, pi, i);
          if (waypoints.isNotEmpty) {
            pawns[i].animateAlongPath(waypoints);
          } else {
            pawns[i].teleportTo(targetPos);
          }
        } else if (oldStep == null) {
          pawns[i].teleportTo(targetPos);
        }
      }

      // Détecter les captures pour les autres joueurs
      for (int otherIdx = 0; otherIdx < playerIds.length; otherIdx++) {
        if (otherIdx == idx) continue;
        final otherId = playerIds[otherIdx];
        final otherPi = _playerIndexMap[otherId] ?? otherIdx;
        final otherOldPawns = oldState?.playerPawns(otherId);
        final otherNewPawns = newState.playerPawns(otherId);
        _detectCaptures(otherOldPawns, otherNewPawns, otherPi, otherId);
      }
    }

    _updateHighlights(newState, playerIds);
  }

  // Rétro-compatibilité pour le mode online (2 joueurs)
  void updateGameState2P({
    required LudoGameState newState,
    required String p1Id,
    required String p2Id,
    String? activePlayerId,
    int? dice,
    LudoGameState? oldState,
  }) {
    updateGameState(
      newState: newState,
      playerIds: [p1Id, p2Id],
      activePlayerId: activePlayerId,
      dice: dice,
      oldState: oldState,
    );
  }

  void _detectCaptures(List<int>? oldPawns, List<int> newPawns, int playerIndex, String playerId) {
    if (oldPawns == null) return;
    final pawns = _playerPawns[playerId];
    if (pawns == null) return;

    for (int i = 0; i < 4; i++) {
      if (oldPawns[i] > 0 && newPawns[i] == 0) {
        final pos = _stepToPixel(oldPawns[i], playerIndex, i);
        final color = _colors[playerIndex.clamp(0, 3)];
        add(CaptureEffect(effectPosition: pos + Vector2.all(cellSize / 2), color: color));
        pawns[i].teleportTo(_stepToPixel(0, playerIndex, i));
      }
    }
  }

  void triggerWinEffect() {
    add(WinEffect(boardSize: size));
  }

  void _updateHighlights(LudoGameState state, List<String> playerIds) {
    for (final pid in playerIds) {
      final pawns = _playerPawns[pid];
      if (pawns == null) continue;
      for (int i = 0; i < 4; i++) {
        final canMove = currentPlayerId == pid &&
            diceValue != null &&
            state.canMovePawn(pid, i, diceValue!);
        pawns[i].isHighlighted = canMove;
        pawns[i].isSelected = false;
      }
    }
  }

  void setSelectedPawn(int? index) {
    for (final pawns in _playerPawns.values) {
      for (final p in pawns) {
        p.isSelected = false;
      }
    }
    if (index != null && currentPlayerId != null) {
      final pawns = _playerPawns[currentPlayerId!];
      if (pawns != null && index < pawns.length) {
        pawns[index].isSelected = true;
      }
    }
  }

  Vector2 _stepToPixel(int step, int playerIndex, int pawnIndex) {
    final gridPos = LudoBoard.getPawnPositionByPlayer(step, playerIndex, pawnIndex: pawnIndex);
    return cellToPixel(gridPos[0], gridPos[1]);
  }

  List<Vector2> _buildWaypoints(int fromStep, int toStep, int playerIndex, int pawnIndex) {
    final waypoints = <Vector2>[];

    if (fromStep == 0 && toStep == 1) {
      waypoints.add(_stepToPixel(1, playerIndex, pawnIndex));
      return waypoints;
    }

    if (toStep == 0) {
      return [_stepToPixel(0, playerIndex, pawnIndex)];
    }

    final start = fromStep < 1 ? 1 : fromStep;
    if (toStep > start) {
      for (int s = start + 1; s <= toStep; s++) {
        waypoints.add(_stepToPixel(s, playerIndex, pawnIndex));
      }
    }

    return waypoints;
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (onPawnTap == null || currentPlayerId == null) return;

    final tapPos = event.localPosition;
    final pawns = _playerPawns[currentPlayerId!];
    if (pawns == null) return;

    for (int i = 0; i < 4; i++) {
      final pawn = pawns[i];
      final pawnCenter = pawn.position + pawn.size / 2;
      if (tapPos.distanceTo(pawnCenter) < cellSize * 0.6) {
        onPawnTap!(i);
        return;
      }
    }
  }
}

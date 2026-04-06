// ============================================================
// LUDO MODULE - Local Game Provider
// Gère le jeu local (2 ou 4 joueurs, sans Supabase)
// ============================================================

import 'dart:math';
import 'package:flutter/material.dart';
import '../game/ludo_board_colors.dart';
import '../models/ludo_models.dart';

enum PlayerColor { red, green, blue, yellow }

class LocalLudoProvider extends ChangeNotifier {
  final int playerCount;
  final Random _random = Random();

  // État du jeu
  Map<PlayerColor, List<int>> _pawns = {};
  PlayerColor _currentTurn = PlayerColor.red;
  int _lastDice = 0;
  bool _hasRolled = false;
  int? _selectedPawnIndex;
  PlayerColor? _winner;

  LocalLudoProvider({required this.playerCount}) {
    _initGame();
  }

  // Getters
  Map<PlayerColor, List<int>> get pawns => _pawns;
  PlayerColor get currentTurn => _currentTurn;
  int get lastDice => _lastDice;
  bool get hasRolled => _hasRolled;
  int? get selectedPawnIndex => _selectedPawnIndex;
  PlayerColor? get winner => _winner;

  bool get isPlayer1Turn {
    if (playerCount == 2) {
      return _currentTurn == PlayerColor.red || _currentTurn == PlayerColor.yellow;
    }
    // Pour 4 joueurs, alterner: red -> green -> blue -> yellow
    return _currentTurn == PlayerColor.red;
  }

  String get currentPlayerName {
    if (playerCount == 2) {
      return isPlayer1Turn ? 'Joueur 1' : 'Joueur 2';
    }
    // 4 joueurs
    return 'Joueur ${_currentTurn.index + 1}';
  }

  Color get currentPlayerColor {
    switch (_currentTurn) {
      case PlayerColor.red:
        return LudoBoardColors.red;
      case PlayerColor.green:
        return LudoBoardColors.green;
      case PlayerColor.blue:
        return LudoBoardColors.blue;
      case PlayerColor.yellow:
        return LudoBoardColors.yellow;
    }
  }

  void _initGame() {
    // Initialiser tous les pions à la position de départ (-1)
    _pawns = {
      PlayerColor.red: [-1, -1, -1, -1],
      PlayerColor.green: [-1, -1, -1, -1],
      PlayerColor.blue: [-1, -1, -1, -1],
      PlayerColor.yellow: [-1, -1, -1, -1],
    };
    _currentTurn = PlayerColor.red;
    _lastDice = 0;
    _hasRolled = false;
    _selectedPawnIndex = null;
    _winner = null;
  }

  /// Lancer le dé
  void rollDice() {
    if (_hasRolled) return;

    _lastDice = _random.nextInt(6) + 1;
    _hasRolled = true;
    _selectedPawnIndex = null;
    notifyListeners();

    // Si aucun mouvement possible, passer au joueur suivant
    if (!_hasValidMoves()) {
      Future.delayed(const Duration(milliseconds: 800), () {
        _nextTurn();
      });
    }
  }

  /// Vérifier s'il y a des mouvements valides
  bool _hasValidMoves() {
    final currentPawns = _pawns[_currentTurn]!;

    // Si 6, peut toujours sortir un pion ou bouger
    if (_lastDice == 6) return true;

    // Sinon, vérifier si au moins un pion est sorti
    return currentPawns.any((pos) => pos >= 0);
  }

  /// Sélectionner un pion
  void selectPawn(int index) {
    if (!_hasRolled) return;

    final currentPawns = _pawns[_currentTurn]!;
    final currentPos = currentPawns[index];

    // Vérifier si le mouvement est valide
    if (currentPos == -1 && _lastDice != 6) {
      // Pas de 6, ne peut pas sortir
      return;
    }

    _selectedPawnIndex = index;
    notifyListeners();
  }

  /// Déplacer le pion sélectionné
  void movePawn() {
    if (_selectedPawnIndex == null || !_hasRolled) return;

    final currentPawns = _pawns[_currentTurn]!;
    final currentPos = currentPawns[_selectedPawnIndex!];

    int newPos;
    if (currentPos == -1) {
      // Sortir le pion (case 0)
      newPos = 0;
    } else {
      // Avancer le pion
      newPos = currentPos + _lastDice;

      // Vérifier si atteint la case finale (57)
      if (newPos > 57) {
        // Dépassement, mouvement invalide
        _selectedPawnIndex = null;
        notifyListeners();
        return;
      }
    }

    // Mettre à jour la position
    _pawns[_currentTurn]![_selectedPawnIndex!] = newPos;

    // Vérifier victoire
    if (_checkWin()) {
      _winner = _currentTurn;
      notifyListeners();
      return;
    }

    // Si pas de 6, passer au suivant
    if (_lastDice != 6) {
      _nextTurn();
    } else {
      // 6 = rejouer
      _hasRolled = false;
      _selectedPawnIndex = null;
      notifyListeners();
    }
  }

  /// Vérifier si le joueur a gagné
  bool _checkWin() {
    final currentPawns = _pawns[_currentTurn]!;
    // Gagné si tous les pions sont à 57
    return currentPawns.every((pos) => pos == 57);
  }

  /// Passer au joueur suivant
  void _nextTurn() {
    if (playerCount == 2) {
      // Mode 2 joueurs: alterner entre les 2 groupes de couleurs
      if (_currentTurn == PlayerColor.red) {
        _currentTurn = PlayerColor.yellow;
      } else if (_currentTurn == PlayerColor.yellow) {
        _currentTurn = PlayerColor.green;
      } else if (_currentTurn == PlayerColor.green) {
        _currentTurn = PlayerColor.blue;
      } else {
        _currentTurn = PlayerColor.red;
      }
    } else {
      // Mode 4 joueurs: rotation red -> green -> blue -> yellow
      switch (_currentTurn) {
        case PlayerColor.red:
          _currentTurn = PlayerColor.green;
          break;
        case PlayerColor.green:
          _currentTurn = PlayerColor.blue;
          break;
        case PlayerColor.blue:
          _currentTurn = PlayerColor.yellow;
          break;
        case PlayerColor.yellow:
          _currentTurn = PlayerColor.red;
          break;
      }
    }

    _hasRolled = false;
    _selectedPawnIndex = null;
    _lastDice = 0;
    notifyListeners();
  }

  /// Réinitialiser le jeu
  void resetGame() {
    _initGame();
    notifyListeners();
  }

  // ─── Conversion vers LudoGameState (pour LudoFlameWidget) ─────────────────

  /// Identifiant string stable pour chaque couleur
  static String colorToId(PlayerColor color) {
    switch (color) {
      case PlayerColor.red:    return 'player1';
      case PlayerColor.green:  return 'player2';
      case PlayerColor.blue:   return 'player3';
      case PlayerColor.yellow: return 'player4';
    }
  }

  /// ID du joueur dont c'est le tour
  String get currentPlayerId => colorToId(_currentTurn);

  /// Noms fixes pour chaque joueur
  static String playerName(PlayerColor color, int playerCount) {
    if (playerCount == 2) {
      return (color == PlayerColor.red || color == PlayerColor.yellow)
          ? 'Joueur 1'
          : 'Joueur 2';
    }
    switch (color) {
      case PlayerColor.red:    return 'Joueur 1';
      case PlayerColor.green:  return 'Joueur 2';
      case PlayerColor.blue:   return 'Joueur 3';
      case PlayerColor.yellow: return 'Joueur 4';
    }
  }

  /// Vérifie si un pion donné peut bouger avec le dé actuel
  bool canMovePawn(int index) {
    if (!_hasRolled) return false;
    final pos = _pawns[_currentTurn]![index];
    if (pos == -1) return _lastDice == 6;
    final newPos = pos + _lastDice;
    return newPos <= 57;
  }

  /// Convertit l'état local en LudoGameState lisible par LudoFlameWidget
  /// Mapping de position: -1 → 0 (base), n → n+1 (plateau/goal)
  LudoGameState toGameState() {
    final Map<String, List<int>> statePawns = {};
    for (final entry in _pawns.entries) {
      statePawns[colorToId(entry.key)] =
          entry.value.map((p) => p < 0 ? 0 : p + 1).toList();
    }
    return LudoGameState(
      pawns: statePawns,
      lastDice: _lastDice,
      hasRolled: _hasRolled,
    );
  }

  /// Abandonner le jeu
  void forfeit() {
    // Le joueur adverse gagne
    if (playerCount == 2) {
      _winner = isPlayer1Turn ? PlayerColor.green : PlayerColor.red;
    } else {
      // En mode 4 joueurs, pas de gagnant par forfait
      _winner = null;
    }
    notifyListeners();
  }
}

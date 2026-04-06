// ============================================================
// LUDO MODULE - Provider (State Management)
// Gère : profil, lobby, challenges, game state
// ============================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ludo_models.dart';
import '../services/ludo_service.dart';

class LudoProvider extends ChangeNotifier {
  final LudoService _service;

  LudoProvider({LudoService? service}) : _service = service ?? LudoService();

  // --- État ---
  UserProfile? _profile;
  List<OnlinePlayer> _onlinePlayers = [];
  List<LudoChallenge> _pendingChallenges = [];
  LudoGame? _currentGame;
  bool _isInLobby = false;
  bool _isLoading = false;
  String? _error;

  // --- Rooms ---
  LudoRoom? _currentRoom;
  List<LudoRoom> _publicRooms = [];
  RealtimeChannel? _roomChannel;

  // --- Channels realtime ---
  RealtimeChannel? _lobbyChannel;
  RealtimeChannel? _challengeChannel;
  RealtimeChannel? _myChallengeChannel;
  RealtimeChannel? _gameChannel;
  Timer? _presenceTimer;

  // --- Getters ---
  UserProfile? get profile => _profile;
  int get coins => _profile?.coins ?? 0;
  List<OnlinePlayer> get onlinePlayers => _onlinePlayers;
  List<LudoChallenge> get pendingChallenges => _pendingChallenges;
  LudoGame? get currentGame => _currentGame;
  bool get isInLobby => _isInLobby;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _service.currentUserId != null;
  String? get userId => _service.currentUserId;

  // ============================================================
  // PROFIL
  // ============================================================

  /// Charger le profil utilisateur
  Future<void> loadProfile() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _profile = await _service.getMyProfile();
    } catch (e) {
      _error = 'Impossible de charger le profil';
      debugPrint('Erreur loadProfile: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Rafraîchir le profil (après un gain/perte)
  Future<void> refreshProfile() async {
    _profile = await _service.getMyProfile();
    notifyListeners();
  }

  /// Mettre à jour le pseudo
  Future<void> updateUsername(String username) async {
    await _service.updateUsername(username);
    await refreshProfile();
  }

  // ============================================================
  // LOBBY
  // ============================================================

  /// Rejoindre le lobby
  Future<void> joinLobby() async {
    if (_isInLobby) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _service.joinLobby();
      _isInLobby = true;

      // Charger les joueurs en ligne
      await _refreshOnlinePlayers();

      // Charger les défis en attente
      await _refreshPendingChallenges();

      // Écouter les changements du lobby
      _lobbyChannel = _service.subscribeLobby(() {
        _refreshOnlinePlayers();
      });

      // Écouter les nouveaux défis
      _challengeChannel = _service.subscribeChallenges((challenge) {
        _pendingChallenges.insert(0, challenge);
        notifyListeners();
      });

      // Écouter les réponses à mes défis
      _myChallengeChannel = _service.subscribeMyChallengeUpdates((challenge) {
        if (challenge.status == ChallengeStatus.accepted &&
            challenge.gameId != null) {
          // L'adversaire a accepté → lancer la partie
          _onChallengeAccepted(challenge.gameId!);
        }
        notifyListeners();
      });

      // Heartbeat de présence toutes les 30s
      _presenceTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _service.updatePresence(),
      );
    } catch (e) {
      _error = 'Erreur lobby: $e';
      debugPrint('Erreur joinLobby: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Quitter le lobby
  Future<void> leaveLobby() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;

    if (_lobbyChannel != null) _service.unsubscribe(_lobbyChannel!);
    if (_challengeChannel != null) _service.unsubscribe(_challengeChannel!);
    if (_myChallengeChannel != null) _service.unsubscribe(_myChallengeChannel!);

    _lobbyChannel = null;
    _challengeChannel = null;
    _myChallengeChannel = null;

    await _service.leaveLobby();
    _isInLobby = false;
    _onlinePlayers = [];
    _pendingChallenges = [];
    notifyListeners();
  }

  Future<void> _refreshOnlinePlayers() async {
    _onlinePlayers = await _service.getOnlinePlayers();
    notifyListeners();
  }

  Future<void> _refreshPendingChallenges() async {
    _pendingChallenges = await _service.getPendingChallenges();
    notifyListeners();
  }

  // ============================================================
  // CHALLENGES
  // ============================================================

  /// Envoyer un défi
  Future<LudoChallenge?> sendChallenge(String toUserId, int betAmount) async {
    if (_profile == null) return null;

    if (_profile!.coins < betAmount) {
      _error = 'Solde insuffisant ! Vous avez ${_profile!.coins} coins.';
      notifyListeners();
      return null;
    }

    _error = null;
    final challenge = await _service.sendChallenge(toUserId, betAmount);
    return challenge;
  }

  /// Accepter un défi
  Future<String?> acceptChallenge(String challengeId) async {
    try {
      _error = null;
      final gameId = await _service.acceptChallenge(challengeId);

      // Retirer le défi de la liste
      _pendingChallenges.removeWhere((c) => c.id == challengeId);

      // Charger la partie
      if (gameId != null) {
        await loadGame(gameId);
        await refreshProfile();
      }

      notifyListeners();
      return gameId;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Refuser un défi
  Future<void> declineChallenge(String challengeId) async {
    await _service.declineChallenge(challengeId);
    _pendingChallenges.removeWhere((c) => c.id == challengeId);
    notifyListeners();
  }

  /// Callback quand un de mes défis est accepté
  void Function(String gameId)? onGameStarted;

  void _onChallengeAccepted(String gameId) async {
    await loadGame(gameId);
    await refreshProfile();
    onGameStarted?.call(gameId);
  }

  // ============================================================
  // GAME
  // ============================================================

  /// Charger une partie
  Future<void> loadGame(String gameId) async {
    _currentGame = await _service.getGame(gameId);

    // S'abonner aux mises à jour en temps réel
    _gameChannel?.let((ch) => _service.unsubscribe(ch));
    _gameChannel = _service.subscribeGame(gameId, (updatedGame) {
      _currentGame = updatedGame;
      notifyListeners();
    });

    notifyListeners();
  }

  /// Lancer le dé
  int rollDice() {
    return LudoGameState.rollDice();
  }

  /// Jouer un mouvement
  Future<bool> makeMove(int pawnIndex, int diceValue) async {
    final game = _currentGame;
    final myId = userId;
    if (game == null || myId == null) return false;

    // Vérifier que c'est mon tour
    if (!game.isMyTurn(myId)) return false;

    final opponentIds = game.opponentsOf(myId);
    final state = game.gameState;

    // Vérifier mouvement valide
    if (!state.canMovePawn(myId, pawnIndex, diceValue)) return false;

    // Appliquer le mouvement
    final result = state.applyMove(myId, pawnIndex, diceValue, opponentIds);

    // Déterminer le prochain tour
    // On rejoue si : dé = 6, ou capture
    String nextTurn;
    if (result.won) {
      nextTurn = myId; // Pas important, la partie est finie
    } else if (result.rolledSix || result.captured) {
      nextTurn = myId; // Rejouer
    } else {
      nextTurn = _getNextPlayer(game, myId);
    }

    // Envoyer au serveur
    try {
      await _service.updateGameState(
        gameId: game.id,
        newState: result.newState,
        nextTurn: nextTurn,
        winnerId: result.won ? myId : null,
      );

      if (result.won) {
        await refreshProfile();
      }

      return true;
    } catch (e) {
      _error = 'Erreur de synchronisation: $e';
      notifyListeners();
      return false;
    }
  }

  /// Obtenir le joueur suivant dans l'ordre de rotation
  String _getNextPlayer(LudoGame game, String currentPlayerId) {
    final players = game.allPlayers;
    final currentIndex = players.indexOf(currentPlayerId);
    final nextIndex = (currentIndex + 1) % players.length;
    return players[nextIndex];
  }

  /// Passer son tour (quand aucun mouvement possible)
  Future<void> skipTurn() async {
    final game = _currentGame;
    final myId = userId;
    if (game == null || myId == null) return;

    final nextTurn = _getNextPlayer(game, myId);

    await _service.updateGameState(
      gameId: game.id,
      newState: game.gameState,
      nextTurn: nextTurn,
    );
  }

  /// Abandonner la partie
  Future<void> abandonGame() async {
    final game = _currentGame;
    if (game == null) return;

    try {
      await _service.abandonGame(game.id);
      await refreshProfile();
      _currentGame = null;
      notifyListeners();
    } catch (e) {
      _error = 'Erreur abandon: $e';
      notifyListeners();
    }
  }

  /// Annuler la partie (bug systeme) - rembourse les deux joueurs
  Future<void> cancelGame() async {
    final game = _currentGame;
    if (game == null) return;

    try {
      await _service.cancelGame(game.id);
      await refreshProfile();
      _currentGame = null;
      notifyListeners();
    } catch (e) {
      _error = 'Erreur annulation: $e';
      notifyListeners();
    }
  }

  /// Quitter la partie (après fin)
  void leaveGame() {
    if (_gameChannel != null) _service.unsubscribe(_gameChannel!);
    _gameChannel = null;
    _currentGame = null;
    notifyListeners();
  }

  /// Récupérer le profil d'un adversaire
  Future<UserProfile?> getPlayerProfile(String playerId) {
    return _service.getPlayerProfile(playerId);
  }

  // ============================================================
  // ROOMS
  // ============================================================

  LudoRoom? get currentRoom => _currentRoom;
  List<LudoRoom> get publicRooms => _publicRooms;

  /// Creer une salle, retourne le code ou null
  Future<String?> createRoom(
    int betAmount,
    bool isPrivate, {
    int playerCount = 2,
  }) async {
    if (_profile != null && _profile!.coins < betAmount) {
      _error = 'Solde insuffisant !';
      notifyListeners();
      return null;
    }

    _error = null;
    try {
      final result = await _service.createRoom(
        betAmount,
        isPrivate,
        playerCount: playerCount,
      );
      if (result == null) return null;

      final roomId = result['room_id'] as String;
      final code = result['code'] as String;

      _currentRoom = LudoRoom(
        id: roomId,
        code: code,
        hostId: userId!,
        playerCount: playerCount,
        betAmount: betAmount,
        isPrivate: isPrivate,
        createdAt: DateTime.now(),
      );

      // Ecouter quand un joueur rejoint
      _roomChannel = _service.subscribeRoom(roomId, (updatedRoom) {
        debugPrint('[LUDO-PROV] Room callback: status=${updatedRoom.status}, gameId=${updatedRoom.gameId}, isFull=${updatedRoom.isFull}, onGameStarted=${onGameStarted != null}');
        _currentRoom = updatedRoom;
        if (updatedRoom.gameId != null) {
          // Le jeu est créé → naviguer
          debugPrint('[LUDO-PROV] >>> GAME STARTED! gameId=${updatedRoom.gameId}');
          loadGame(updatedRoom.gameId!);
          refreshProfile();
          onGameStarted?.call(updatedRoom.gameId!);
        } else if (updatedRoom.isFull && updatedRoom.gameId == null) {
          // Room pleine mais pas de gameId → refetcher depuis DB
          debugPrint('[LUDO-PROV] Room pleine mais gameId null, refetch...');
          _refetchRoomGameId(roomId);
        }
        notifyListeners();
      });

      notifyListeners();
      return code;
    } catch (e) {

      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Fallback: refetcher le game_id depuis la DB si Realtime l'a raté
  Future<void> _refetchRoomGameId(String roomId) async {
    try {
      await Future.delayed(const Duration(seconds: 1));
      final rows = await Supabase.instance.client
          .from('ludo_rooms')
          .select('game_id, status')
          .eq('id', roomId)
          .limit(1);
      if (rows.isNotEmpty && rows.first['game_id'] != null) {
        final gameId = rows.first['game_id'] as String;
        debugPrint('[LUDO-PROV] Refetch OK: gameId=$gameId');
        await loadGame(gameId);
        await refreshProfile();
        onGameStarted?.call(gameId);
      }
    } catch (e) {
      debugPrint('[LUDO-PROV] Refetch error: $e');
    }
  }

  /// Rejoindre une salle par code, retourne le gameId ou null
  Future<String?> joinRoom(String code) async {
    _error = null;
    try {
      final gameId = await _service.joinRoom(code);
      if (gameId != null) {
        await loadGame(gameId);
        await refreshProfile();
      }
      notifyListeners();
      return gameId;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Charger les salles publiques
  Future<void> loadPublicRooms({int? playerCount}) async {
    _publicRooms = await _service.getPublicRooms(playerCount: playerCount);
    notifyListeners();
  }

  /// Quitter/supprimer une salle en attente
  void leaveRoom() {
    if (_roomChannel != null) {
      _service.unsubscribe(_roomChannel!);
      _roomChannel = null;
    }
    if (_currentRoom != null && _currentRoom!.status == 'waiting') {
      _service.deleteRoom(_currentRoom!.id);
    }
    _currentRoom = null;
    notifyListeners();
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  @override
  void dispose() {
    _presenceTimer?.cancel();
    if (_lobbyChannel != null) _service.unsubscribe(_lobbyChannel!);
    if (_challengeChannel != null) _service.unsubscribe(_challengeChannel!);
    if (_myChallengeChannel != null) _service.unsubscribe(_myChallengeChannel!);
    if (_gameChannel != null) _service.unsubscribe(_gameChannel!);
    if (_roomChannel != null) _service.unsubscribe(_roomChannel!);
    super.dispose();
  }
}

/// Extension utilitaire pour nullable
extension _NullableExt<T> on T? {
  void let(void Function(T) fn) {
    if (this != null) fn(this as T);
  }
}

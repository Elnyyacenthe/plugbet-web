// ============================================================
// Solitaire – Partie multijoueur tour par tour (plateau partagé)
// ============================================================
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/solitaire_models.dart';
import '../models/solitaire_room_models.dart';
import '../game/solitaire_logic.dart';
import '../services/solitaire_multiplayer_service.dart';

class SolitaireMultiplayerGameScreen extends StatefulWidget {
  final SolitaireRoom room;
  const SolitaireMultiplayerGameScreen({super.key, required this.room});
  @override
  State<SolitaireMultiplayerGameScreen> createState() =>
      _SolitaireMultiplayerGameScreenState();
}

class _SolitaireMultiplayerGameScreenState
    extends State<SolitaireMultiplayerGameScreen> {
  final SolitaireMultiplayerService _service = SolitaireMultiplayerService();

  late SolitaireState _state;
  late List<SolitaireRoomPlayer> _players;
  late int _currentTurnIndex;
  late int _myIndex;
  bool _gameEnded = false;
  bool _pushing = false; // évite double-push

  Timer? _timer;
  int _elapsed = 0;
  static const int _maxSec = 600; // 10 minutes

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    final uid = _service.currentUserId ?? '';

    // Charger l'état initial depuis le JSONB de la salle
    if (room.gameStateJson != null) {
      try {
        _state = SolitaireState.fromJson(room.gameStateJson!);
      } catch (_) {
        _state = SolitaireState.initial();
      }
    } else {
      _state = SolitaireState.initial();
    }

    _players = List.from(room.players);
    _currentTurnIndex = room.currentTurnIndex;
    _myIndex = _players.indexWhere((p) => p.id == uid);
    if (_myIndex < 0) _myIndex = 0;

    // Timer global
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      if (_elapsed >= _maxSec && !_gameEnded) _endGame();
    });

    // Realtime : recevoir les moves des autres joueurs
    _service.subscribeToRoom(room.id, _onRoomUpdate);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.unsubscribe();
    super.dispose();
  }

  // ── Mise à jour realtime ────────────────────────────────
  void _onRoomUpdate(SolitaireRoom updated) {
    if (!mounted || _gameEnded) return;
    if (updated.status == SolitaireRoomStatus.finished) {
      _endGame(fromRealtime: true, room: updated);
      return;
    }
    final gsJson = updated.gameStateJson;
    if (gsJson == null) return;
    try {
      final newState = SolitaireState.fromJson(gsJson);
      final newPlayers = updated.players;
      final newTurn = updated.currentTurnIndex;
      setState(() {
        _state = newState;
        _players = newPlayers;
        _currentTurnIndex = newTurn;
      });
    } catch (e) {
      debugPrint('[SOL-MULTI] onRoomUpdate parse: $e');
    }
  }

  // ── Appliquer une action ────────────────────────────────
  bool get _isMyTurn => _currentTurnIndex == _myIndex;

  /// Applique un état résultant d'une action et synchronise
  void _act(SolitaireState? newState) {
    if (newState == null || !_isMyTurn || _gameEnded || _pushing) return;

    // Détecter si une carte est allée en fondation (diff du total)
    final prevFoundationCount = _state.foundations.fold(0, (s, f) => s + f.length);
    final newFoundationCount = newState.foundations.fold(0, (s, f) => s + f.length);
    final addedToFoundation = newFoundationCount - prevFoundationCount;

    // Mettre à jour les scores localement
    final updatedPlayers = List<SolitaireRoomPlayer>.from(_players);
    if (addedToFoundation > 0 && _myIndex < updatedPlayers.length) {
      updatedPlayers[_myIndex] = updatedPlayers[_myIndex]
          .copyWith(score: updatedPlayers[_myIndex].score + addedToFoundation);
    }

    // Passer au joueur suivant
    final nextTurn = (_currentTurnIndex + 1) % updatedPlayers.length;

    setState(() {
      _state = newState;
      _players = updatedPlayers;
      _currentTurnIndex = nextTurn;
    });

    // Vérifier victoire
    if (newState.isWon) {
      _endGame();
      return;
    }

    // Synchroniser avec Supabase (sans bloquer l'UI)
    _pushState(updatedPlayers, nextTurn);
  }

  Future<void> _pushState(List<SolitaireRoomPlayer> players, int turnIndex) async {
    if (_pushing) return;
    _pushing = true;
    try {
      await _service.pushGameState(widget.room.id, _state, players, turnIndex);
    } finally {
      _pushing = false;
    }
  }

  // ── Fin de partie ───────────────────────────────────────
  void _endGame({bool fromRealtime = false, SolitaireRoom? room}) {
    if (_gameEnded) return;
    _gameEnded = true;
    _timer?.cancel();

    final finalPlayers = room?.players ?? _players;

    // Distribuer les gains (seulement si on est le premier à détecter la fin)
    if (!fromRealtime) {
      _service.distributeWinnings(widget.room.id, finalPlayers);
    }

    // Trier par score décroissant
    final sorted = List<SolitaireRoomPlayer>.from(finalPlayers)
      ..sort((a, b) => b.score.compareTo(a.score));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResultDialog(
        players: sorted,
        myId: _service.currentUserId ?? '',
        pot: widget.room.pot,
        onClose: () {
          Navigator.pop(context); // ferme dialog
          Navigator.pop(context); // retour lobby
        },
      ),
    );
  }

  String get _timeStr {
    final rem = (_maxSec - _elapsed).clamp(0, _maxSec);
    final m = rem ~/ 60;
    final s = rem % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ──────────────────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(children: [
            _topBar(),
            _scoreBar(),
            Expanded(child: _board()),
          ]),
        ),
      ),
    );
  }

  Widget _topBar() {
    final myTurn = _isMyTurn;
    final activePlayer = _currentTurnIndex < _players.length
        ? _players[_currentTurnIndex]
        : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: myTurn
                      ? AppColors.neonGreen.withValues(alpha: 0.15)
                      : AppColors.bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: myTurn
                        ? AppColors.neonGreen.withValues(alpha: 0.5)
                        : AppColors.divider,
                  ),
                ),
                child: Text(
                  myTurn ? '🎯 Ton tour !' : 'Tour de ${activePlayer?.username ?? '...'}',
                  style: TextStyle(
                    color: myTurn ? AppColors.neonGreen : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Timer
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _elapsed > _maxSec * 0.8
                ? AppColors.neonRed.withValues(alpha: 0.15)
                : AppColors.bgCard,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _timeStr,
            style: TextStyle(
              color: _elapsed > _maxSec * 0.8 ? AppColors.neonRed : AppColors.neonGreen,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _scoreBar() {
    return Container(
      height: 56,
      margin: EdgeInsets.symmetric(horizontal: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _players.length,
        itemBuilder: (context, i) {
          final p = _players[i];
          final isActive = i == _currentTurnIndex;
          final isMe = i == _myIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: EdgeInsets.only(right: 8),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.neonGreen.withValues(alpha: 0.12)
                  : AppColors.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? AppColors.neonGreen.withValues(alpha: 0.5)
                    : isMe
                        ? const Color(0xFF9C27B0).withValues(alpha: 0.4)
                        : AppColors.divider,
                width: isActive ? 1.5 : 0.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isMe
                        ? const Color(0xFF9C27B0).withValues(alpha: 0.3)
                        : AppColors.bgElevated,
                  ),
                  child: Center(
                    child: Text(
                      p.username.isNotEmpty ? p.username[0].toUpperCase() : '?',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                  ),
                ),
                SizedBox(width: 6),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMe ? 'Moi' : p.username,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    Text(
                      '${p.score} pts',
                      style: TextStyle(
                          fontSize: 10,
                          color: isActive ? AppColors.neonGreen : AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // PLATEAU (identique solo mais actif seulement si mon tour)
  // ──────────────────────────────────────────────────────────
  Widget _board() {
    return LayoutBuilder(builder: (ctx, box) {
      final cw = (box.maxWidth - 48) / 7;
      final ch = cw * 1.45;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Column(children: [
          SizedBox(height: 8),
          SizedBox(
            height: ch,
            child: Row(children: [
              _stock(cw, ch),
              SizedBox(width: 6),
              _waste(cw, ch),
              const Spacer(),
              for (int i = 0; i < 4; i++) ...[
                SizedBox(width: 6),
                _foundation(i, cw, ch),
              ],
            ]),
          ),
          SizedBox(height: 10),
          SizedBox(
            height: box.maxHeight - ch - 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(7, (col) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: _tableauCol(col, cw, ch),
                ),
              )),
            ),
          ),
        ]),
      );
    });
  }

  Widget _stock(double w, double h) => GestureDetector(
        onTap: _isMyTurn
            ? () => _act(SolitaireLogic.drawFromStock(_state))
            : null,
        child: _slot(w, h,
            child: _state.stock.isNotEmpty
                ? _back(w, h)
                : Center(
                    child: Icon(Icons.refresh,
                        color: _isMyTurn
                            ? AppColors.neonGreen
                            : AppColors.textMuted))),
      );

  Widget _waste(double w, double h) => _slot(w, h,
        child: _state.waste.isNotEmpty
            ? _face(_state.waste.last, w, h,
                onTap: _isMyTurn
                    ? () => _act(SolitaireLogic.moveWasteToFoundation(_state))
                    : null)
            : null,
      );

  Widget _foundation(int idx, double w, double h) {
    final f = _state.foundations[idx];
    final suit = CardSuit.values[idx];
    return GestureDetector(
      onTap: _isMyTurn
          ? () => _act(SolitaireLogic.moveWasteToFoundation(_state))
          : null,
      child: _slot(w, h,
          border: AppColors.neonGreen.withValues(alpha: 0.35),
          child: f.isNotEmpty
              ? _face(f.last, w, h)
              : Center(
                  child: Text(suit.symbol,
                      style: TextStyle(
                        color: suit.isRed ? Colors.red.shade300 : AppColors.textMuted,
                        fontSize: 20,
                      )))),
    );
  }

  Widget _tableauCol(int col, double w, double h) {
    final cards = _state.tableau[col];
    if (cards.isEmpty) {
      return GestureDetector(
        onTap: _isMyTurn
            ? () => _act(SolitaireLogic.moveWasteToTableau(_state, col))
            : null,
        child: _slot(w, h),
      );
    }
    final overlap = h * 0.27;
    return SizedBox(
      height: h + overlap * (cards.length - 1),
      child: Stack(
        children: List.generate(cards.length, (i) {
          final card = cards[i];
          return Positioned(
            top: i * overlap,
            left: 0, right: 0,
            child: card.faceUp
                ? _face(card, w, h,
                    onTap: _isMyTurn
                        ? () {
                            if (i == cards.length - 1) {
                              final r = SolitaireLogic.moveTableauToFoundation(_state, col);
                              if (r != null) { _act(r); return; }
                            }
                            for (int d = 0; d < 7; d++) {
                              if (d == col) continue;
                              final r = SolitaireLogic.moveTableauToTableau(_state, col, i, d);
                              if (r != null) { _act(r); return; }
                            }
                          }
                        : null)
                : _back(w, h),
          );
        }),
      ),
    );
  }

  // ── Widgets cartes ──────────────────────────────────────
  Widget _slot(double w, double h, {Widget? child, Color? border}) => Container(
        width: w, height: h,
        decoration: BoxDecoration(
          color: _isMyTurn
              ? AppColors.bgCardLight.withValues(alpha: 0.55)
              : AppColors.bgCardLight.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border ?? AppColors.divider.withValues(alpha: 0.5)),
        ),
        child: child,
      );

  Widget _face(PlayingCard card, double w, double h, {VoidCallback? onTap}) {
    final color = card.isRed ? Colors.red.shade500 : const Color(0xFF1A1A1A);
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap != null ? 1.0 : 0.7,
        child: Container(
          width: w, height: h,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F0E8),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(1, 2))],
          ),
          child: Stack(children: [
            Positioned(
              top: 3, left: 4,
              child: Column(children: [
                Text(card.label,
                    style: TextStyle(color: color, fontSize: w * 0.24,
                        fontWeight: FontWeight.w900, height: 1.1)),
                Text(card.suit.symbol,
                    style: TextStyle(color: color, fontSize: w * 0.2, height: 1)),
              ]),
            ),
            Center(child: Text(card.suit.symbol,
                style: TextStyle(color: color.withValues(alpha: 0.12), fontSize: w * 0.48))),
          ]),
        ),
      ),
    );
  }

  Widget _back(double w, double h) => Container(
        width: w, height: h,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3949AB), Color(0xFF7B1FA2)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(1, 2))],
        ),
        child: GridView.count(
          crossAxisCount: 4,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.all(4),
          children: List.generate(16, (_) => Container(
            margin: EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(2),
            ),
          )),
        ),
      );
}

// ============================================================
// Dialog résultats
// ============================================================
class _ResultDialog extends StatelessWidget {
  final List<SolitaireRoomPlayer> players; // triés par score desc
  final String myId;
  final int pot;
  final VoidCallback onClose;

  const _ResultDialog({
    required this.players,
    required this.myId,
    required this.pot,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final winner = players.isNotEmpty ? players.first : null;
    final isWinner = winner?.id == myId;
    final winnerCount = players.where((p) => p.score == (winner?.score ?? 0)).length;
    final myPrize = isWinner ? (pot ~/ winnerCount) : 0;

    return AlertDialog(
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(isWinner ? '🏆' : '🎴', style: TextStyle(fontSize: 48)),
          SizedBox(height: 8),
          Text(
            isWinner ? 'Victoire !' : 'Fin de partie',
            style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w900,
              color: isWinner ? AppColors.neonGreen : AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 16),
          // Classement
          ...List.generate(players.length, (i) {
            final p = players[i];
            final isMe = p.id == myId;
            final medals = ['🥇', '🥈', '🥉'];
            final medal = i < medals.length ? medals[i] : '${i + 1}.';
            return Container(
              margin: EdgeInsets.only(bottom: 6),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe
                    ? AppColors.neonGreen.withValues(alpha: 0.1)
                    : AppColors.bgElevated,
                borderRadius: BorderRadius.circular(10),
                border: isMe
                    ? Border.all(color: AppColors.neonGreen.withValues(alpha: 0.3))
                    : null,
              ),
              child: Row(children: [
                Text(medal, style: TextStyle(fontSize: 18)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isMe ? 'Moi' : p.username,
                    style: TextStyle(
                      color: isMe ? AppColors.neonGreen : AppColors.textPrimary,
                      fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                Text('${p.score} pts',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ]),
            );
          }),
          if (isWinner && myPrize > 0) ...[
            SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.monetization_on, color: AppColors.neonYellow),
              SizedBox(width: 6),
              Text('+$myPrize FCFA',
                  style: TextStyle(
                      color: AppColors.neonYellow,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ]),
          ],
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: isWinner ? AppColors.neonGreen : AppColors.neonOrange,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('RETOUR', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

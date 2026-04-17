// ============================================================
// BLACKJACK — Lobby (salle d'attente)
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/blackjack_models.dart';
import '../services/blackjack_service.dart';
import 'game_screen.dart';

class BJLobbyScreen extends StatefulWidget {
  final String roomId;
  const BJLobbyScreen({super.key, required this.roomId});
  @override
  State<BJLobbyScreen> createState() => _BJLobbyScreenState();
}

class _BJLobbyScreenState extends State<BJLobbyScreen> {
  final _svc = BlackjackService.instance;
  BJRoom? _room;
  List<Map<String, dynamic>> _players = [];
  bool _isReady = false;
  RealtimeChannel? _roomChannel;
  RealtimeChannel? _playersChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    if (_roomChannel != null) _svc.unsubscribe(_roomChannel!);
    if (_playersChannel != null) _svc.unsubscribe(_playersChannel!);
    super.dispose();
  }

  Future<void> _load() async {
    _room = await _svc.getRoom(widget.roomId);
    _players = await _svc.getPlayers(widget.roomId);
    final uid = _svc.currentUserId;
    if (uid != null) {
      final me = _players.where((p) => p['user_id'] == uid);
      if (me.isNotEmpty) _isReady = me.first['is_ready'] as bool? ?? false;
    }
    if (mounted) setState(() {});
  }

  void _subscribe() {
    _roomChannel = _svc.subscribeRoom(widget.roomId, (room) {
      setState(() => _room = room);
      if (room.status == 'playing' && room.gameId != null) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => BJGameScreen(gameId: room.gameId!),
        ));
      }
    });

    _playersChannel = _svc.subscribePlayers(widget.roomId, () {
      _loadPlayers();
    });
  }

  Future<void> _loadPlayers() async {
    _players = await _svc.getPlayers(widget.roomId);
    if (mounted) setState(() {});
  }

  Future<void> _toggleReady() async {
    HapticFeedback.heavyImpact();
    final newReady = !_isReady;
    await _svc.markReady(widget.roomId, newReady);
    setState(() => _isReady = newReady);

    if (newReady) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadPlayers();
      final allReady = _room != null &&
          _players.length == _room!.playerCount &&
          _players.every((p) => p['is_ready'] as bool? ?? false);
      if (allReady && mounted) {
        final gameId = await _svc.startGame(widget.roomId);
        if (gameId != null && mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => BJGameScreen(gameId: gameId),
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_room == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppColors.neonGreen)),
      );
    }

    final allReady = _players.length == _room!.playerCount &&
        _players.every((p) => p['is_ready'] as bool? ?? false);

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.gameWaitingRoom, style: TextStyle(fontSize: 16)),
            Text('${AppLocalizations.of(context)!.gameCode}: ${_room!.code}', style: TextStyle(
              fontSize: 12, color: AppColors.neonGreen, fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _room!.code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppLocalizations.of(context)!.gameCodeCopied), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Column(
          children: [
            // Info
            Container(
              margin: EdgeInsets.all(16),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.neonYellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _info(Icons.people, '${_players.length}/${_room!.playerCount}', 'Joueurs'),
                  _info(Icons.monetization_on, '${_room!.betAmount * _room!.playerCount}', 'Pot'),
                  _info(Icons.casino, '${_room!.betAmount}', 'Mise'),
                ],
              ),
            ),

            // Joueurs
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16),
                itemCount: _room!.playerCount,
                itemBuilder: (_, i) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: i < _players.length ? _playerCard(_players[i]) : _emptySlot(),
                  );
                },
              ),
            ),

            // Bouton
            Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: allReady ? null : _toggleReady,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isReady ? AppColors.neonRed : AppColors.neonGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    allReady ? 'Démarrage...' : _isReady ? 'Annuler' : 'PRÊT !',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String val, String label) {
    return Column(children: [
      Icon(icon, color: AppColors.neonYellow, size: 20),
      SizedBox(height: 4),
      Text(val, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
      Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
    ]);
  }

  Widget _playerCard(Map<String, dynamic> p) {
    final isMe = p['user_id'] == _svc.currentUserId;
    final ready = p['is_ready'] as bool? ?? false;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: isMe ? LinearGradient(colors: [
          AppColors.neonGreen.withValues(alpha: 0.2), AppColors.neonBlue.withValues(alpha: 0.2),
        ]) : AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMe ? AppColors.neonGreen : AppColors.divider.withValues(alpha: 0.3), width: isMe ? 2 : 1),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: ready ? AppColors.neonGreen : AppColors.bgElevated,
            child: Text((p['username'] as String? ?? '?')[0].toUpperCase(),
                style: TextStyle(color: ready ? Colors.black : AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 12))),
          SizedBox(width: 8),
          Expanded(child: Text(p['username'] as String? ?? 'Joueur', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700))),
          Icon(ready ? Icons.check_circle : Icons.schedule, size: 14,
              color: ready ? AppColors.neonGreen : AppColors.textMuted),
        ],
      ),
    );
  }

  Widget _emptySlot() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_add_outlined, size: 20, color: AppColors.textMuted.withValues(alpha: 0.5)),
          SizedBox(width: 8),
          Text(AppLocalizations.of(context)!.gameWaiting, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

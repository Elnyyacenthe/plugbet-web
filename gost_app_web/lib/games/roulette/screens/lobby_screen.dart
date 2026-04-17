// ============================================================
// ROULETTE — Lobby
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../models/roulette_models.dart';
import '../services/roulette_service.dart';
import 'game_screen.dart';

class RLTLobbyScreen extends StatefulWidget {
  final String roomId;
  const RLTLobbyScreen({super.key, required this.roomId});
  @override
  State<RLTLobbyScreen> createState() => _RLTLobbyScreenState();
}

class _RLTLobbyScreenState extends State<RLTLobbyScreen> {
  final _svc = RouletteService.instance;
  RouletteRoom? _room;
  List<Map<String, dynamic>> _players = [];
  bool _isReady = false;
  RealtimeChannel? _roomCh, _playersCh;

  @override
  void initState() { super.initState(); _load(); _subscribe(); }

  @override
  void dispose() {
    if (_roomCh != null) _svc.unsubscribe(_roomCh!);
    if (_playersCh != null) _svc.unsubscribe(_playersCh!);
    super.dispose();
  }

  Future<void> _load() async {
    _room = await _svc.getRoom(widget.roomId);
    _players = await _svc.getPlayers(widget.roomId);
    final uid = _svc.currentUserId;
    final me = _players.where((p) => p['user_id'] == uid);
    if (me.isNotEmpty) _isReady = me.first['is_ready'] as bool? ?? false;
    if (mounted) setState(() {});
  }

  void _subscribe() {
    _roomCh = _svc.subscribeRoom(widget.roomId, (room) {
      setState(() => _room = room);
      if (room.status == 'playing' && room.gameId != null) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => RLTGameScreen(gameId: room.gameId!)));
      }
    });
    _playersCh = _svc.subscribePlayers(widget.roomId, () async {
      _players = await _svc.getPlayers(widget.roomId);
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggleReady() async {
    HapticFeedback.heavyImpact();
    final newReady = !_isReady;
    await _svc.markReady(widget.roomId, newReady);
    setState(() => _isReady = newReady);

    if (newReady) {
      await Future.delayed(const Duration(milliseconds: 500));
      _players = await _svc.getPlayers(widget.roomId);
      if (mounted) setState(() {});
      final allReady = _room != null && _players.length >= 2 &&
          _players.every((p) => p['is_ready'] as bool? ?? false);
      if (allReady && mounted) {
        final gameId = await _svc.startGame(widget.roomId);
        if (gameId != null && mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => RLTGameScreen(gameId: gameId)));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_room == null) return Scaffold(backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppColors.neonGreen)));

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(backgroundColor: AppColors.bgBlueNight,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(AppLocalizations.of(context)!.gameWaitingRoom, style: TextStyle(fontSize: 16)),
          Text('${AppLocalizations.of(context)!.gameCode}: ${_room!.code}', style: TextStyle(fontSize: 12, color: AppColors.neonGreen)),
        ]),
        actions: [IconButton(icon: Icon(Icons.copy, size: 18), onPressed: () {
          Clipboard.setData(ClipboardData(text: _room!.code));
        })],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Column(children: [
          Container(margin: EdgeInsets.all(16), padding: EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.neonYellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _info('${_players.length}/${_room!.maxPlayers}', 'Joueurs'),
              _info('${_room!.minBet}+', 'Mise min'),
            ])),
          Expanded(child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16),
            itemCount: _players.length,
            itemBuilder: (_, i) {
              final p = _players[i];
              final ready = p['is_ready'] as bool? ?? false;
              return ListTile(
                leading: CircleAvatar(radius: 18, backgroundColor: ready ? AppColors.neonGreen : AppColors.bgElevated,
                  child: Text((p['username'] as String? ?? '?')[0].toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w900,
                      color: ready ? Colors.black : AppColors.textPrimary))),
                title: Text(p['username'] as String? ?? 'Joueur',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                trailing: Icon(ready ? Icons.check_circle : Icons.schedule,
                    color: ready ? AppColors.neonGreen : AppColors.textMuted, size: 20),
              );
            },
          )),
          Padding(padding: EdgeInsets.all(16), child: SizedBox(width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _toggleReady,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isReady ? AppColors.neonRed : AppColors.neonGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text(_isReady ? 'Annuler' : 'PRÊT !',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black))))),
        ]),
      ),
    );
  }

  Widget _info(String val, String label) => Column(children: [
    Text(val, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18)),
    Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
  ]);
}

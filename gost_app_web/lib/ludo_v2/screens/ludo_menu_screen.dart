// ============================================================
// LUDO V2 — Menu Screen (create/join room)
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../providers/ludo_game_provider.dart';
import '../services/ludo_service.dart';
import 'ludo_game_screen.dart';

class LudoV2MenuScreen extends StatefulWidget {
  const LudoV2MenuScreen({super.key});

  @override
  State<LudoV2MenuScreen> createState() => _LudoV2MenuScreenState();
}

class _LudoV2MenuScreenState extends State<LudoV2MenuScreen> {
  final _svc = LudoV2Service.instance;
  final _codeCtrl = TextEditingController();
  final _betCtrl = TextEditingController(text: '50');

  int _playerCount = 2;
  final bool _isPrivate = true; // Toujours privé (par code)
  bool _loading = false;
  String? _error;
  String? _waitingRoomId;
  String? _waitingCode;
  Timer? _pollTimer;
  RealtimeChannel? _roomChannel;

  @override
  void initState() {
    super.initState();
    _svc.cleanupStaleRooms(); // Nettoyer les salles > 1h
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_roomChannel != null) _svc.unsubscribe(_roomChannel!);
    _codeCtrl.dispose();
    _betCtrl.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final bet = int.tryParse(_betCtrl.text) ?? 0;
    if (bet < 0) {
      setState(() => _error = 'Mise invalide');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final result = await _svc.createRoom(
        playerCount: _playerCount,
        bet: bet,
        isPrivate: _isPrivate,
      );
      final roomId = result['room_id'] as String;
      final code = result['code'] as String;

      setState(() {
        _waitingRoomId = roomId;
        _waitingCode = code;
        _loading = false;
      });

      // Écouter les updates de la room
      _roomChannel = _svc.subscribeRoom(roomId, (room) {
        if (room.gameId != null && mounted) {
          _navigateToGame(room.gameId!);
        }
      });

      // Fallback poll
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!mounted || _waitingRoomId == null) return;
        try {
          final room = await _svc.getRoom(_waitingRoomId!);
          if (room != null && room.gameId != null && mounted) {
            _navigateToGame(room.gameId!);
          }
        } catch (_) {}
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Code trop court');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final result = await _svc.joinRoom(code);
      final gameId = result['game_id'] as String?;
      final started = result['started'] as bool? ?? false;

      if (started && gameId != null && mounted) {
        _navigateToGame(gameId);
      } else if (mounted) {
        // En attente des autres joueurs
        final roomId = result['room_id'] as String;
        setState(() {
          _waitingRoomId = roomId;
          _waitingCode = code.toUpperCase();
          _loading = false;
        });

        _roomChannel = _svc.subscribeRoom(roomId, (room) {
          if (room.gameId != null && mounted) {
            _navigateToGame(room.gameId!);
          }
        });

        _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
          if (!mounted) return;
          try {
            final room = await _svc.getRoom(roomId);
            if (room != null && room.gameId != null && mounted) {
              _navigateToGame(room.gameId!);
            }
          } catch (_) {}
        });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _navigateToGame(String gameId) {
    _pollTimer?.cancel();
    if (_roomChannel != null) _svc.unsubscribe(_roomChannel!);
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => LudoV2GameProvider(),
          child: LudoV2GameScreen(gameId: gameId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text(AppLocalizations.of(context)!.ludoTitle, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: _waitingCode != null ? _buildWaiting() : _buildMenu(),
      ),
    );
  }

  Widget _buildMenu() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Créer une salle
          _card(
            title: 'Créer une salle',
            icon: Icons.add_circle,
            child: Column(
              children: [
                // Nombre de joueurs
                Row(
                  children: [
                    Text('${AppLocalizations.of(context)!.gamePlayers}:', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    SizedBox(width: 12),
                    _chip('2', _playerCount == 2, () => setState(() => _playerCount = 2)),
                    SizedBox(width: 8),
                    _chip('4', _playerCount == 4, () => setState(() => _playerCount = 4)),
                  ],
                ),
                SizedBox(height: 12),
                // Mise
                Row(
                  children: [
                    Text('${AppLocalizations.of(context)!.gameBetLabel}:', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: _betCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: AppColors.divider),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text('coins', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _createRoom,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonGreen,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : Text(AppLocalizations.of(context)!.gameCreateAction, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),

          // Rejoindre
          _card(
            title: 'Rejoindre une salle',
            icon: Icons.login,
            child: Column(
              children: [
                TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 6),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'CODE',
                    hintStyle: TextStyle(color: AppColors.textMuted, letterSpacing: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.divider),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _joinRoom,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonBlue,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(AppLocalizations.of(context)!.gameJoinAction, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: AppColors.neonRed, fontSize: 13), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _buildWaiting() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.neonGreen),
            SizedBox(height: 24),
            Text(AppLocalizations.of(context)!.ludoWaitingPlayers, style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_waitingCode!, style: TextStyle(color: AppColors.neonGreen, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
                  SizedBox(width: 12),
                  IconButton(
                    icon: Icon(Icons.copy, color: AppColors.neonGreen),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _waitingCode!));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.gameCodeCopied)));
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            TextButton(
              onPressed: () {
                _pollTimer?.cancel();
                if (_roomChannel != null) _svc.unsubscribe(_roomChannel!);
                if (_waitingRoomId != null) _svc.deleteRoom(_waitingRoomId!);
                setState(() { _waitingRoomId = null; _waitingCode = null; });
              },
              child: Text(AppLocalizations.of(context)!.commonCancel, style: TextStyle(color: AppColors.neonRed)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.neonGreen, size: 20),
            SizedBox(width: 8),
            Text(title, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.neonGreen.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.neonGreen : AppColors.divider),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? AppColors.neonGreen : AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        )),
      ),
    );
  }
}

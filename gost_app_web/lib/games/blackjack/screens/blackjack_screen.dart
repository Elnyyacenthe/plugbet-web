// ============================================================
// BLACKJACK — Écran principal (créer/rejoindre)
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../services/blackjack_service.dart';
import 'lobby_screen.dart';

class BlackjackScreen extends StatefulWidget {
  const BlackjackScreen({super.key});
  @override
  State<BlackjackScreen> createState() => _BlackjackScreenState();
}

class _BlackjackScreenState extends State<BlackjackScreen> {
  final _svc = BlackjackService.instance;
  final _codeCtrl = TextEditingController();
  final _betCtrl = TextEditingController(text: '100');
  int _playerCount = 2;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _svc.cleanupStaleRooms();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _betCtrl.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final bet = int.tryParse(_betCtrl.text) ?? 100;
    if (bet < 50) return;
    setState(() => _loading = true);
    try {
      final result = await _svc.createRoom(playerCount: _playerCount, betAmount: bet);
      if (result != null && mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => BJLobbyScreen(roomId: result['room_id'] as String),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final roomId = await _svc.joinRoom(code);
      if (roomId != null && mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => BJLobbyScreen(roomId: roomId),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Row(children: [
          Text('🃏', style: TextStyle(fontSize: 22)),
          SizedBox(width: 8),
          Text('Blackjack', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(child: Text('${wallet.coins} coins',
                style: TextStyle(color: AppColors.neonYellow, fontWeight: FontWeight.w700))),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Créer une partie
              _sectionTitle('Créer une partie'),
              SizedBox(height: 12),
              _buildCreateCard(),
              SizedBox(height: 24),

              // Rejoindre
              _sectionTitle('Rejoindre une partie'),
              SizedBox(height: 12),
              _buildJoinCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t.toUpperCase(),
      style: TextStyle(color: AppColors.textMuted, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1.5));

  Widget _buildCreateCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          // Joueurs
          Row(children: [
            Text('Joueurs:', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            Spacer(),
            for (final n in [2, 3, 4])
              Padding(
                padding: EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text('$n'),
                  selected: _playerCount == n,
                  onSelected: (_) => setState(() => _playerCount = n),
                  selectedColor: AppColors.neonGreen,
                  backgroundColor: AppColors.bgElevated,
                  labelStyle: TextStyle(
                    color: _playerCount == n ? Colors.black : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ]),
          SizedBox(height: 12),
          // Mise
          TextField(
            controller: _betCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Mise (min 50)',
              labelStyle: TextStyle(color: AppColors.textMuted),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.neonGreen),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _createRoom,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('CRÉER LA TABLE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, letterSpacing: 2),
              decoration: InputDecoration(
                hintText: 'CODE',
                hintStyle: TextStyle(color: AppColors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.neonGreen),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          ElevatedButton(
            onPressed: _loading ? null : _joinRoom,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonBlue,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('REJOINDRE', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ROULETTE — Écran principal (créer/rejoindre) — même pattern que Blackjack
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../services/roulette_service.dart';
import 'lobby_screen.dart';

class RouletteScreen extends StatefulWidget {
  const RouletteScreen({super.key});
  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _RouletteScreenState extends State<RouletteScreen> {
  final _svc = RouletteService.instance;
  final _codeCtrl = TextEditingController();
  final _betCtrl = TextEditingController(text: '50');
  bool _loading = false;

  @override
  void initState() { super.initState(); _svc.cleanupStaleRooms();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<WalletProvider>().refresh();
    });
  }

  @override
  void dispose() { _codeCtrl.dispose(); _betCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    final bet = int.tryParse(_betCtrl.text) ?? 50;
    setState(() => _loading = true);
    try {
      final r = await _svc.createRoom(minBet: bet);
      if (r != null && mounted) Navigator.push(context, MaterialPageRoute(
        builder: (_) => RLTLobbyScreen(roomId: r['room_id'] as String)));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim(); if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final id = await _svc.joinRoom(code);
      if (id != null && mounted) Navigator.push(context, MaterialPageRoute(
        builder: (_) => RLTLobbyScreen(roomId: id)));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(backgroundColor: AppColors.bgBlueNight,
        title: Row(children: [Text('🎰', style: TextStyle(fontSize: 22)), SizedBox(width: 8),
          Text('Roulette', style: TextStyle(fontWeight: FontWeight.w800))]),
        actions: [Padding(padding: EdgeInsets.only(right: 12), child: Center(
          child: Text('${wallet.coins}', style: TextStyle(color: AppColors.neonYellow, fontWeight: FontWeight.w700))))]),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SingleChildScrollView(padding: EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _card('Créer une table', [
              TextField(controller: _betCtrl, keyboardType: TextInputType.number,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(labelText: 'Mise min', labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              SizedBox(height: 12),
              ElevatedButton(onPressed: _loading ? null : _create,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonGreen,
                  padding: EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('CRÉER', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800))),
            ]),
            SizedBox(height: 20),
            _card('Rejoindre', [
              Row(children: [
                Expanded(child: TextField(controller: _codeCtrl, textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: AppColors.textPrimary, letterSpacing: 2),
                  decoration: InputDecoration(hintText: 'CODE', hintStyle: TextStyle(color: AppColors.textMuted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
                SizedBox(width: 12),
                ElevatedButton(onPressed: _loading ? null : _join,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonBlue,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: Text('GO', style: TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ]),
          ],
        )),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
    padding: EdgeInsets.all(16), decoration: BoxDecoration(gradient: AppColors.cardGradient,
      borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title.toUpperCase(), style: TextStyle(color: AppColors.textMuted, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      SizedBox(height: 12), ...children]),
  );
}

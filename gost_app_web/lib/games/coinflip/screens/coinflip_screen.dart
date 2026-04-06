// ============================================================
// PILE OU FACE — Écran principal (créer/rejoindre duel)
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import '../services/coinflip_service.dart';
import 'game_screen.dart';

class CoinflipScreen extends StatefulWidget {
  const CoinflipScreen({super.key});
  @override
  State<CoinflipScreen> createState() => _CoinflipScreenState();
}

class _CoinflipScreenState extends State<CoinflipScreen> {
  final _svc = CoinflipService.instance;
  final _codeCtrl = TextEditingController();
  final _betCtrl = TextEditingController(text: '100');
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
  void dispose() { _codeCtrl.dispose(); _betCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    final bet = int.tryParse(_betCtrl.text) ?? 100;
    if (bet < 50) return;
    setState(() => _loading = true);
    try {
      final r = await _svc.createRoom(betAmount: bet);
      if (r != null && mounted) {
        final roomId = r['room_id'] as String;
        final code = r['code'] as String;
        _showWaiting(roomId, code);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final roomId = await _svc.joinRoom(code);
      if (roomId != null && mounted) {
        // Le join démarre automatiquement (duel = 2 joueurs)
        final room = await _svc.getRoom(roomId);
        if (room?.gameId != null && mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => CFGameScreen(gameId: room!.gameId!)));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showWaiting(String roomId, String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // S'abonner aux changements de la room
        final ch = _svc.subscribeRoom(roomId, (room) {
          if (room.status == 'playing' && room.gameId != null) {
            Navigator.pop(ctx);
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => CFGameScreen(gameId: room.gameId!)));
          }
        });

        return PopScope(
          onPopInvokedWithResult: (didPop, _) { _svc.unsubscribe(ch); },
          child: AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('En attente...', style: TextStyle(color: AppColors.textPrimary)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: AppColors.neonGreen),
              SizedBox(height: 16),
              Text('Code: $code', style: TextStyle(color: AppColors.neonGreen,
                  fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 4)),
              SizedBox(height: 8),
              Text('Partage ce code à ton adversaire',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ]),
            actions: [
              TextButton(
                onPressed: () { _svc.unsubscribe(ch); Navigator.pop(ctx); },
                child: Text('Annuler', style: TextStyle(color: AppColors.neonRed))),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(backgroundColor: AppColors.bgBlueNight,
        title: Row(children: [
          Text('🪙', style: TextStyle(fontSize: 22)), SizedBox(width: 8),
          Text('Pile ou Face', style: TextStyle(fontWeight: FontWeight.w800))]),
        actions: [Padding(padding: EdgeInsets.only(right: 12), child: Center(
          child: Text('${wallet.coins}', style: TextStyle(
            color: AppColors.neonYellow, fontWeight: FontWeight.w700))))]),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SingleChildScrollView(padding: EdgeInsets.all(20), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Hero
            Container(padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.neonYellow.withValues(alpha: 0.15), Colors.orange.withValues(alpha: 0.1)]),
                borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                Text('🪙', style: TextStyle(fontSize: 60)),
                SizedBox(height: 12),
                Text('DUEL', style: TextStyle(color: AppColors.neonYellow,
                    fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 3)),
                Text('2 joueurs • 1 pièce • Le gagnant prend tout',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ])),
            SizedBox(height: 24),

            // Créer
            _section('Créer un duel', [
              TextField(controller: _betCtrl, keyboardType: TextInputType.number,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(labelText: 'Mise (min 50)',
                  labelStyle: TextStyle(color: AppColors.textMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              SizedBox(height: 12),
              ElevatedButton(onPressed: _loading ? null : _create,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonYellow,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('LANCER LE DUEL', style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16))),
            ]),
            SizedBox(height: 20),

            // Rejoindre
            _section('Rejoindre', [
              Row(children: [
                Expanded(child: TextField(controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: AppColors.textPrimary, letterSpacing: 2),
                  decoration: InputDecoration(hintText: 'CODE',
                    hintStyle: TextStyle(color: AppColors.textMuted),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
                SizedBox(width: 12),
                ElevatedButton(onPressed: _loading ? null : _join,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonBlue,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: Text('GO', style: TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ]),
          ])),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Container(
    padding: EdgeInsets.all(16), decoration: BoxDecoration(gradient: AppColors.cardGradient,
      borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title.toUpperCase(), style: TextStyle(color: AppColors.textMuted,
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      SizedBox(height: 12), ...children]),
  );
}

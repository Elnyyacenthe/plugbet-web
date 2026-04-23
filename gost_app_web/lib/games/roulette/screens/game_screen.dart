// ============================================================
// ROULETTE — Écran de jeu
// ============================================================

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/wallet_provider.dart';
import '../../../providers/matches_provider.dart';
import '../../../services/live_score_manager.dart';
import '../models/roulette_models.dart';
import '../services/roulette_service.dart';

class RLTGameScreen extends StatefulWidget {
  final String gameId;
  const RLTGameScreen({super.key, required this.gameId});
  @override
  State<RLTGameScreen> createState() => _RLTGameScreenState();
}

class _RLTGameScreenState extends State<RLTGameScreen> with SingleTickerProviderStateMixin {
  final _svc = RouletteService.instance;
  RouletteGame? _game;
  bool _loading = true;
  RealtimeChannel? _channel;
  String? _selectedType;
  int? _selectedNumber;
  final _betCtrl = TextEditingController(text: '50');
  bool _placing = false;
  bool _spinning = false;
  // (auto-continue, pas de vote)

  // Animation roue
  late AnimationController _wheelCtrl;
  double _wheelAngle = 0;

  String get _myId => _svc.currentUserId ?? '';

  static const _redNumbers = {1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36};

  @override
  void initState() {
    super.initState();
    _wheelCtrl = AnimationController(vsync: this, duration: Duration(seconds: 4));
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try { context.read<MatchesProvider>().pausePolling(); } catch (_) {}
      try { context.read<LiveScoreManager>().pauseTracking(); } catch (_) {}
    });
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    _betCtrl.dispose();
    if (_channel != null) _svc.unsubscribe(_channel!);
    try { context.read<MatchesProvider>().resumePolling(); } catch (_) {}
    try { context.read<LiveScoreManager>().resumeTracking(); } catch (_) {}
    super.dispose();
  }

  Future<void> _init() async {
    _game = await _svc.getGame(widget.gameId);
    _channel = _svc.subscribeGame(widget.gameId, _onUpdate);
    if (mounted) setState(() => _loading = false);
  }

  void _onUpdate(RouletteGame g) {
    if (!mounted) return;
    final wasSpinning = _game?.gameState.phase == 'betting';
    setState(() => _game = g);

    if (wasSpinning && g.gameState.phase == 'spinning') {
      _animateSpin(g.gameState.result ?? 0);
    }
    if (g.gameState.isFinished) {
      Future.delayed(Duration(seconds: 2), () {
        if (mounted) _showResult();
      });
    }
  }

  void _animateSpin(int result) {
    final targetAngle = (result / 37) * 2 * pi + 4 * 2 * pi;
    _wheelCtrl.reset();
    _wheelCtrl.forward();
    _wheelCtrl.addListener(() {
      setState(() => _wheelAngle = targetAngle * _wheelCtrl.value);
    });
  }

  Future<void> _placeBet() async {
    if (_selectedType == null || _placing) return;
    final amount = int.tryParse(_betCtrl.text) ?? 50;
    setState(() => _placing = true);
    try {
      await _svc.placeBet(widget.gameId, _selectedType!, amount, number: _selectedNumber);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pari placé: $_selectedType ${_selectedNumber ?? ""} ($amount FCFA)'),
            backgroundColor: AppColors.neonGreen, duration: Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _spinWheel() async {
    if (_spinning) return;
    setState(() => _spinning = true);
    try {
      await _svc.spin(widget.gameId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _spinning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _game == null) {
      return Scaffold(backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppColors.neonGreen)));
    }

    final gs = _game!.gameState;

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(backgroundColor: const Color(0xFF0D3B0F),
        title: Text('Roulette', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true),
      body: SafeArea(
        child: Column(children: [
          // Phase
          Container(width: double.infinity, padding: EdgeInsets.symmetric(vertical: 8),
            color: gs.phase == 'betting' ? AppColors.neonGreen.withValues(alpha: 0.15) :
                   gs.phase == 'spinning' ? Colors.orange.withValues(alpha: 0.15) :
                   AppColors.neonYellow.withValues(alpha: 0.15),
            child: Text(
              gs.phase == 'betting' ? 'Placez vos paris !' :
              gs.phase == 'spinning' ? 'La roue tourne...' :
              'Résultat: ${gs.result ?? "?"}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),

          // Roue
          SizedBox(height: 16),
          _buildWheel(gs),
          SizedBox(height: 16),

          // Zone de paris (seulement en phase betting)
          if (gs.phase == 'betting') Expanded(child: _buildBettingArea()),

          // Bouton LANCER LA ROUE (après avoir misé)
          if (gs.phase == 'betting')
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _spinning ? null : _spinWheel,
                  icon: Icon(Icons.casino, size: 20),
                  label: Text(AppLocalizations.of(context)!.gameSpinWheel,
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),

          // Résultat
          if (gs.isFinished) _buildResultBanner(gs),
        ]),
      ),
    );
  }

  Widget _buildWheel(RouletteGameState gs) {
    return Transform.rotate(
      angle: _wheelAngle,
      child: Container(
        width: 120, height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [
            Colors.red, Colors.black, Colors.red, Colors.black,
            Colors.green, Colors.red, Colors.black, Colors.red,
          ]),
          border: Border.all(color: AppColors.neonYellow, width: 3),
          boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 12)],
        ),
        child: Center(
          child: Container(
            width: 50, height: 50,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: Center(child: Text(
              gs.result != null && gs.isFinished ? '${gs.result}' : '?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                color: gs.result != null && _redNumbers.contains(gs.result) ? Colors.red : Colors.black),
            )),
          ),
        ),
      ),
    );
  }

  Widget _buildBettingArea() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        // Types de paris
        Wrap(spacing: 8, runSpacing: 8, children: [
          _betChip('Rouge', 'red', Colors.red),
          _betChip('Noir', 'black', Colors.black87),
          _betChip('Pair', 'even', Colors.blue),
          _betChip('Impair', 'odd', Colors.purple),
          _betChip('1-18', 'low', Colors.teal),
          _betChip('19-36', 'high', Colors.orange),
        ]),
        SizedBox(height: 12),

        // Numéro exact
        Row(children: [
          Text('${AppLocalizations.of(context)!.gameExactNumber}:', style: TextStyle(color: Colors.white70, fontSize: 13)),
          SizedBox(width: 8),
          SizedBox(width: 60, child: TextField(
            keyboardType: TextInputType.number,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(hintText: '0-36', hintStyle: TextStyle(color: Colors.white30),
              isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n >= 0 && n <= 36) {
                setState(() { _selectedType = 'number'; _selectedNumber = n; });
              }
            },
          )),
        ]),
        SizedBox(height: 12),

        // Montant
        Row(children: [
          Text('${AppLocalizations.of(context)!.gameBetLabel}:', style: TextStyle(color: Colors.white70, fontSize: 13)),
          SizedBox(width: 8),
          SizedBox(width: 80, child: TextField(controller: _betCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          SizedBox(width: 12),
          Expanded(child: ElevatedButton(
            onPressed: _selectedType != null && !_placing ? _placeBet : null,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonGreen,
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(AppLocalizations.of(context)!.gameBetButton, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)))),
        ]),
      ]),
    );
  }

  Widget _betChip(String label, String type, Color color) {
    final selected = _selectedType == type && _selectedNumber == null;
    return GestureDetector(
      onTap: () => setState(() { _selectedType = type; _selectedNumber = null; }),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: selected ? Border.all(color: Colors.white, width: 2) : null),
        child: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }

  Widget _buildResultBanner(RouletteGameState gs) {
    final myPlayer = gs.players[_myId];
    final won = myPlayer?.winnings != null && myPlayer!.winnings! > 0;
    return Container(
      padding: EdgeInsets.all(16), margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: won ? AppColors.neonGreen.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(won ? 'Tu as gagné !' : 'Perdu...', style: TextStyle(
          color: won ? AppColors.neonGreen : Colors.redAccent, fontSize: 20, fontWeight: FontWeight.w900)),
        if (won) Text('+${myPlayer!.winnings} FCFA', style: TextStyle(
          color: AppColors.neonYellow, fontSize: 24, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  void _showResult() {
    try { context.read<WalletProvider>().refresh(); } catch (_) {}
    showDialog(context: context, barrierDismissible: false, builder: (ctx) {
      final autoTimer = Timer(Duration(seconds: 5), () {
        if (mounted) _rltAutoContinue(ctx);
      });
      return PopScope(
        onPopInvokedWithResult: (_, __) => autoTimer.cancel(),
        child: AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Résultat: ${_game?.gameState.result ?? "?"}',
              style: TextStyle(color: AppColors.neonYellow)),
          content: Text(AppLocalizations.of(context)!.gameNextRound, style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(onPressed: () { autoTimer.cancel(); Navigator.pop(ctx); Navigator.pop(context); },
              child: Text(AppLocalizations.of(context)!.gameQuit, style: TextStyle(color: AppColors.neonRed))),
          ],
        ),
      );
    });
  }

  Future<void> _rltAutoContinue(BuildContext ctx) async {
    if (!mounted) return;
    try {
      final r = await _svc.autoContinue(widget.gameId);
      if (!mounted) return;
      try { Navigator.pop(ctx); } catch (_) {}
      if (r == 'ended') { Navigator.pop(context); }
      else {
        try { context.read<WalletProvider>().refresh(); } catch (_) {}
        _game = await _svc.getGame(widget.gameId);
        _wheelAngle = 0;
        if (mounted) setState(() {});
      }
    } catch (_) { if (mounted) { try { Navigator.pop(ctx); } catch (_) {} Navigator.pop(context); } }
  }
}

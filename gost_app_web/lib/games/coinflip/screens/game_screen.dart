// ============================================================
// PILE OU FACE — Écran de jeu (duel)
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
import '../models/coinflip_models.dart';
import '../services/coinflip_service.dart';

class CFGameScreen extends StatefulWidget {
  final String gameId;
  const CFGameScreen({super.key, required this.gameId});
  @override
  State<CFGameScreen> createState() => _CFGameScreenState();
}

class _CFGameScreenState extends State<CFGameScreen> with SingleTickerProviderStateMixin {
  final _svc = CoinflipService.instance;
  CFGame? _game;
  bool _loading = true;
  bool _choosing = false;
  RealtimeChannel? _channel;
  bool _showingResult = false;

  // Animation pièce
  late AnimationController _flipCtrl;
  int _flipCount = 0;

  String get _myId => _svc.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 800))
      ..addListener(() { setState(() {}); });
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try { context.read<MatchesProvider>().pausePolling(); } catch (_) {}
      try { context.read<LiveScoreManager>().pauseTracking(); } catch (_) {}
    });
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
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

  void _onUpdate(CFGame g) {
    if (!mounted) return;
    final wasChoosing = _game?.gameState.phase == 'choosing';
    setState(() => _game = g);

    if (wasChoosing && g.gameState.phase == 'flipping') {
      _animateFlip();
    }
    if (g.gameState.isFinished && !_showingResult) {
      _showingResult = true;
      Future.delayed(Duration(seconds: 2), () {
        if (mounted) _showResult();
      });
    }
  }

  void _animateFlip() {
    _flipCount = 0;
    _flipCtrl.repeat();
    Future.delayed(Duration(seconds: 3), () {
      _flipCtrl.stop();
      if (mounted) setState(() {});
    });
  }

  Future<void> _choose(String side) async {
    if (_choosing) return;
    setState(() => _choosing = true);
    try {
      await _svc.chooseSide(widget.gameId, side);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _game == null) {
      return Scaffold(backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppColors.neonYellow)));
    }

    final gs = _game!.gameState;
    final myPlayer = gs.players[_myId];
    final hasChosen = myPlayer?.hasChosen ?? false;
    final isWinner = gs.winnerId == _myId;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(backgroundColor: AppColors.bgBlueNight,
        title: Text(AppLocalizations.of(context)!.gameCoinflipTitle, style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [Padding(padding: EdgeInsets.only(right: 12), child: Center(
          child: Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.neonYellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8)),
            child: Text('${AppLocalizations.of(context)!.gamePot}: ${_game!.pot}', style: TextStyle(
              color: AppColors.neonYellow, fontWeight: FontWeight.w700)))))]),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(child: Column(children: [
          // Status
          Container(width: double.infinity, padding: EdgeInsets.symmetric(vertical: 10),
            color: gs.phase == 'choosing' ? AppColors.neonBlue.withValues(alpha: 0.15) :
                   gs.phase == 'flipping' ? AppColors.neonYellow.withValues(alpha: 0.15) :
                   isWinner ? AppColors.neonGreen.withValues(alpha: 0.15) :
                   Colors.red.withValues(alpha: 0.15),
            child: Text(
              gs.phase == 'choosing' ? (hasChosen ? 'En attente de l\'adversaire...' : 'Choisis ton côté !') :
              gs.phase == 'flipping' ? 'La pièce tourne...' :
              isWinner ? 'Tu as gagné !' : 'Tu as perdu...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16))),

          Spacer(),

          // Pièce
          _buildCoin(gs),

          SizedBox(height: 24),

          // Joueurs
          _buildPlayers(gs),

          Spacer(),

          // Boutons choix
          if (gs.phase == 'choosing' && !hasChosen)
            Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(children: [
                Expanded(child: _choiceButton('PILE', 'pile', AppColors.neonYellow)),
                SizedBox(width: 16),
                Expanded(child: _choiceButton('FACE', 'face', AppColors.neonBlue)),
              ])),

          if (hasChosen && gs.phase == 'choosing')
            Padding(padding: EdgeInsets.only(bottom: 20),
              child: Text('${AppLocalizations.of(context)!.gameYouChose}: ${myPlayer!.choice?.toUpperCase() ?? "?"}',
                style: TextStyle(color: AppColors.neonGreen, fontSize: 16, fontWeight: FontWeight.w700))),

          // Résultat
          if (gs.isFinished)
            Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Container(padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isWinner ? AppColors.neonGreen.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  Text('${AppLocalizations.of(context)!.gameResult}: ${gs.result?.toUpperCase() ?? "?"}',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text(isWinner ? '+${_game!.pot} FCFA' : '-${_game!.betAmount} FCFA',
                    style: TextStyle(
                      color: isWinner ? AppColors.neonGreen : Colors.redAccent,
                      fontSize: 24, fontWeight: FontWeight.w900)),
                ]))),
        ])),
      ),
    );
  }

  Widget _buildCoin(CFGameState gs) {
    final isFlipping = _flipCtrl.isAnimating;
    final angle = isFlipping ? _flipCtrl.value * 2 * pi * 6 : 0.0;
    final showResult = gs.isFinished && gs.result != null;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(angle),
      child: Container(
        width: 140, height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            Color(0xFFFFD700), Color(0xFFDAA520), Color(0xFFB8860B)]),
          border: Border.all(color: Color(0xFFFFD700), width: 4),
          boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 8))],
        ),
        child: Center(child: Text(
          showResult ? (gs.result == 'pile' ? 'P' : 'F') : '?',
          style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900,
            color: Color(0xFF4A3000)),
        )),
      ),
    );
  }

  Widget _buildPlayers(CFGameState gs) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: gs.players.entries.map((e) {
          final isMe = e.key == _myId;
          final p = e.value;
          final won = gs.winnerId == e.key;
          return Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? AppColors.neonGreen.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: won ? Border.all(color: AppColors.neonYellow, width: 2) : null),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 20,
                backgroundColor: isMe ? AppColors.neonGreen : AppColors.neonBlue,
                child: Text(p.username[0].toUpperCase(),
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900))),
              SizedBox(height: 4),
              Text(isMe ? 'Toi' : p.username, style: TextStyle(
                color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
              if (p.hasChosen) Icon(Icons.check_circle, color: AppColors.neonGreen, size: 16),
              if (won) Text('👑', style: TextStyle(fontSize: 18)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _choiceButton(String label, String side, Color color) {
    return ElevatedButton(
      onPressed: _choosing ? null : () => _choose(side),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      child: Text(label, style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w900)),
    );
  }

  void _showResult() {
    if (_game == null) return;
    final isWinner = _game!.gameState.winnerId == _myId;
    try { context.read<WalletProvider>().refresh(); } catch (_) {}

    showDialog(context: context, barrierDismissible: false, builder: (ctx) {
      final autoTimer = Timer(Duration(seconds: 5), () {
        if (mounted) _cfAutoContinue(ctx);
      });
      return PopScope(
        onPopInvokedWithResult: (_, __) => autoTimer.cancel(),
        child: AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(isWinner ? Icons.emoji_events : Icons.close,
              color: isWinner ? AppColors.neonYellow : Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Text(isWinner ? 'Victoire !' : 'Défaite',
              style: TextStyle(color: isWinner ? AppColors.neonYellow : Colors.redAccent)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${AppLocalizations.of(context)!.gameResult}: ${_game!.gameState.result?.toUpperCase() ?? "?"}',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18)),
            if (isWinner) Text('+${_game!.pot} FCFA',
              style: TextStyle(color: AppColors.neonGreen, fontSize: 22, fontWeight: FontWeight.w900)),
            SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.gameNextRound, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () { autoTimer.cancel(); Navigator.pop(ctx); Navigator.pop(context); },
              child: Text(AppLocalizations.of(context)!.gameQuit, style: TextStyle(color: AppColors.neonRed))),
          ],
        ),
      );
    });
  }

  Future<void> _cfAutoContinue(BuildContext ctx) async {
    if (!mounted) return;
    try {
      final r = await _svc.autoContinue(widget.gameId);
      if (!mounted) return;
      try { Navigator.pop(ctx); } catch (_) {}
      if (r == 'ended') { Navigator.pop(context); }
      else {
        _showingResult = false;
        try { context.read<WalletProvider>().refresh(); } catch (_) {}
        _game = await _svc.getGame(widget.gameId);
        if (mounted) setState(() {});
      }
    } catch (_) { if (mounted) { try { Navigator.pop(ctx); } catch (_) {} Navigator.pop(context); } }
  }
}

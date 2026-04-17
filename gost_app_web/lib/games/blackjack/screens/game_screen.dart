// ============================================================
// BLACKJACK — Écran de jeu
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/wallet_provider.dart';
import '../../../providers/matches_provider.dart';
import '../../../services/live_score_manager.dart';
import '../models/blackjack_models.dart';
import '../services/blackjack_service.dart';
import '../widgets/card_widget.dart';

class BJGameScreen extends StatefulWidget {
  final String gameId;
  const BJGameScreen({super.key, required this.gameId});
  @override
  State<BJGameScreen> createState() => _BJGameScreenState();
}

class _BJGameScreenState extends State<BJGameScreen> {
  final _svc = BlackjackService.instance;
  BJGame? _game;
  bool _loading = true;
  bool _acting = false;
  RealtimeChannel? _channel;
  Timer? _turnTimer;
  int _countdown = 15;
  int _consecutiveTimeouts = 0;
  bool _showingResult = false;

  String get _myId => _svc.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try { context.read<MatchesProvider>().pausePolling(); } catch (_) {}
      try { context.read<LiveScoreManager>().pauseTracking(); } catch (_) {}
    });
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    if (_channel != null) _svc.unsubscribe(_channel!);
    try { context.read<MatchesProvider>().resumePolling(); } catch (_) {}
    try { context.read<LiveScoreManager>().resumeTracking(); } catch (_) {}
    super.dispose();
  }

  Future<void> _init() async {
    debugPrint('[BJ-GAME] Loading game: ${widget.gameId}');
    _game = await _svc.getGame(widget.gameId);
    debugPrint('[BJ-GAME] Game loaded: ${_game != null}, phase: ${_game?.gameState.phase}, players: ${_game?.gameState.players.length}');
    _channel = _svc.subscribeGame(widget.gameId, _onGameUpdate);
    if (mounted) setState(() => _loading = false);
    _startTimer();
  }

  void _onGameUpdate(BJGame updated) {
    if (!mounted) return;
    setState(() => _game = updated);
    _startTimer();

    if (updated.gameState.isFinished && !_showingResult) {
      _turnTimer?.cancel();
      _showingResult = true;
      Future.delayed(Duration(seconds: 1), () {
        if (mounted) _showResultDialog();
      });
    }
  }

  void _startTimer() {
    _turnTimer?.cancel();
    if (_game == null || _game!.gameState.isFinished) return;
    if (_game!.gameState.currentTurn != _myId) return;
    if (_game!.gameState.phase != 'playing') return;

    _countdown = 15;
    _turnTimer = Timer.periodic(Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _consecutiveTimeouts++;
        if (_consecutiveTimeouts >= 4) {
          _stand(); // Auto-stand = forfait progressif
        } else {
          _stand(); // Auto-stand après timeout
        }
      }
    });
  }

  Future<void> _hit() async {
    if (_acting || _game == null) return;
    _consecutiveTimeouts = 0;
    setState(() => _acting = true);
    try {
      await _svc.hit(widget.gameId);
    } catch (e) {
      debugPrint('[BJ] hit error: $e');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _stand() async {
    if (_acting || _game == null) return;
    setState(() => _acting = true);
    try {
      await _svc.stand(widget.gameId);
    } catch (e) {
      debugPrint('[BJ] stand error: $e');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _game == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(child: CircularProgressIndicator(color: AppColors.neonGreen)),
      );
    }

    final gs = _game!.gameState;
    final isMyTurn = gs.currentTurn == _myId && gs.phase == 'playing';
    final myPlayer = gs.players[_myId];
    final canHit = isMyTurn && myPlayer != null && myPlayer.hand.canHit && !_acting;
    final canStand = isMyTurn && myPlayer != null && myPlayer.hand.status == 'playing' && !_acting;

    return Scaffold(
      backgroundColor: const Color(0xFF0B6623), // Vert casino
      appBar: AppBar(
        backgroundColor: const Color(0xFF064E18),
        title: Text('Blackjack', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          if (isMyTurn && _countdown > 0)
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _countdown <= 5 ? Colors.red.withValues(alpha: 0.3) : Colors.white12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_countdown}s', style: TextStyle(
                  color: _countdown <= 5 ? Colors.redAccent : Colors.white70,
                  fontWeight: FontWeight.w800)),
              )),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status
            _buildStatusBar(gs),

            // Dealer
            _buildDealerSection(gs),

            Spacer(),

            // Autres joueurs
            if (gs.players.length > 1) _buildOtherPlayers(gs),

            // Mon jeu
            if (myPlayer != null) _buildMyHand(myPlayer, gs),

            // Boutons
            if (gs.phase == 'playing' && !gs.isFinished)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: canHit ? _hit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonGreen,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(AppLocalizations.of(context)!.gameHit, style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: canStand ? _stand : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonRed,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(AppLocalizations.of(context)!.gameStand, style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              ),

            if (gs.phase == 'dealer_turn' && !gs.isFinished)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(AppLocalizations.of(context)!.gameDealerPlaying, style: TextStyle(
                    color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(BJGameState gs) {
    String msg;
    Color color;
    if (gs.isFinished) {
      msg = 'Partie terminée';
      color = AppColors.neonYellow;
    } else if (gs.phase == 'dealing') {
      msg = 'Distribution...';
      color = Colors.white70;
    } else if (gs.phase == 'dealer_turn') {
      msg = 'Tour du dealer';
      color = Colors.orange;
    } else if (gs.currentTurn == _myId) {
      msg = 'Ton tour — Hit ou Stand ?';
      color = AppColors.neonGreen;
    } else {
      final p = gs.players[gs.currentTurn];
      msg = 'Tour de ${p?.username ?? "..."}';
      color = Colors.white54;
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 8),
      color: color.withValues(alpha: 0.15),
      child: Text(msg, textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }

  Widget _buildDealerSection(BJGameState gs) {
    final dealer = gs.dealerHand;
    final hideSecond = gs.phase == 'playing' && !gs.isFinished;
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(AppLocalizations.of(context)!.gameDealer, style: TextStyle(color: Colors.white54, fontSize: 12,
              fontWeight: FontWeight.w700, letterSpacing: 2)),
          SizedBox(height: 8),
          BJHandWidget(cards: dealer.cards, hideSecond: hideSecond, cardWidth: 48),
          SizedBox(height: 6),
          if (!hideSecond && dealer.cards.isNotEmpty)
            Text('Score: ${dealer.score}', style: TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildOtherPlayers(BJGameState gs) {
    final others = gs.players.entries.where((e) => e.key != _myId).toList();
    if (others.isEmpty) return SizedBox.shrink();

    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: others.map((e) {
          final p = e.value;
          final isActive = gs.currentTurn == e.key;
          return Container(
            margin: EdgeInsets.only(right: 8),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? Colors.white12 : Colors.black12,
              borderRadius: BorderRadius.circular(10),
              border: isActive ? Border.all(color: AppColors.neonGreen, width: 2) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(p.username, style: TextStyle(color: Colors.white70, fontSize: 10,
                      fontWeight: FontWeight.w700), maxLines: 1),
                  Text('${p.hand.score}', style: TextStyle(color: Colors.white54, fontSize: 10)),
                ]),
                SizedBox(width: 6),
                BJHandWidget(cards: p.hand.cards, cardWidth: 22),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMyHand(BJPlayer me, BJGameState gs) {
    final isActive = gs.currentTurn == _myId;
    return Container(
      margin: EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withValues(alpha: 0.08) : Colors.black26,
        borderRadius: BorderRadius.circular(16),
        border: isActive ? Border.all(color: AppColors.neonGreen, width: 2) : null,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppLocalizations.of(context)!.gameYou, style: TextStyle(color: AppColors.neonGreen, fontSize: 12,
                  fontWeight: FontWeight.w700, letterSpacing: 2)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _scoreColor(me.hand).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${me.hand.score}', style: TextStyle(
                    color: _scoreColor(me.hand), fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ],
          ),
          SizedBox(height: 8),
          BJHandWidget(cards: me.hand.cards, cardWidth: 55),
          if (me.hand.status != 'playing')
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                me.hand.status == 'bust' ? 'BUST !' :
                me.hand.status == 'blackjack' ? 'BLACKJACK !' :
                me.hand.status == 'stand' ? 'Stand' : me.hand.status.toUpperCase(),
                style: TextStyle(
                  color: me.hand.status == 'bust' ? Colors.redAccent :
                         me.hand.status == 'blackjack' ? AppColors.neonYellow : Colors.white54,
                  fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  Color _scoreColor(BJHand hand) {
    if (hand.isBust) return Colors.redAccent;
    if (hand.isBlackjack) return AppColors.neonYellow;
    if (hand.score >= 17) return Colors.orange;
    return AppColors.neonGreen;
  }

  void _showResultDialog() {
    if (_game == null) return;
    final gs = _game!.gameState;
    final result = gs.results[_myId] ?? 'lost';
    final isWin = result == 'won';
    final isPush = result == 'push';
    final pot = _game!.betAmount * _game!.playerCount;

    try { context.read<WalletProvider>().refresh(); } catch (_) {}

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // Auto-continue après 5s
        final autoTimer = Timer(Duration(seconds: 5), () {
          if (mounted) _autoContinue(ctx);
        });

        return PopScope(
          onPopInvokedWithResult: (_, __) => autoTimer.cancel(),
          child: AlertDialog(
            backgroundColor: AppColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(children: [
              Icon(
                isWin ? Icons.emoji_events : isPush ? Icons.handshake : Icons.close,
                color: isWin ? AppColors.neonYellow : isPush ? Colors.orange : Colors.redAccent,
                size: 28),
              SizedBox(width: 10),
              Text(
                isWin ? 'Victoire !' : isPush ? 'Égalité' : 'Défaite',
                style: TextStyle(color: isWin ? AppColors.neonYellow : isPush ? Colors.orange : Colors.redAccent)),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Dealer: ${gs.dealerHand.score}  |  Toi: ${gs.players[_myId]?.hand.score ?? 0}',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                if (isWin) ...[
                  SizedBox(height: 12),
                  Text('+$pot coins', style: TextStyle(
                      color: AppColors.neonGreen, fontSize: 24, fontWeight: FontWeight.w900)),
                ],
                SizedBox(height: 8),
                Text(AppLocalizations.of(context)!.gameNextRound, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () { autoTimer.cancel(); Navigator.pop(ctx); Navigator.pop(context); },
                child: Text(AppLocalizations.of(context)!.gameQuit, style: TextStyle(color: AppColors.neonRed)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _autoContinue(BuildContext ctx) async {
    if (!mounted) return;
    try {
      final result = await _svc.autoContinue(widget.gameId);
      if (!mounted) return;
      try { Navigator.pop(ctx); } catch (_) {}
      if (result == 'ended') {
        Navigator.pop(context);
      } else {
        _showingResult = false;
        try { context.read<WalletProvider>().refresh(); } catch (_) {}
        _game = await _svc.getGame(widget.gameId);
        if (mounted) setState(() {});
        _startTimer();
      }
    } catch (_) {
      if (mounted) { try { Navigator.pop(ctx); } catch (_) {} Navigator.pop(context); }
    }
  }
}

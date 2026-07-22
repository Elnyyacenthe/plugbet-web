// ============================================================
// BLACKJACK — Écran de jeu
// ============================================================
// >>> DESIGN PREMIUM <<<
// Seul l'habillage visuel a ete retravaille (feutre casino degrade,
// panneaux glassmorphism, bordures neon actives, boutons a glow,
// badges, dialogue premium). Toute la logique de jeu (gameId, service,
// realtime, timers, RPC hit/stand, providers, callbacks...) est
// strictement identique a l'original.
// ============================================================

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../services/audio_service.dart';
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
import '../../../services/network_retry.dart';
import '../../../widgets/connectivity_banner.dart';
import '../../../widgets/network_lost_overlay.dart';

class BJGameScreen extends StatefulWidget {
  final String gameId;
  const BJGameScreen({super.key, required this.gameId});
  @override
  State<BJGameScreen> createState() => _BJGameScreenState();
}

class _BJGameScreenState extends State<BJGameScreen>
    with WidgetsBindingObserver {
  final _svc = BlackjackService.instance;
  BJGame? _game;
  bool _loading = true;
  bool _acting = false;
  String? _pendingAction;
  RealtimeChannel? _channel;
  Timer? _turnTimer;
  Timer? _pollTimer; // fallback realtime mort
  int _countdown = 15;
  int _consecutiveTimeouts = 0;
  bool _showingResult = false;

  String get _myId => _svc.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _initAudio();
    WidgetsBinding.instance.addObserver(this);
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<MatchesProvider>().pausePolling();
      } catch (_) {}
      try {
        context.read<LiveScoreManager>().pauseTracking();
      } catch (_) {}
    });
  }

  Future<void> _initAudio() async {
    await AudioService.instance.configureGame('blackjack');
    AudioService.instance.startBackgroundMusic();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !(_game?.gameState.isFinished ?? false)) {
      _refetchNow();
    }
  }

  Future<void> _refetchNow() async {
    final fresh = await _svc.getGame(widget.gameId);
    if (fresh != null && mounted) _onGameUpdate(fresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _turnTimer?.cancel();
    _pollTimer?.cancel();
    if (_channel != null) _svc.unsubscribe(_channel!);
    try {
      context.read<MatchesProvider>().resumePolling();
    } catch (_) {}
    try {
      context.read<LiveScoreManager>().resumeTracking();
    } catch (_) {}
    AudioService.instance.stopBackgroundMusic();
    super.dispose();
  }

  Future<void> _init() async {
    debugPrint('[BJ-GAME] Loading game: ${widget.gameId}');
    _game = await _svc.getGame(widget.gameId);
    debugPrint(
        '[BJ-GAME] Game loaded: ${_game != null}, phase: ${_game?.gameState.phase}, players: ${_game?.gameState.players.length}');
    _channel = _svc.subscribeGame(
      widget.gameId,
      _onGameUpdate,
      onConnectionLost: _startPollingFallback,
    );
    if (mounted) setState(() => _loading = false);
    _startTimer();
  }

  /// Polling 2s si le realtime meurt. Auto-stop quand game fini.
  void _startPollingFallback() {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted || (_game?.gameState.isFinished ?? false)) {
        t.cancel();
        _pollTimer = null;
        return;
      }
      final fresh = await _svc.getGame(widget.gameId);
      if (fresh != null) _onGameUpdate(fresh);
    });
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
      if (!mounted) {
        t.cancel();
        return;
      }
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
    setState(() {
      _acting = true;
      _pendingAction = 'hit';
    });
    final reqId =
        '$_myId-${widget.gameId}-hit-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await NetworkRetry.run(() => _svc.hit(widget.gameId, requestId: reqId),
          label: 'bj_hit');
      AudioService.instance.playCardFlip();
    } catch (e) {
      debugPrint('[BJ] hit error: $e');
      if (mounted && _isNet(e)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Connexion perdue — reessaie'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted)
        setState(() {
          _acting = false;
          _pendingAction = null;
        });
    }
  }

  Future<void> _stand() async {
    if (_acting || _game == null) return;
    setState(() {
      _acting = true;
      _pendingAction = 'stand';
    });
    final reqId =
        '$_myId-${widget.gameId}-stand-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await NetworkRetry.run(() => _svc.stand(widget.gameId, requestId: reqId),
          label: 'bj_stand');
      AudioService.instance.playChipPlace();
    } catch (e) {
      debugPrint('[BJ] stand error: $e');
      if (mounted && _isNet(e)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Connexion perdue — reessaie'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted)
        setState(() {
          _acting = false;
          _pendingAction = null;
        });
    }
  }

  bool _isNet(Object e) {
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('TimeoutException') ||
        s.contains('Failed host lookup') ||
        s.contains('ClientException');
  }

  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    if (_loading || _game == null) {
      return Scaffold(
        backgroundColor: AppColors.bgDark,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.neonGreen)),
      );
    }

    final gs = _game!.gameState;
    final isMyTurn = gs.currentTurn == _myId && gs.phase == 'playing';
    final myPlayer = gs.players[_myId];
    final canHit =
        isMyTurn && myPlayer != null && myPlayer.hand.canHit && !_acting;
    final canStand = isMyTurn &&
        myPlayer != null &&
        myPlayer.hand.status == 'playing' &&
        !_acting;

    return Scaffold(
      backgroundColor: const Color(0xFF06381A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A5227), Color(0xFF063317)],
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('♠', style: TextStyle(color: Colors.white, fontSize: 18)),
            SizedBox(width: 8),
            Text('Blackjack',
                style: TextStyle(
                    fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
        centerTitle: true,
        actions: [
          if (isMyTurn && _countdown > 0)
            Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                  child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _countdown <= 5
                      ? AppColors.neonRed.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _countdown <= 5
                        ? AppColors.neonRed.withValues(alpha: 0.6)
                        : Colors.white24,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 13,
                        color: _countdown <= 5
                            ? Colors.redAccent
                            : Colors.white70),
                    const SizedBox(width: 4),
                    Text('${_countdown}s',
                        style: TextStyle(
                            color: _countdown <= 5
                                ? Colors.redAccent
                                : Colors.white70,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              )),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Feutre casino : halo vert radial + degrade profond.
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.35),
                radius: 1.1,
                colors: [Color(0xFF14713A), Color(0xFF06381A)],
                stops: [0, 0.9],
              ),
            ),
          ),
          Positioned(
              top: -50, left: -40, child: _ambientBlob(AppColors.neonGreen, 180)),
          Positioned(
              bottom: 30,
              right: -50,
              child: _ambientBlob(AppColors.neonYellow, 160)),
          // Rail lumineux + vignette de table (profondeur du feutre)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.3),
                    radius: 1.1,
                    colors: [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x66021109),
                    ],
                    stops: [0.0, 0.62, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const ConnectivityBanner(),
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
                          child: _actionButton(
                            label: AppLocalizations.of(context)!.gameHit,
                            icon: Icons.add_rounded,
                            color: AppColors.neonGreen,
                            textColor: Colors.black,
                            loading: _pendingAction == 'hit',
                            onPressed: canHit ? _hit : null,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _actionButton(
                            label: AppLocalizations.of(context)!.gameStand,
                            icon: Icons.pan_tool_rounded,
                            color: AppColors.neonRed,
                            textColor: Colors.white,
                            loading: _pendingAction == 'stand',
                            onPressed: canStand ? _stand : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (gs.phase == 'dealer_turn' && !gs.isFinished)
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        AppLocalizations.of(context)!.gameDealerPlaying,
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tache de lumiere floue purement decorative.
  Widget _ambientBlob(Color color, double size) {
    return IgnorePointer(
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
            ),
          ),
        ),
      ),
    );
  }

  /// Bouton d'action habille (glow neon + icone), fallback loader.
  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color textColor,
    required bool loading,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.55,
      duration: const Duration(milliseconds: 200),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 16)]
              : null,
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.5),
            elevation: 0,
            padding: EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: textColor))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: textColor, size: 20),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                  ],
                ),
        ),
      ),
    );
  }

  /// Panneau en verre depoli (glassmorphism) reutilise pour dealer/main.
  Widget _glassPanel({
    required Widget child,
    required EdgeInsets margin,
    required EdgeInsets padding,
    Color? glow,
  }) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.18),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: (glow ?? Colors.white).withValues(alpha: glow != null ? 0.6 : 0.12),
                width: glow != null ? 1.6 : 1,
              ),
              boxShadow: glow != null
                  ? [BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 20)]
                  : null,
            ),
            child: child,
          ),
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
      color = AppColors.neonOrange;
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
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.08),
        ]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildDealerSection(BJGameState gs) {
    final dealer = gs.dealerHand;
    final hideSecond = gs.phase == 'playing' && !gs.isFinished;
    return _glassPanel(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(AppLocalizations.of(context)!.gameDealer,
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2)),
          SizedBox(height: 10),
          BJHandWidget(
              cards: dealer.cards, hideSecond: hideSecond, cardWidth: 48),
          SizedBox(height: 8),
          if (!hideSecond && dealer.cards.isNotEmpty)
            _scoreBadge('Score ${dealer.score}', Colors.white70),
        ],
      ),
    );
  }

  Widget _scoreBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }

  Widget _buildOtherPlayers(BJGameState gs) {
    final others = gs.players.entries.where((e) => e.key != _myId).toList();
    if (others.isEmpty) return SizedBox.shrink();

    return Container(
      height: 62,
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: others.map((e) {
          final p = e.value;
          final isActive = gs.currentTurn == e.key;
          return Container(
            margin: EdgeInsets.only(right: 8),
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isActive ? 0.12 : 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? AppColors.neonGreen
                    : Colors.white.withValues(alpha: 0.1),
                width: isActive ? 1.6 : 0.8,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                          color: AppColors.neonGreen.withValues(alpha: 0.35),
                          blurRadius: 14)
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(p.username,
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                      maxLines: 1),
                  Text('${p.hand.score}',
                      style: TextStyle(color: Colors.white54, fontSize: 10)),
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
    return _glassPanel(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(14),
      glow: isActive ? AppColors.neonGreen : null,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(AppLocalizations.of(context)!.gameYou,
                  style: TextStyle(
                      color: AppColors.neonGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _scoreColor(me.hand).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: _scoreColor(me.hand).withValues(alpha: 0.5),
                      width: 0.8),
                ),
                child: Text('${me.hand.score}',
                    style: TextStyle(
                        color: _scoreColor(me.hand),
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
              ),
            ],
          ),
          SizedBox(height: 10),
          BJHandWidget(cards: me.hand.cards, cardWidth: 55),
          if (me.hand.status != 'playing')
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                me.hand.status == 'bust'
                    ? 'BUST !'
                    : me.hand.status == 'blackjack'
                        ? 'BLACKJACK !'
                        : me.hand.status == 'stand'
                            ? 'Stand'
                            : me.hand.status.toUpperCase(),
                style: TextStyle(
                    color: me.hand.status == 'bust'
                        ? Colors.redAccent
                        : me.hand.status == 'blackjack'
                            ? AppColors.neonYellow
                            : Colors.white54,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    fontSize: 15),
              ),
            ),
        ],
      ),
    );
  }

  Color _scoreColor(BJHand hand) {
    if (hand.isBust) return Colors.redAccent;
    if (hand.isBlackjack) return AppColors.neonYellow;
    if (hand.score >= 17) return AppColors.neonOrange;
    return AppColors.neonGreen;
  }

  void _showResultDialog() {
    if (_game == null) return;
    final gs = _game!.gameState;
    final result = gs.results[_myId] ?? 'lost';
    final isWin = result == 'won';
    final isPush = result == 'push';
    final pot = _game!.betAmount * _game!.playerCount;

    try {
      context.read<WalletProvider>().refresh();
    } catch (_) {}

    if (isWin) {
      AudioService.instance.playWin();
    } else if (isPush) {
      AudioService.instance.playResult();
    } else {
      AudioService.instance.playLose();
    }

    final accent = isWin
        ? AppColors.neonYellow
        : isPush
            ? AppColors.neonOrange
            : AppColors.neonRed;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) {
        // Auto-continue après 5s
        final autoTimer = Timer(Duration(seconds: 5), () {
          if (mounted) _autoContinue(ctx);
        });

        return PopScope(
          onPopInvokedWithResult: (_, __) => autoTimer.cancel(),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 36),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.bgCard.withValues(alpha: 0.96),
                        AppColors.bgBlueNight.withValues(alpha: 0.96),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: accent.withValues(alpha: 0.5), width: 1.2),
                    boxShadow: [
                      BoxShadow(
                          color: accent.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 1),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          isWin
                              ? Icons.emoji_events_rounded
                              : isPush
                                  ? Icons.handshake_rounded
                                  : Icons.close_rounded,
                          color: accent,
                          size: 44,
                          shadows: [Shadow(color: accent, blurRadius: 18)]),
                      const SizedBox(height: 10),
                      Text(
                          isWin
                              ? 'Victoire !'
                              : isPush
                                  ? 'Égalité'
                                  : 'Défaite',
                          style: TextStyle(
                              color: accent,
                              fontSize: 22,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Text(
                          'Dealer: ${gs.dealerHand.score}  |  Toi: ${gs.players[_myId]?.hand.score ?? 0}',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 15)),
                      if (isWin) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.neonGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: AppColors.neonGreen
                                    .withValues(alpha: 0.5)),
                          ),
                          child: Text('+$pot FCFA',
                              style: TextStyle(
                                  color: AppColors.neonGreen,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900)),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(AppLocalizations.of(context)!.gameNextRound,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () {
                          autoTimer.cancel();
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                        },
                        child: Text(AppLocalizations.of(context)!.gameQuit,
                            style: TextStyle(
                                color: AppColors.neonRed,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
      try {
        Navigator.pop(ctx);
      } catch (_) {}
      if (result == 'ended') {
        Navigator.pop(context);
      } else {
        _showingResult = false;
        try {
          context.read<WalletProvider>().refresh();
        } catch (_) {}
        _game = await _svc.getGame(widget.gameId);
        if (mounted) setState(() {});
        _startTimer();
      }
    } catch (_) {
      if (mounted) {
        try {
          Navigator.pop(ctx);
        } catch (_) {}
        Navigator.pop(context);
      }
    }
  }
}

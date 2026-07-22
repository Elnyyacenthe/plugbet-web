// ============================================================
// PILE OU FACE — Écran de jeu (duel)
// ============================================================
// >>> DESIGN PREMIUM <<<
// Seul l'habillage visuel a ete retravaille (fond degrade profond,
// blobs neon, piece a halo dore, cartes joueurs glassmorphism, boutons
// neon, dialogue premium). Toute la logique de jeu (gameId, service,
// realtime, animation flip, RPC chooseSide, providers, callbacks...)
// est strictement identique a l'original.
// ============================================================

import 'dart:async';
import 'dart:math';
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
import '../models/coinflip_models.dart';
import '../services/coinflip_service.dart';
import '../../../services/network_retry.dart';
import '../../../widgets/connectivity_banner.dart';
import '../../../widgets/network_lost_overlay.dart';

class CFGameScreen extends StatefulWidget {
  final String gameId;
  const CFGameScreen({super.key, required this.gameId});
  @override
  State<CFGameScreen> createState() => _CFGameScreenState();
}

class _CFGameScreenState extends State<CFGameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _svc = CoinflipService.instance;
  CFGame? _game;
  bool _loading = true;
  bool _choosing = false;
  String? _pendingSide;
  RealtimeChannel? _channel;
  bool _showingResult = false;
  Timer? _pollTimer; // fallback si realtime meurt

  // Animation pièce
  late AnimationController _flipCtrl;
  int _flipCount = 0;

  String get _myId => _svc.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _initAudio();
    WidgetsBinding.instance.addObserver(this);
    _flipCtrl =
        AnimationController(vsync: this, duration: Duration(milliseconds: 800))
          ..addListener(() {
            setState(() {});
          });
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
    await AudioService.instance.configureGame('coinflip');
    AudioService.instance.startBackgroundMusic();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour foreground : refetch pour rattraper les events realtime
    // perdus pendant le background.
    if (state == AppLifecycleState.resumed &&
        !(_game?.gameState.isFinished ?? false)) {
      _refetchNow();
    }
  }

  Future<void> _refetchNow() async {
    final fresh = await _svc.getGame(widget.gameId);
    if (fresh != null && mounted) _onUpdate(fresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flipCtrl.dispose();
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
    _game = await _svc.getGame(widget.gameId);
    _channel = _svc.subscribeGame(
      widget.gameId,
      _onUpdate,
      onConnectionLost: _startPollingFallback,
    );
    if (mounted) setState(() => _loading = false);
  }

  /// Active un polling toutes les 2s si le realtime meurt.
  /// Auto-stop quand le game est fini.
  void _startPollingFallback() {
    if (_pollTimer != null && _pollTimer!.isActive) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted || (_game?.gameState.isFinished ?? false)) {
        t.cancel();
        _pollTimer = null;
        return;
      }
      final fresh = await _svc.getGame(widget.gameId);
      if (fresh != null) _onUpdate(fresh);
    });
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
    AudioService.instance.playCoinFlip();
    _flipCtrl.repeat();
    Future.delayed(Duration(seconds: 3), () {
      _flipCtrl.stop();
      if (mounted) setState(() {});
    });
  }

  Future<void> _choose(String side) async {
    if (_choosing) return;
    setState(() {
      _choosing = true;
      _pendingSide = side;
    });
    // request_id STABLE genere hors du closure -> reutilise a chaque
    // retry pour que le wrapper *_idem deduplique cote serveur.
    final reqId =
        '$_myId-${widget.gameId}-$side-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await NetworkRetry.run(
        () => _svc.chooseSide(widget.gameId, side, requestId: reqId),
        label: 'cf_choose_side',
      );
      AudioService.instance.playChipPlace();
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('SocketException') ||
                e.toString().contains('TimeoutException')
            ? 'Connexion perdue — reessaie'
            : '$e';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted)
        setState(() {
          _choosing = false;
          _pendingSide = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) =>
      NetworkLostOverlay(child: _buildInner(context));

  Widget _buildInner(BuildContext context) {
    if (_loading || _game == null) {
      return Scaffold(
          backgroundColor: AppColors.bgDark,
          body: Center(
              child: CircularProgressIndicator(color: AppColors.neonYellow)));
    }

    final gs = _game!.gameState;
    final myPlayer = gs.players[_myId];
    final hasChosen = myPlayer?.hasChosen ?? false;
    final isWinner = gs.winnerId == _myId;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.bgBlueNight, AppColors.bgDark],
              ),
            ),
          ),
          title: Text(AppLocalizations.of(context)!.gameCoinflipTitle,
              style: TextStyle(fontWeight: FontWeight.w900)),
          centerTitle: true,
          actions: [
            Padding(
                padding: EdgeInsets.only(right: 12),
                child: Center(
                    child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                            color: AppColors.neonYellow.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.neonYellow
                                    .withValues(alpha: 0.4),
                                width: 0.8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.savings_rounded,
                              size: 14, color: AppColors.neonYellow),
                          const SizedBox(width: 5),
                          Text(
                              '${AppLocalizations.of(context)!.gamePot}: ${_game!.pot}',
                              style: TextStyle(
                                  color: AppColors.neonYellow,
                                  fontWeight: FontWeight.w800))
                        ]))))
          ]),
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: AppColors.bgGradient)),
          Positioned(
              top: -40, right: -50, child: _ambientBlob(AppColors.neonBlue, 190)),
          Positioned(
              bottom: 20,
              left: -40,
              child: _ambientBlob(AppColors.neonYellow, 170)),
          SafeArea(
              child: Column(children: [
            const ConnectivityBanner(),
            // Status
            _buildStatusBar(gs, hasChosen, isWinner),

            Spacer(),

            // Pièce
            _buildCoin(gs),

            SizedBox(height: 28),

            // Joueurs
            _buildPlayers(gs),

            Spacer(),

            // Boutons choix
            if (gs.phase == 'choosing' && !hasChosen)
              Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(children: [
                    Expanded(
                        child: _choiceButton(
                            'PILE', 'pile', AppColors.neonYellow)),
                    SizedBox(width: 16),
                    Expanded(
                        child:
                            _choiceButton('FACE', 'face', AppColors.neonBlue)),
                  ])),

            if (hasChosen && gs.phase == 'choosing')
              Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.neonGreen.withValues(alpha: 0.4),
                          width: 0.8),
                    ),
                    child: Text(
                        '${AppLocalizations.of(context)!.gameYouChose}: ${myPlayer!.choice?.toUpperCase() ?? "?"}',
                        style: TextStyle(
                            color: AppColors.neonGreen,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  )),

            // Résultat
            if (gs.isFinished)
              Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Container(
                      padding: EdgeInsets.all(18),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            (isWinner ? AppColors.neonGreen : AppColors.neonRed)
                                .withValues(alpha: 0.22),
                            (isWinner ? AppColors.neonGreen : AppColors.neonRed)
                                .withValues(alpha: 0.08),
                          ]),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: (isWinner
                                      ? AppColors.neonGreen
                                      : AppColors.neonRed)
                                  .withValues(alpha: 0.5),
                              width: 1)),
                      child: Column(children: [
                        Text(
                            '${AppLocalizations.of(context)!.gameResult}: ${gs.result?.toUpperCase() ?? "?"}',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 8),
                        Text(
                            isWinner
                                ? '+${_game!.pot} FCFA'
                                : '-${_game!.betAmount} FCFA',
                            style: TextStyle(
                                color: isWinner
                                    ? AppColors.neonGreen
                                    : Colors.redAccent,
                                fontSize: 26,
                                fontWeight: FontWeight.w900)),
                      ]))),
          ])),
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

  Widget _buildStatusBar(CFGameState gs, bool hasChosen, bool isWinner) {
    final color = gs.phase == 'choosing'
        ? AppColors.neonBlue
        : gs.phase == 'flipping'
            ? AppColors.neonYellow
            : isWinner
                ? AppColors.neonGreen
                : AppColors.neonRed;
    final msg = gs.phase == 'choosing'
        ? (hasChosen ? 'En attente de l\'adversaire...' : 'Choisis ton côté !')
        : gs.phase == 'flipping'
            ? 'La pièce tourne...'
            : isWinner
                ? 'Tu as gagné !'
                : 'Tu as perdu...';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.08),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(msg,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 16)),
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
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.3),
            colors: [
              Color(0xFFFFF3B0),
              Color(0xFFFFD700),
              Color(0xFFDAA520),
              Color(0xFFB8860B)
            ],
            stops: const [0, 0.4, 0.75, 1],
          ),
          border: Border.all(color: Color(0xFFFFF3B0), width: 5),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.55),
                blurRadius: 34,
                spreadRadius: 2),
            const BoxShadow(
                color: Colors.black38, blurRadius: 16, offset: Offset(0, 10)),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Tranche cannelee + anneaux graves (relief frappe)
            const Positioned.fill(child: CustomPaint(painter: _CoinFacePainter())),
            // Glyphe embosse (P / F / ?)
            Text(
              showResult ? (gs.result == 'pile' ? 'P' : 'F') : '?',
              style: const TextStyle(
                fontSize: 62,
                fontWeight: FontWeight.w900,
                color: Color(0xFF6E4A00),
                shadows: [
                  // Highlight haut-gauche + ombre bas-droite = emboss
                  Shadow(
                      color: Color(0xCCFFF7D6),
                      offset: Offset(-1.5, -1.5),
                      blurRadius: 1),
                  Shadow(
                      color: Color(0x99321F00),
                      offset: Offset(2, 2),
                      blurRadius: 2),
                ],
              ),
            ),
          ],
        ),
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
          final accent = isMe ? AppColors.neonGreen : AppColors.neonBlue;
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: isMe ? 0.14 : 0.10),
                        Colors.white.withValues(alpha: 0.03),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: won
                            ? AppColors.neonYellow
                            : accent.withValues(alpha: 0.35),
                        width: won ? 2 : 1),
                    boxShadow: won
                        ? [
                            BoxShadow(
                                color: AppColors.neonYellow
                                    .withValues(alpha: 0.45),
                                blurRadius: 18)
                          ]
                        : null),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: accent.withValues(alpha: 0.5),
                            blurRadius: 12)
                      ],
                    ),
                    child: CircleAvatar(
                        radius: 22,
                        backgroundColor: accent,
                        child: Text(p.username[0].toUpperCase(),
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900))),
                  ),
                  SizedBox(height: 6),
                  Text(isMe ? 'Toi' : p.username,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                  if (p.hasChosen)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle,
                          color: AppColors.neonGreen, size: 16),
                    ),
                  if (won)
                    Icon(Icons.workspace_premium_rounded,
                        color: AppColors.neonYellow,
                        size: 20,
                        shadows: [
                          Shadow(
                              color:
                                  AppColors.neonYellow.withValues(alpha: 0.8),
                              blurRadius: 10)
                        ]),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _choiceButton(String label, String side, Color color) {
    final isPending = _pendingSide == side;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: _choosing
            ? null
            : [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 18)],
      ),
      child: ElevatedButton(
        onPressed: _choosing ? null : () => _choose(side),
        style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.5),
            elevation: 0,
            padding: EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16))),
        child: isPending
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black)),
                SizedBox(width: 10),
                Text('Envoi…',
                    style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
              ])
            : Text(label,
                style: TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
      ),
    );
  }

  void _showResult() {
    if (_game == null) return;
    final isWinner = _game!.gameState.winnerId == _myId;
    try {
      context.read<WalletProvider>().refresh();
    } catch (_) {}

    if (isWinner) {
      AudioService.instance.playWin();
    } else {
      AudioService.instance.playResult();
    }

    final accent = isWinner ? AppColors.neonYellow : AppColors.neonRed;

    showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.7),
        builder: (ctx) {
          final autoTimer = Timer(Duration(seconds: 5), () {
            if (mounted) _cfAutoContinue(ctx);
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
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          isWinner
                              ? Icons.emoji_events_rounded
                              : Icons.close_rounded,
                          color: accent,
                          size: 44,
                          shadows: [Shadow(color: accent, blurRadius: 18)]),
                      const SizedBox(height: 10),
                      Text(isWinner ? 'Victoire !' : 'Défaite',
                          style: TextStyle(
                              color: accent,
                              fontSize: 22,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Text(
                          '${AppLocalizations.of(context)!.gameResult}: ${_game!.gameState.result?.toUpperCase() ?? "?"}',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 16)),
                      if (isWinner) ...[
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
                          child: Text('+${_game!.pot} FCFA',
                              style: TextStyle(
                                  color: AppColors.neonGreen,
                                  fontSize: 22,
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
                                  fontWeight: FontWeight.w700))),
                    ]),
                  ),
                ),
              ),
            ),
          );
        });
  }

  Future<void> _cfAutoContinue(BuildContext ctx) async {
    if (!mounted) return;
    try {
      final r = await _svc.autoContinue(widget.gameId);
      if (!mounted) return;
      try {
        Navigator.pop(ctx);
      } catch (_) {}
      if (r == 'ended') {
        Navigator.pop(context);
      } else {
        _showingResult = false;
        try {
          context.read<WalletProvider>().refresh();
        } catch (_) {}
        _game = await _svc.getGame(widget.gameId);
        if (mounted) setState(() {});
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

/// Frappe de la piece : tranche cannelee (reeded edge) + anneaux graves.
/// Purement decoratif — ajoute du relief a la piece doree.
class _CoinFacePainter extends CustomPainter {
  const _CoinFacePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    // Tranche cannelee : petits traits radiaux sur le pourtour
    final ridgeDark = Paint()
      ..color = const Color(0xFF8A5A00).withValues(alpha: 0.6)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final ridgeLight = Paint()
      ..color = const Color(0xFFFFF3B0).withValues(alpha: 0.7)
      ..strokeWidth = 1.0;
    const n = 72;
    for (int i = 0; i < n; i++) {
      final a = i * 2 * pi / n;
      final p1 = Offset(center.dx + r * 0.90 * cos(a), center.dy + r * 0.90 * sin(a));
      final p2 = Offset(center.dx + r * 0.99 * cos(a), center.dy + r * 0.99 * sin(a));
      canvas.drawLine(p1, p2, i.isEven ? ridgeDark : ridgeLight);
    }

    // Anneau grave (double liseret bevel : ombre + lumiere)
    canvas.drawCircle(
      center,
      r * 0.80,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = const Color(0xFF8A5A00).withValues(alpha: 0.75),
    );
    canvas.drawCircle(
      center,
      r * 0.77,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0xFFFFF7D6).withValues(alpha: 0.55),
    );

    // Deux petites etoiles gravees (haut et bas) pour l'ornement
    _star(canvas, Offset(center.dx, center.dy - r * 0.62), r * 0.07);
    _star(canvas, Offset(center.dx, center.dy + r * 0.62), r * 0.07);

    // Reflet vitre haut-gauche (matiere metal)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * 0.7),
      pi * 1.05,
      pi * 0.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  void _star(Canvas canvas, Offset c, double rad) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final a = -pi / 2 + i * pi / 5;
      final rr = i.isEven ? rad : rad * 0.45;
      final p = Offset(c.dx + rr * cos(a), c.dy + rr * sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(
        path, Paint()..color = const Color(0xFF8A5A00).withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(covariant _CoinFacePainter old) => false;
}

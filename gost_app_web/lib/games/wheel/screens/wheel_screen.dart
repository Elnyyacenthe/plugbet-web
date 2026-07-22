// ============================================================
// WheelScreen — Plugbet Wheel (multi-mise + spin server-side)
// ============================================================
// Layout :
//   Top bar    : Balance + Win + Total Bet
//   Centre     : roue 48 segments + pointeur
//   Mid        : 6 tuiles de mise (1/2/5/10/20/40)
//   Bottom     : chip selector + bouton SPIN (hold 2s = auto-spin)
//
// >>> DESIGN PREMIUM <<<
// Seul l'habillage visuel a ete retravaille (gradients, glow neon,
// glassmorphism via BackdropFilter, badges, micro-animations). Toute
// la logique de jeu (gameId, room, gameState, providers, RPC, timers,
// callbacks onPressed/onTap...) est strictement identique a l'original.
// ============================================================

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../theme/app_theme.dart';
import '../models/wheel_models.dart';
import '../providers/wheel_provider.dart';
import '../widgets/wheel_widget.dart';
import '../widgets/bet_tile.dart';
import '../widgets/amount_input.dart';
import '../../../services/audio_service.dart';

class WheelScreen extends StatefulWidget {
  const WheelScreen({super.key});

  @override
  State<WheelScreen> createState() => _WheelScreenState();
}

class _WheelScreenState extends State<WheelScreen>
    with TickerProviderStateMixin {
  late final WheelProvider _state;
  late final AnimationController _spinBtnCtrl;

  // Resultat affiche apres la fin de l'animation (decouple du provider
  // qui le set des que la RPC repond).
  int? _displayedTargetSegment;
  int? _winningTileHighlight;
  int _lastWinDisplay = 0;

  /// Multiplicateur courant a afficher en badge (1 si pas de free spin).
  int _activeMultiplier = 1;

  bool _autoSpinActive = false;
  Timer? _autoSpinHoldTimer;

  @override
  void initState() {
    super.initState();
    _initAudio();
    final wallet = context.read<WalletProvider>();
    _state = WheelProvider(wallet: wallet);
    _state.addListener(_onState);
    wallet.addListener(_onWallet);
    _spinBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  Future<void> _initAudio() async {
    await AudioService.instance.configureGame('wheel');
    AudioService.instance.startBackgroundMusic();
  }

  @override
  void dispose() {
    _autoSpinHoldTimer?.cancel();
    _state.removeListener(_onState);
    _state.wallet.removeListener(_onWallet);
    _state.dispose();
    _spinBtnCtrl.dispose();
    AudioService.instance.stopBackgroundMusic();
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
    final err = _state.error;
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: AppColors.neonRed,
        duration: const Duration(seconds: 2),
      ));
      _state.clearError();
    }
  }

  void _onWallet() {
    if (mounted) setState(() {});
  }

  Future<void> _doSpin() async {
    if (_state.spinning) return;
    if (!_state.canSpin) return;
    HapticFeedback.lightImpact();
    AudioService.instance.playSpin();

    setState(() {
      _winningTileHighlight = null;
      _activeMultiplier = 1;
    });

    final r = await _state.spin();
    if (r == null || !mounted) return;

    await _animateAndHandle(r);
  }

  /// Anime la roue vers r.segment, attend la fin, gere :
  ///   - Si segment special 2x/7x -> overlay "FREE SPIN" + auto-call
  ///     processPendingFreeSpin (cascade jusqu'a cap=3).
  ///   - Sinon : highlight tile, auto-spin si actif.
  Future<void> _animateAndHandle(WheelSpinResult r) async {
    setState(() => _displayedTargetSegment = r.segment);

    await Future.delayed(const Duration(milliseconds: 4300));
    if (!mounted) return;

    setState(() {
      _winningTileHighlight = r.isSpecial ? null : r.winningTile;
      _lastWinDisplay = r.winnings > 0 ? r.winnings : _lastWinDisplay;
      _activeMultiplier = r.multiplier;
    });
    if (r.isWin) {
      HapticFeedback.mediumImpact();
      AudioService.instance.playWin();
    } else {
      AudioService.instance.playLand();
    }

    // Si la roue est tombee sur 2x/7x, on declenche le free spin.
    final fs = _state.pendingFreeSpin;
    if (fs != null) {
      HapticFeedback.heavyImpact();
      await _showFreeSpinOverlay(fs);
      if (!mounted) return;
      // Reset l'animation, puis lance le free spin
      setState(() => _displayedTargetSegment = null);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final fsResult = await _state.processPendingFreeSpin();
      if (fsResult == null || !mounted) return;
      // Recursive : meme logique, peut cascader
      await _animateAndHandle(fsResult);
      return;
    }

    // Auto-spin si actif (et pas de free spin en cours)
    if (_autoSpinActive) {
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || !_autoSpinActive) return;
      _state.repeatLastBets();
      setState(() {
        _displayedTargetSegment = null;
        _activeMultiplier = 1;
      });
      _doSpin();
    } else {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() {
        _displayedTargetSegment = null;
        _activeMultiplier = 1;
      });
    }
  }

  /// Overlay "FREE SPIN ×N" anime, dismissible apres 1.8s ou au tap.
  Future<void> _showFreeSpinOverlay(WheelFreeSpin fs) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 1800), () {
          // ignore: use_build_context_synchronously
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.7, end: 1.0),
              duration: const Duration(milliseconds: 420),
              curve: Curves.elasticOut,
              builder: (_, scale, child) => Transform.scale(
                scale: scale,
                child: child,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 36, vertical: 28),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF2E1565).withValues(alpha: 0.85),
                          const Color(0xFF0E0418).withValues(alpha: 0.9),
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.neonYellow.withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neonYellow.withValues(alpha: 0.35),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        '🎁',
                        style: TextStyle(
                          fontSize: 70,
                          shadows: [
                            Shadow(color: AppColors.neonYellow, blurRadius: 24),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ShaderMask(
                        shaderCallback: (rect) => LinearGradient(
                          colors: [
                            AppColors.neonYellow,
                            const Color(0xFFFFF59D),
                          ],
                        ).createShader(rect),
                        child: const Text(
                          'FREE SPIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 11),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF19B562), Color(0xFF00A854)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.neonGreen.withValues(alpha: 0.55),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        child: Text(
                          '× ${fs.multiplier}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        fs.cascadeDepth > 1
                            ? 'Cascade ${fs.cascadeDepth}/3'
                            : 'Tour gratuit',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _startSpinHold() {
    if (_state.spinning || !_state.canSpin) return;
    _autoSpinHoldTimer?.cancel();
    _autoSpinHoldTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _autoSpinActive = true);
      HapticFeedback.heavyImpact();
      _doSpin();
    });
  }

  void _endSpinHold() {
    final wasLong = _autoSpinHoldTimer?.isActive == false;
    _autoSpinHoldTimer?.cancel();
    if (!wasLong && !_autoSpinActive) {
      _doSpin();
    }
  }

  void _stopAutoSpin() {
    setState(() => _autoSpinActive = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0418),
      body: Stack(
        children: [
          // Fond degrade profond
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topCenter,
                radius: 1.3,
                colors: [Color(0xFF2E1565), Color(0xFF0E0418)],
                stops: [0, 0.7],
              ),
            ),
          ),
          // Blobs neon decoratifs (glassmorphism ambiant, purement visuel)
          Positioned(
            top: -60,
            left: -40,
            child: _ambientBlob(const Color(0xFF00E5FF), 180),
          ),
          Positioned(
            bottom: 40,
            right: -50,
            child: _ambientBlob(const Color(0xFFFF1744), 200),
          ),
          Positioned(
            top: 220,
            right: -30,
            child: _ambientBlob(const Color(0xFFFFD600), 140),
          ),
          SafeArea(
            child: Column(children: [
              _buildTopBar(),
              const SizedBox(height: 8),
              Expanded(child: Center(child: _buildWheel())),
              _buildTilesRow(),
              const SizedBox(height: 12),
              _buildChipsAndSpinRow(),
              const SizedBox(height: 8),
            ]),
          ),
        ],
      ),
    );
  }

  /// Tache de lumiere floue purement decorative (aucune interaction,
  /// aucun impact sur la logique).
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
              color: color.withValues(alpha: 0.18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(children: [
        _glassIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        _miniStat('Balance', '${_state.balance}', AppColors.neonGreen),
        const SizedBox(width: 10),
        if (_activeMultiplier > 1) ...[
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.elasticOut,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE91E63), Color(0xFF6A1B9A)],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE91E63).withValues(alpha: 0.6),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Text(
                '× $_activeMultiplier',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ] else ...[
          _miniStat('Win', '$_lastWinDisplay', AppColors.neonYellow),
          const SizedBox(width: 10),
        ],
        _miniStat('Bet', '${_state.totalBet}', AppColors.neonOrange),
        const SizedBox(width: 6),
        _glassIconButton(
          icon: Icons.info_outline,
          onPressed: _showRules,
          tooltip: 'Comment jouer',
        ),
      ]),
    );
  }

  /// Bouton icone habille en verre depoli avec liseret subtil.
  Widget _glassIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
            tooltip: tooltip,
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Text(
                value,
                key: ValueKey(value),
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.w900),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildWheel() {
    final w = MediaQuery.of(context).size.width;
    final size = (w - 60).clamp(220.0, 320.0);
    return WheelWidget(
      targetSegment: _displayedTargetSegment,
      spinning: _state.spinning,
      size: size,
    );
  }

  Widget _buildTilesRow() {
    final w = MediaQuery.of(context).size.width;
    final tileWidth = (w - 32 - 5 * 6) / 6;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: WheelTile.values.map((t) {
          final chips = _state.chipsByTile[t] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: SizedBox(
              width: tileWidth,
              height: 76,
              child: AnimatedScale(
                scale: _winningTileHighlight == t.value ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: BetTile(
                  tile: t,
                  chips: chips,
                  isWinning: _winningTileHighlight == t.value,
                  disabled: _state.spinning,
                  onTap: () => _state.addChip(t),
                  onLongPress: () => _state.clearTile(t),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChipsAndSpinRow() {
    final canSpin = _state.canSpin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Amount input (mise libre + quick chips)
        Expanded(
          child: AmountInput(
            current: _state.currentAmount,
            disabled: _state.spinning,
            onChanged: _state.setCurrentAmount,
          ),
        ),
        const SizedBox(width: 8),
        // Reset
        if (_state.totalBet > 0 && !_state.spinning)
          _glassIconButton(
            icon: Icons.refresh,
            onPressed: _state.clearAll,
            tooltip: 'Tout effacer',
          ),
        // Stop auto-spin
        if (_autoSpinActive) ...[
          const SizedBox(width: 4),
          _glassIconButton(
            icon: Icons.stop_circle,
            onPressed: _stopAutoSpin,
            tooltip: 'Stop auto-spin',
          ),
        ],
        const SizedBox(width: 6),
        // SPIN button
        GestureDetector(
          onTapDown: (_) => _startSpinHold(),
          onTapUp: (_) => _endSpinHold(),
          onTapCancel: () => _autoSpinHoldTimer?.cancel(),
          child: AnimatedBuilder(
            animation: _spinBtnCtrl,
            builder: (_, __) {
              final pulse = 1 + (canSpin ? _spinBtnCtrl.value * 0.06 : 0.0);
              return Transform.scale(
                scale: pulse,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: canSpin
                          ? [
                              const Color(0xFF4CFFA0),
                              AppColors.neonGreen,
                              const Color(0xFF00A854),
                            ]
                          : [Colors.grey.shade600, Colors.grey.shade800],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: canSpin ? 0.4 : 0.1),
                      width: 1.4,
                    ),
                    boxShadow: canSpin
                        ? [
                            BoxShadow(
                              color: AppColors.neonGreen.withValues(alpha: 0.55),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: AppColors.neonGreen.withValues(alpha: 0.25),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: _state.spinning
                        ? const SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                                strokeWidth: 3, color: Colors.black),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                const Icon(Icons.play_arrow,
                                    color: Colors.black, size: 28),
                                Text(
                                  _autoSpinActive ? 'AUTO' : 'SPIN',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  void _showRules() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF1B0E33).withValues(alpha: 0.96),
                  const Color(0xFF0E0418).withValues(alpha: 0.98),
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: AppColors.neonYellow.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )),
                      const SizedBox(height: 16),
                      const Text('🎡 Comment jouer',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      const Text(
                          '1. Choisis un jeton (25, 100, 500, 5k, 10k, 40k)',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Text(
                          '2. Tap une tuile (1, 2, 5, 10, 20, 40) pour deposer le jeton',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Text(
                          '3. Tu peux miser sur plusieurs tuiles en meme temps',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Text(
                          '4. Long press sur une tuile pour retirer les jetons',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const Text('5. Tap SPIN. Hold 2s = mode AUTO-spin',
                          style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.neonYellow.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💰 Gains',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            const Text(
                              'Si la roue s\'arrete sur un numero ou tu as mise, tu gagnes :\n'
                              '   stake × (numero + 1)\n\n'
                              'Ex : tu mises 100 sur 5, la roue tombe sur 5 -> 600 (= 5×100 gain + 100 mise).',
                              style: TextStyle(
                                  color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                          'Limites : min 25 FCFA total, max 25 000 FCFA. Max 5 000 par tuile.',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

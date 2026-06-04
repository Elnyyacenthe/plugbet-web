// ============================================================
// WheelScreen — Plugbet Wheel (multi-mise + spin server-side)
// ============================================================
// Layout :
//   Top bar    : Balance + Win + Total Bet
//   Centre     : roue 48 segments + pointeur
//   Mid        : 6 tuiles de mise (1/2/5/10/20/40)
//   Bottom     : chip selector + bouton SPIN (hold 2s = auto-spin)
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../theme/app_theme.dart';
import '../models/wheel_models.dart';
import '../providers/wheel_provider.dart';
import '../widgets/wheel_widget.dart';
import '../widgets/bet_tile.dart';
import '../widgets/chip_selector.dart';

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
    final wallet = context.read<WalletProvider>();
    _state = WheelProvider(wallet: wallet);
    _state.addListener(_onState);
    wallet.addListener(_onWallet);
    _spinBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _autoSpinHoldTimer?.cancel();
    _state.removeListener(_onState);
    _state.wallet.removeListener(_onWallet);
    _state.dispose();
    _spinBtnCtrl.dispose();
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
    if (r.isWin) HapticFeedback.mediumImpact();

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
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) {
        Future.delayed(const Duration(milliseconds: 1800), () {
          // ignore: use_build_context_synchronously
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(
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
              Text(
                'FREE SPIN',
                style: TextStyle(
                  color: AppColors.neonYellow,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: AppColors.neonYellow, blurRadius: 16),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.neonGreen,
                  borderRadius: BorderRadius.circular(14),
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
              const SizedBox(height: 12),
              Text(
                fs.cascadeDepth > 1 ? 'Cascade ${fs.cascadeDepth}/3' : 'Tour gratuit',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ]),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [Color(0xFF2E1565), Color(0xFF0E0418)],
            stops: [0, 0.7],
          ),
        ),
        child: SafeArea(child: Column(children: [
          _buildTopBar(),
          const SizedBox(height: 8),
          Expanded(child: Center(child: _buildWheel())),
          _buildTilesRow(),
          const SizedBox(height: 12),
          _buildChipsAndSpinRow(),
          const SizedBox(height: 8),
        ])),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        _miniStat('Balance', '${_state.balance}', AppColors.neonGreen),
        const SizedBox(width: 10),
        if (_activeMultiplier > 1) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE91E63), Color(0xFF6A1B9A)],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE91E63).withValues(alpha: 0.6),
                  blurRadius: 10,
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
          const SizedBox(width: 10),
        ] else ...[
          _miniStat('Win', '$_lastWinDisplay', AppColors.neonYellow),
          const SizedBox(width: 10),
        ],
        _miniStat('Bet', '${_state.totalBet}', AppColors.neonOrange),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: _showRules,
          tooltip: 'Comment jouer',
        ),
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.7),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 9, fontWeight: FontWeight.w700)),
        Text(value, style: TextStyle(
            color: color, fontSize: 14, fontWeight: FontWeight.w900)),
      ]),
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
              width: tileWidth, height: 76,
              child: BetTile(
                tile: t,
                chips: chips,
                isWinning: _winningTileHighlight == t.value,
                disabled: _state.spinning,
                onTap: () => _state.addChip(t),
                onLongPress: () => _state.clearTile(t),
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
        // Chip selector
        Expanded(
          child: ChipSelector(
            selected: _state.selectedChip,
            disabled: _state.spinning,
            onPick: _state.setSelectedChip,
          ),
        ),
        const SizedBox(width: 8),
        // Reset
        if (_state.totalBet > 0 && !_state.spinning)
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white.withValues(alpha: 0.7)),
            onPressed: _state.clearAll,
            tooltip: 'Tout effacer',
          ),
        // Stop auto-spin
        if (_autoSpinActive)
          IconButton(
            icon: Icon(Icons.stop_circle, color: AppColors.neonRed),
            onPressed: _stopAutoSpin,
            tooltip: 'Stop auto-spin',
          ),
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
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: canSpin
                          ? [AppColors.neonGreen, const Color(0xFF00A854)]
                          : [Colors.grey, Colors.grey.shade800],
                    ),
                    boxShadow: canSpin
                        ? [
                            BoxShadow(
                              color: AppColors.neonGreen.withValues(alpha: 0.5),
                              blurRadius: 18,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: _state.spinning
                        ? const SizedBox(
                            width: 30, height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.black),
                          )
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.play_arrow, color: Colors.black, size: 28),
                            Text(
                              _autoSpinActive ? 'AUTO' : 'SPIN',
                              style: const TextStyle(
                                color: Colors.black, fontSize: 11,
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
      backgroundColor: const Color(0xFF1B0E33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 16),
            const Text('🎡 Comment jouer',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            const Text('1. Choisis un jeton (25, 100, 500, 5k, 10k, 40k)',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const Text('2. Tap une tuile (1, 2, 5, 10, 20, 40) pour deposer le jeton',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const Text('3. Tu peux miser sur plusieurs tuiles en meme temps',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const Text('4. Long press sur une tuile pour retirer les jetons',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const Text('5. Tap SPIN. Hold 2s = mode AUTO-spin',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            const Text('💰 Gains',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text(
              'Si la roue s\'arrete sur un numero ou tu as mise, tu gagnes :\n'
              '   stake × (numero + 1)\n\n'
              'Ex : tu mises 100 sur 5, la roue tombe sur 5 -> 600 (= 5×100 gain + 100 mise).',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text('Limites : min 25 FCFA total, max 25 000 FCFA. Max 5 000 par tuile.',
                style: TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

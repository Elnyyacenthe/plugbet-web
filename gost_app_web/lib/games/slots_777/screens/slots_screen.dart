// ============================================================
// SlotsScreen — Big Win 777 (Phase 1 Demo)
// ============================================================
// Layout :
//   AppBar minimal (back + paytable info + solde)
//   Fer a cheval doree + titre BIG WIN 777
//   3 rouleaux centres
//   Bouton SPIN circulaire neon
//   BetSelector horizontal
//   Bouton refill demo (debug)
//
// Theme : fond violet sombre (#1B0E33 -> #0E0418) + dore (#FFD600)
// + rouge neon pour les 7. Conforme au brief "Big Win 777".
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../theme/app_theme.dart';
import '../models/slot_models.dart';
import '../providers/slots_provider.dart';
import '../widgets/slot_reel.dart';
import '../widgets/paytable_panel.dart';
import '../widgets/win_overlay.dart';
import '../widgets/bet_selector.dart';

class SlotsScreen extends StatefulWidget {
  const SlotsScreen({super.key});

  @override
  State<SlotsScreen> createState() => _SlotsScreenState();
}

class _SlotsScreenState extends State<SlotsScreen>
    with TickerProviderStateMixin {
  late final SlotsProvider _state;
  late final AnimationController _spinBtnCtrl;

  // Symboles affiches sur les 3 rouleaux (etat statique entre spins).
  List<SlotSymbol> _displayed = const [
    SlotSymbol.seven,
    SlotSymbol.seven,
    SlotSymbol.seven,
  ];
  // True quand un rouleau particulier est en train de tourner.
  List<bool> _spinning = const [false, false, false];

  bool _overlayShown = false;

  @override
  void initState() {
    super.initState();
    final wallet = context.read<WalletProvider>();
    _state = SlotsProvider(wallet: wallet);
    _state.addListener(_onState);
    wallet.addListener(_onWallet);
    _spinBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
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
    if (_state.balance < _state.currentBet) {
      // L'erreur sera affichee via le listener _onState (provider.error)
      return;
    }
    HapticFeedback.lightImpact();

    setState(() => _spinning = const [true, true, true]);
    final result = await _state.spin();
    if (result == null) {
      setState(() => _spinning = const [false, false, false]);
      return;
    }

    // Affichage : on cible les vrais symboles + arret en cascade
    setState(() => _displayed = result.reels);
    // Reel 1 stoppe a 1.5s, reel 2 a 1.8s, reel 3 a 2.1s
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() => _spinning = [false, _spinning[1], _spinning[2]]);
    });
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _spinning = [false, false, _spinning[2]]);
    });
    Future.delayed(const Duration(milliseconds: 2100), () {
      if (!mounted) return;
      setState(() => _spinning = const [false, false, false]);
      if (result.isWin) {
        if (result.isJackpot) {
          HapticFeedback.heavyImpact();
        } else if (result.isBigWin) {
          HapticFeedback.mediumImpact();
        }
        _showOverlay(result);
      }
    });
  }

  void _showOverlay(result) {
    if (_overlayShown) return;
    _overlayShown = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (ctx) => WinOverlay(
        result: result,
        onDismiss: () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          _overlayShown = false;
        },
      ),
    );
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
        child: SafeArea(
          child: Column(children: [
            _buildTopBar(),
            const SizedBox(height: 8),
            _buildHorseshoeTitle(),
            const SizedBox(height: 8),
            Expanded(child: Center(child: _buildMachine())),
            _buildBottomControls(),
          ]),
        ),
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
        // Solde demo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.4), width: 0.8),
          ),
          child: Row(children: [
            Icon(Icons.account_balance_wallet,
                size: 14, color: AppColors.neonGreen),
            const SizedBox(width: 6),
            Text('${_state.balance} FCFA',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                )),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onPressed: () => PaytablePanel.show(context),
        ),
      ]),
    );
  }

  Widget _buildHorseshoeTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        // Fer a cheval (emoji + glow)
        Text(
          '🧿',
          style: TextStyle(
            fontSize: 38,
            shadows: [
              Shadow(color: AppColors.neonYellow, blurRadius: 18),
            ],
          ),
        ),
        const SizedBox(height: 2),
        ShaderMask(
          shaderCallback: (b) => const LinearGradient(
            colors: [Color(0xFFFFE082), Color(0xFFFFD600), Color(0xFFFFB300)],
          ).createShader(b),
          child: const Text(
            'BIG WIN 777',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        Text(
          'Jackpot 7-7-7',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ]),
    );
  }

  Widget _buildMachine() {
    final w = MediaQuery.of(context).size.width;
    final tile = ((w - 80) / 3).clamp(64.0, 96.0);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE082), Color(0xFFFFB300), Color(0xFF7A4F00)],
          stops: [0, 0.5, 1],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF7A4F00), width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonYellow.withValues(alpha: 0.35),
            blurRadius: 30,
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Reels
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1B0E33),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF7A4F00), width: 2),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (int i = 0; i < 3; i++) ...[
              SlotReel(
                target: _displayed[i],
                spinning: _spinning[i],
                tileHeight: tile,
                width: tile,
              ),
              if (i < 2) const SizedBox(width: 6),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        // Payline indicator
        Container(
          height: 3,
          margin: EdgeInsets.symmetric(horizontal: tile / 4),
          decoration: BoxDecoration(
            color: AppColors.neonRed,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                  color: AppColors.neonRed.withValues(alpha: 0.6),
                  blurRadius: 8),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildBottomControls() {
    final canSpin = !_state.spinning && _state.balance >= _state.currentBet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        BetSelector(
          current: _state.currentBet,
          disabled: _state.spinning,
          onChanged: _state.setBet,
        ),
        const SizedBox(height: 14),
        Row(children: [
          const SizedBox(width: 48), // spacer pour centrer le bouton SPIN
          const Spacer(),
          // Bouton SPIN circulaire
          GestureDetector(
            onTap: canSpin ? _doSpin : null,
            child: AnimatedBuilder(
              animation: _spinBtnCtrl,
              builder: (_, __) {
                final pulse = 1 + (canSpin ? _spinBtnCtrl.value * 0.06 : 0.0);
                return Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: canSpin
                            ? [AppColors.neonGreen, const Color(0xFF00A854)]
                            : [Colors.grey, Colors.grey.shade800],
                      ),
                      boxShadow: canSpin
                          ? [
                              BoxShadow(
                                color: AppColors.neonGreen.withValues(alpha: 0.5),
                                blurRadius: 20,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: _state.spinning
                          ? const SizedBox(
                              width: 36, height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 4, color: Colors.black),
                            )
                          : const Text('SPIN',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              )),
                    ),
                  ),
                );
              },
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Table des gains',
            onPressed: () => PaytablePanel.show(context),
            icon: Icon(Icons.list_alt,
                color: Colors.white.withValues(alpha: 0.8)),
          ),
        ]),
      ]),
    );
  }
}

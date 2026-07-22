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
//
// >>> DESIGN PREMIUM <<<
// Seul l'habillage visuel a ete retravaille (cabinet dore multi-couche,
// glass badges, glow neon, micro-animations). La logique de jeu -
// tokens de spin, cascade de timers (1.5s/1.8s/2.1s), conditions
// canSpin/reelsBusy, callbacks, providers - est strictement identique
// a l'original.
// ============================================================

import 'dart:ui';
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
import '../../../services/audio_service.dart';

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
  // Token incremente a chaque spin. Les Future.delayed verifient leur
  // token contre _spinToken : si different -> spin obsolete, ignore.
  int _spinToken = 0;

  bool _overlayShown = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
    final wallet = context.read<WalletProvider>();
    _state = SlotsProvider(wallet: wallet);
    _state.addListener(_onState);
    wallet.addListener(_onWallet);
    _spinBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  Future<void> _initAudio() async {
    await AudioService.instance.configureGame('slots_777');
    AudioService.instance.startBackgroundMusic();
  }

  @override
  void dispose() {
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
    // Empeche un 2e spin tant que :
    //  - la RPC du spin precedent est en cours (_state.spinning)
    //  - OU les rouleaux du spin precedent tournent encore (_spinning)
    if (_state.spinning) return;
    if (_spinning.any((b) => b)) return;
    if (_state.balance < _state.currentBet) {
      // L'erreur sera affichee via le listener _onState (provider.error)
      return;
    }
    HapticFeedback.lightImpact();
    AudioService.instance.playSpin();

    // Token pour ignorer les delayed callbacks d'un spin obsolete.
    final myToken = ++_spinToken;
    setState(() => _spinning = const [true, true, true]);
    final result = await _state.spin();
    if (myToken != _spinToken || !mounted) return;
    if (result == null) {
      setState(() => _spinning = const [false, false, false]);
      return;
    }

    // Affichage : on cible les vrais symboles + arret en cascade
    setState(() => _displayed = result.reels);
    // Reel 1 stoppe a 1.5s, reel 2 a 1.8s, reel 3 a 2.1s
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted || myToken != _spinToken) return;
      setState(() => _spinning = [false, _spinning[1], _spinning[2]]);
    });
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted || myToken != _spinToken) return;
      setState(() => _spinning = [false, false, _spinning[2]]);
    });
    Future.delayed(const Duration(milliseconds: 2100), () {
      if (!mounted || myToken != _spinToken) return;
      setState(() => _spinning = const [false, false, false]);
      if (result.isWin) {
        if (result.isJackpot) {
          HapticFeedback.heavyImpact();
          AudioService.instance.playJackpot();
        } else if (result.isBigWin) {
          HapticFeedback.mediumImpact();
          AudioService.instance.playWin();
        } else {
          AudioService.instance.playWin();
        }
        _showOverlay(result);
      }
    });
  }

  void _showOverlay(result) {
    if (_overlayShown) return;
    _overlayShown = true;
    // whenComplete : reset le flag QUEL QUE SOIT le mode de fermeture
    // (tap WinOverlay, barrier dismiss, auto-close 3s, back button...).
    // Sans ca, un dismiss par barrier laissait _overlayShown=true et
    // bloquait l'overlay des gains suivants.
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (ctx) => WinOverlay(
        result: result,
        onDismiss: () {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        },
      ),
    ).whenComplete(() {
      _overlayShown = false;
    });
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
          // Blobs neon decoratifs (glassmorphism ambiant)
          Positioned(
            top: -50,
            right: -40,
            child: _ambientBlob(const Color(0xFFFFD600), 190),
          ),
          Positioned(
            bottom: 60,
            left: -50,
            child: _ambientBlob(const Color(0xFFFF1744), 180),
          ),
          Positioned(
            top: 260,
            left: -30,
            child: _ambientBlob(const Color(0xFF00E5FF), 130),
          ),
          SafeArea(
            child: Column(children: [
              _buildTopBar(),
              const SizedBox(height: 8),
              _buildHorseshoeTitle(),
              const SizedBox(height: 8),
              Expanded(child: Center(child: _buildMachine())),
              _buildBottomControls(),
            ]),
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

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(children: [
        _glassIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        // Solde demo
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.09),
                    Colors.white.withValues(alpha: 0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.neonGreen.withValues(alpha: 0.45),
                    width: 0.9),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonGreen.withValues(alpha: 0.25),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Row(children: [
                Icon(Icons.account_balance_wallet,
                    size: 14, color: AppColors.neonGreen),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Text('${_state.balance} FCFA',
                      key: ValueKey(_state.balance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      )),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _glassIconButton(
          icon: Icons.info_outline,
          onPressed: () => PaytablePanel.show(context),
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

  Widget _buildHorseshoeTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        // Triptyque de jetons "7" neon embosses (remplace l'emoji plat)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            _SevenToken(size: 34),
            SizedBox(width: 8),
            _SevenToken(size: 42, featured: true),
            SizedBox(width: 8),
            _SevenToken(size: 34),
          ],
        ),
        const SizedBox(height: 8),
        Stack(alignment: Alignment.center, children: [
          // Outline pour renforcer la lisibilite/impact du titre
          Text(
            'BIG WIN 777',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4
                ..color = Colors.black.withValues(alpha: 0.55),
            ),
          ),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
              colors: [
                Color(0xFFFFF59D),
                Color(0xFFFFD600),
                Color(0xFFFFB300),
              ],
              stops: [0, 0.5, 1],
            ).createShader(b),
            child: const Text(
              'BIG WIN 777',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: [
                  Shadow(color: Color(0xFFFF6F00), blurRadius: 10),
                ],
              ),
            ),
          ),
        ]),
        Text(
          'Jackpot 7-7-7',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
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
      // Ombre portee du meuble (profondeur + halo dore)
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonYellow.withValues(alpha: 0.35),
            blurRadius: 40,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: CustomPaint(
        // Cadre metal brosse biseaute (relief 3D dessine)
        painter: _MetalFramePainter(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Rangee d'ampoules casino sur les bords haut/bas
              Positioned(top: -4, left: 4, right: 4, child: _bulbStrip()),
              Positioned(bottom: -4, left: 4, right: 4, child: _bulbStrip()),
              Column(mainAxisSize: MainAxisSize.min, children: [
                // Fenetre des rouleaux — ENCASTREE (inset shadow)
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF0B0620), Color(0xFF1B0E33)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF5A3800), width: 2),
                  ),
                  child: Stack(children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
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
                    // Ombre interne = effet "creuse dans le meuble"
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _InsetShadowPainter()),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                // Payline indicator
                Container(
                  height: 3,
                  margin: EdgeInsets.symmetric(horizontal: tile / 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0x00FF1744),
                        Color(0xFFFF1744),
                        Color(0x00FF1744),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.neonRed.withValues(alpha: 0.7),
                          blurRadius: 10),
                    ],
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  /// Bandeau d'ampoules casino (glow neon alterne or/blanc).
  Widget _bulbStrip() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(9, (i) => _bulb(i.isEven)),
    );
  }

  /// Petite ampoule decorative de cabinet casino (glow neon fixe).
  Widget _bulb([bool warm = true]) {
    final c = warm ? const Color(0xFFFFF59D) : const Color(0xFFFFE0B2);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [Colors.white, c]),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD600).withValues(alpha: 0.9),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    // Le bouton SPIN reste GRISE tant qu'au moins UN rouleau tourne.
    // Sans ca, l'utilisateur peut tap SPIN des que la RPC repond
    // (~500ms), avant la fin de l'animation cascade (2.1s), ce qui
    // declenchait la race condition #3 (delayed callbacks du spin
    // precedent qui resettent les reels du nouveau spin).
    final reelsBusy = _spinning.any((b) => b);
    final canSpin =
        !_state.spinning && !reelsBusy && _state.balance >= _state.currentBet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        BetSelector(
          current: _state.currentBet,
          disabled: _state.spinning || reelsBusy,
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
                    width: 98,
                    height: 98,
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
                        color:
                            Colors.white.withValues(alpha: canSpin ? 0.4 : 0.1),
                        width: 1.6,
                      ),
                      boxShadow: canSpin
                          ? [
                              BoxShadow(
                                color:
                                    AppColors.neonGreen.withValues(alpha: 0.55),
                                blurRadius: 26,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color:
                                    AppColors.neonGreen.withValues(alpha: 0.25),
                                blurRadius: 40,
                                spreadRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: _state.spinning
                          ? const SizedBox(
                              width: 36,
                              height: 36,
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
          _glassIconButton(
            icon: Icons.list_alt,
            onPressed: () => PaytablePanel.show(context),
            tooltip: 'Table des gains',
          ),
        ]),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Jeton "7" embosse (or biseaute + 7 rouge neon en relief)
// ════════════════════════════════════════════════════════════
class _SevenToken extends StatelessWidget {
  final double size;
  final bool featured;
  const _SevenToken({required this.size, this.featured = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [
            Color(0xFFFFF8E1),
            Color(0xFFFFD54A),
            Color(0xFFCC8A00),
            Color(0xFF6E4500),
          ],
          stops: [0, 0.35, 0.75, 1],
        ),
        border: Border.all(color: const Color(0xFF3E2600), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD600).withValues(alpha: featured ? 0.7 : 0.4),
            blurRadius: featured ? 16 : 9,
            spreadRadius: featured ? 1 : 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '7',
          style: TextStyle(
            fontSize: size * 0.62,
            fontWeight: FontWeight.w900,
            height: 1,
            foreground: Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF6B6B), Color(0xFFD10E2E)],
              ).createShader(Rect.fromLTWH(0, 0, size, size)),
            shadows: const [
              Shadow(color: Color(0xFFFF1744), blurRadius: 10),
              Shadow(color: Colors.black38, blurRadius: 1, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Cadre metal brosse biseaute du meuble (relief 3D)
// ════════════════════════════════════════════════════════════
class _MetalFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect, const Radius.circular(26));

    // 1) Corps or brosse (degrade diagonal + reflets verticaux)
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF3C4),
            Color(0xFFFFD54A),
            Color(0xFFCC8A00),
            Color(0xFF7A4E00),
          ],
          stops: [0, 0.3, 0.7, 1],
        ).createShader(rect),
    );
    // Reflets verticaux "metal brosse"
    final brush = Paint()..color = Colors.white.withValues(alpha: 0.06);
    for (double x = 6; x < size.width; x += 7) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), brush);
    }

    // 2) Biseau clair en haut / a gauche (lumiere)
    canvas.drawRRect(
      rrect.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFDF2), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    // 3) Biseau sombre en bas / a droite (ombre)
    canvas.drawRRect(
      rrect.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0x995A3800), Color(0x00000000)],
        ).createShader(rect),
    );
    // 4) Liseret exterieur sombre net
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF3E2600),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ════════════════════════════════════════════════════════════
// Ombre interne (fenetre rouleaux "creusee" dans le meuble)
// ════════════════════════════════════════════════════════════
class _InsetShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    // Ombre haute interne
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.black.withValues(alpha: 0.0),
          ],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

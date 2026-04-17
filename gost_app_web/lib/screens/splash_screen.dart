// ============================================================
// Plugbet – Splash Screen animé premium (style 1xBet)
// Affiche animation + progression pendant que l'app se charge
// ============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final Future<void> Function() onInit;
  final VoidCallback onReady;

  const SplashScreen({
    super.key,
    required this.onInit,
    required this.onReady,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _orbitController;
  late AnimationController _textController;
  late AnimationController _progressController;
  late AnimationController _glowController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _progressValue;
  late Animation<double> _glow;

  bool _initDone = false;
  bool _animDone = false;

  // Messages rotatifs style 1xBet (resolus a chaque build via l10n)
  int _messageIndex = 0;
  List<String> _localizedMessages(BuildContext ctx) {
    final t = AppLocalizations.of(ctx)!;
    return [
      t.splashInit,
      t.splashConnecting,
      t.splashLoadingMatches,
      t.splashLoading,
      t.splashAlmostReady,
    ];
  }

  @override
  void initState() {
    super.initState();

    // Logo scale + fade in
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _logoScale = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    // Orbite des particules autour du logo
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Texte fade + slide
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );

    // Barre de progression (piloté manuellement)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );
    _progressValue = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOutCubic,
    );

    // Glow pulsant derrière le logo
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _startSequence();
    _rotateMessages();
  }

  Future<void> _rotateMessages() async {
    const count = 5;
    for (int i = 0; i < count; i++) {
      if (!mounted || _initDone) return;
      setState(() => _messageIndex = i);
      await Future.delayed(const Duration(milliseconds: 1200));
    }
  }

  Future<void> _startSequence() async {
    // 1. Logo entry
    _logoController.forward();
    _progressController.forward();

    await Future.delayed(const Duration(milliseconds: 300));

    // 2. Texte
    _textController.forward();

    // 3. Lancer l'init reelle en parallele
    widget.onInit().then((_) {
      _initDone = true;
      _tryNavigate();
    }).catchError((_) {
      _initDone = true;
      _tryNavigate();
    });

    // 4. Duree minimum du splash pour laisser l'animation respirer
    await Future.delayed(const Duration(milliseconds: 2200));
    _animDone = true;
    _tryNavigate();
  }

  Future<void> _tryNavigate() async {
    if (_initDone && _animDone && mounted) {
      // Fade out final
      _progressController.animateTo(1.0,
          duration: const Duration(milliseconds: 300));
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) widget.onReady();
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _orbitController.dispose();
    _textController.dispose();
    _progressController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF040810),
              Color(0xFF0B1F38),
              Color(0xFF071428),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Fond : cercles radiaux lointains
            Positioned.fill(
              child: CustomPaint(painter: _BgGridPainter()),
            ),

            // Contenu central
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo + orbite + glow ──
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        _logoController,
                        _orbitController,
                        _glowController,
                      ]),
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glow derriere
                            Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.neonGreen
                                        .withValues(alpha: _glow.value * 0.4),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),

                            // Orbite externe (particules)
                            ...List.generate(3, (i) {
                              final angle = (_orbitController.value * 2 * math.pi) +
                                  (i * 2 * math.pi / 3);
                              const radius = 70.0;
                              return Transform.translate(
                                offset: Offset(
                                  radius * math.cos(angle),
                                  radius * math.sin(angle),
                                ),
                                child: Opacity(
                                  opacity: _logoOpacity.value,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.neonGreen,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.neonGreen
                                              .withValues(alpha: 0.8),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),

                            // Orbite interne (ring)
                            Transform.rotate(
                              angle: -_orbitController.value * 2 * math.pi,
                              child: Opacity(
                                opacity: _logoOpacity.value * 0.5,
                                child: Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.neonGreen
                                          .withValues(alpha: 0.3),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Logo principal
                            Transform.scale(
                              scale: _logoScale.value,
                              child: Opacity(
                                opacity: _logoOpacity.value,
                                child: Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF0F2838),
                                        Color(0xFF071928),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: AppColors.neonGreen
                                          .withValues(alpha: 0.8),
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.neonGreen
                                            .withValues(alpha: 0.5),
                                        blurRadius: 25,
                                        spreadRadius: 3,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.sports_soccer,
                                    size: 54,
                                    color: AppColors.neonGreen,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Nom de l'app ──
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textOpacity,
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [
                                Color(0xFFF0F2F5),
                                Color(0xFF00E676),
                              ],
                              stops: [0.4, 1.0],
                            ).createShader(bounds),
                            child: const Text(
                              'Plugbet',
                              style: TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -1.5,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.neonGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.neonGreen.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.neonGreen,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.neonGreen,
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'LIVE SPORTS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.neonGreen,
                                    letterSpacing: 2.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 50),

                  // ── Barre de progression ──
                  FadeTransition(
                    opacity: _textOpacity,
                    child: SizedBox(
                      width: 180,
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              AnimatedBuilder(
                                animation: _progressValue,
                                builder: (context, _) {
                                  return FractionallySizedBox(
                                    widthFactor: _progressValue.value,
                                    child: Container(
                                      height: 4,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(4),
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.neonGreen
                                                .withValues(alpha: 0.8),
                                            AppColors.neonGreen,
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.neonGreen
                                                .withValues(alpha: 0.6),
                                            blurRadius: 10,
                                            offset: const Offset(0, 0),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          // Message rotatif
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: Text(
                              _localizedMessages(context)[_messageIndex],
                              key: ValueKey(_messageIndex),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                                letterSpacing: 0.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Footer version ──
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _textOpacity,
                child: Column(
                  children: [
                    Text(
                      'PLUGBET',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withValues(alpha: 0.3),
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v1.0 • Sports & Games',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.2),
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter de fond : grille legere + cercles radiaux
class _BgGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.38);

    // 3 cercles concentriques tres discrets
    for (int i = 1; i <= 3; i++) {
      final paint = Paint()
        ..color = AppColors.neonGreen.withValues(alpha: 0.04 / i)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(center, 120.0 * i, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

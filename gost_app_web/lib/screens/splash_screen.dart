// ============================================================
// Plugbet – Splash Screen animé
// Logo + animation de chargement pendant l'init API
// ============================================================

import 'package:flutter/material.dart';
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
  late AnimationController _pulseController;
  late AnimationController _textController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _pulseScale;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  bool _initDone = false;
  bool _animDone = false;

  @override
  void initState() {
    super.initState();

    // Animation du logo (scale + fade in)
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // Pulse autour du logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Texte (fade in + slide up)
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    // 1. Lancer logo
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 400));

    // 2. Lancer pulse
    _pulseController.repeat(reverse: true);

    // 3. Lancer texte
    _textController.forward();

    // 4. Lancer l'init en parallèle
    widget.onInit().then((_) {
      _initDone = true;
      _tryNavigate();
    }).catchError((_) {
      _initDone = true;
      _tryNavigate();
    });

    // 5. Durée minimum du splash (réduite : les données chargent déjà depuis le provider)
    await Future.delayed(const Duration(milliseconds: 1400));
    _animDone = true;
    _tryNavigate();
  }

  void _tryNavigate() {
    if (_initDone && _animDone && mounted) {
      widget.onReady();
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo animé
              AnimatedBuilder(
                animation: Listenable.merge([_logoController, _pulseController]),
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulse ring
                      if (_pulseController.isAnimating)
                        Opacity(
                          opacity: 1.0 - _pulseController.value,
                          child: Transform.scale(
                            scale: _pulseScale.value,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.neonGreen.withValues(alpha: 0.4),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Logo principal
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.neonGreen.withValues(alpha: 0.2),
                                  AppColors.bgCard,
                                ],
                              ),
                              border: Border.all(
                                color: AppColors.neonGreen.withValues(alpha: 0.6),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.neonGreen.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.sports_soccer,
                              size: 48,
                              color: AppColors.neonGreen,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              SizedBox(height: 32),

              // Nom de l'app
              SlideTransition(
                position: _textSlide,
                child: FadeTransition(
                  opacity: _textOpacity,
                  child: Column(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [AppColors.textPrimary, AppColors.neonGreen],
                          stops: [0.5, 1.0],
                        ).createShader(bounds),
                        child: Text(
                          'Plugbet',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.neonGreen.withValues(alpha: 0.8),
                          letterSpacing: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 48),

              // Indicateur de chargement
              FadeTransition(
                opacity: _textOpacity,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.neonGreen.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),

              SizedBox(height: 16),

              FadeTransition(
                opacity: _textOpacity,
                child: Text(
                  'Chargement des matchs...',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

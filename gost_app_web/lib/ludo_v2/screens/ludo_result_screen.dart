// ============================================================
// LUDO V2 — Result Screen (premium redesign)
// ============================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../models/ludo_models.dart';

class LudoV2ResultScreen extends StatelessWidget {
  final LudoV2Game game;
  final String myId;

  const LudoV2ResultScreen({
    super.key,
    required this.game,
    required this.myId,
  });

  @override
  Widget build(BuildContext context) {
    final isWinner = game.winnerId == myId;
    final pot = game.betAmount * game.turnOrder.length;
    final accent = isWinner ? AppColors.neonGreen : AppColors.neonRed;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Stack(
          children: [
            // Halo de couleur en fond pour renforcer l'ambiance premium.
            Positioned(
              top: -80,
              left: -60,
              child: _GlowOrb(color: accent, size: 260, opacity: 0.22),
            ),
            Positioned(
              bottom: -100,
              right: -70,
              child: _GlowOrb(
                color: isWinner ? AppColors.neonYellow : AppColors.neonOrange,
                size: 240,
                opacity: 0.16,
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutBack,
                    builder: (context, t, child) {
                      return Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.scale(scale: 0.85 + (0.15 * t), child: child),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icône avec halo néon
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                accent.withValues(alpha: 0.28),
                                accent.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.cardGradient,
                                border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isWinner ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                                size: 64,
                                color: isWinner ? AppColors.neonYellow : AppColors.neonRed,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Titre
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: isWinner
                                ? [AppColors.neonGreen, AppColors.neonYellow]
                                : [AppColors.neonRed, const Color(0xFFFF7A7A)],
                          ).createShader(bounds),
                          child: Text(
                            isWinner ? 'VICTOIRE !' : 'DÉFAITE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Badge de gains
                        if (pot > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  accent.withValues(alpha: 0.22),
                                  accent.withValues(alpha: 0.08),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: accent.withValues(alpha: 0.5), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.25),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Text(
                              isWinner ? '+$pot FCFA' : '-${game.betAmount} FCFA',
                              style: TextStyle(
                                color: accent,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        const SizedBox(height: 32),

                        // Stats — carte glassmorphism
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                gradient: AppColors.cardGradient,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.divider),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  _statRow(Icons.casino_rounded, 'Tours joués', '${game.turnNumber}'),
                                  const SizedBox(height: 14),
                                  Divider(color: AppColors.divider, height: 1),
                                  const SizedBox(height: 14),
                                  _statRow(Icons.groups_rounded, 'Joueurs', '${game.turnOrder.length}'),
                                  if (pot > 0) ...[
                                    const SizedBox(height: 14),
                                    Divider(color: AppColors.divider, height: 1),
                                    const SizedBox(height: 14),
                                    _statRow(Icons.savings_rounded, 'Pot total', '$pot FCFA', highlight: true),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Bouton retour
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [AppColors.neonGreen, Color.lerp(AppColors.neonGreen, Colors.black, 0.15)!],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.neonGreen.withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                                child: const Center(
                                  child: Text(
                                    'RETOUR AU MENU',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
        Container(
          padding: highlight
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 3)
              : EdgeInsets.zero,
          decoration: highlight
              ? BoxDecoration(
                  color: AppColors.neonGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Text(
            value,
            style: TextStyle(
              color: highlight ? AppColors.neonGreen : AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

/// Petit halo décoratif flouté pour l'ambiance de fond.
class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _GlowOrb({required this.color, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CORA DICE - Composant animation des dés
// Animation de rotation + effets spéciaux (Cora/7)
// ============================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class DiceAnimationWidget extends StatelessWidget {
  final int dice1;
  final int dice2;
  final AnimationController controller;
  final bool isCora;
  final bool isSeven;
  final AnimationController? coraController;
  final AnimationController? sevenController;

  const DiceAnimationWidget({
    super.key,
    required this.dice1,
    required this.dice2,
    required this.controller,
    this.isCora = false,
    this.isSeven = false,
    this.coraController,
    this.sevenController,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Effet Cora (explosion verte)
        if (isCora && coraController != null)
          AnimatedBuilder(
            animation: coraController!,
            builder: (context, child) {
              return Transform.scale(
                scale: coraController!.value * 2,
                child: Opacity(
                  opacity: 1 - coraController!.value,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.neonGreen,
                        width: 4,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

        // Effet 7 (tremblement rouge)
        if (isSeven && sevenController != null)
          AnimatedBuilder(
            animation: sevenController!,
            builder: (context, child) {
              final shake = math.sin(sevenController!.value * math.pi * 10) * 10;
              return Transform.translate(
                offset: Offset(shake, 0),
                child: Opacity(
                  opacity: 1 - sevenController!.value,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: AppColors.neonRed.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              );
            },
          ),

        // Dés
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDice(dice1, -0.2),
            SizedBox(width: 24),
            _buildDice(dice2, 0.2),
          ],
        ),

        // Texte Cora
        if (isCora && coraController != null)
          AnimatedBuilder(
            animation: coraController!,
            builder: (context, child) {
              return Transform.scale(
                scale: 1 + coraController!.value * 0.5,
                child: Opacity(
                  opacity: 1 - coraController!.value * 0.5,
                  child: Text(
                    'CORA!',
                    style: TextStyle(
                      color: AppColors.neonGreen,
                      fontSize: 60,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: AppColors.neonGreen,
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDice(int value, double rotationOffset) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: controller.value * math.pi * 4 + rotationOffset,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Colors.grey.shade300,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCora
                    ? AppColors.neonGreen
                    : isSeven
                        ? AppColors.neonRed
                        : Colors.grey.shade400,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: isCora
                      ? AppColors.neonGreen.withValues(alpha: 0.5)
                      : isSeven
                          ? AppColors.neonRed.withValues(alpha: 0.5)
                          : Colors.black.withValues(alpha: 0.3),
                  blurRadius: isCora || isSeven ? 20 : 10,
                  spreadRadius: isCora || isSeven ? 5 : 2,
                ),
              ],
            ),
            child: _buildDots(value),
          ),
        );
      },
    );
  }

  Widget _buildDots(int value) {
    final dotColor = isCora
        ? AppColors.neonGreen
        : isSeven
            ? AppColors.neonRed
            : Colors.black87;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        final dotSize = size * 0.15;
        final padding = size * 0.2;

        Widget dot() => Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
            );

        switch (value) {
          case 1:
            return Center(child: dot());

          case 2:
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [dot()],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [dot()],
                  ),
                ],
              ),
            );

          case 3:
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [dot()],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [dot()],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [dot()],
                  ),
                ],
              ),
            );

          case 4:
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [dot(), dot()],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [dot(), dot()],
                  ),
                ],
              ),
            );

          case 5:
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [dot(), dot()],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [dot()],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [dot(), dot()],
                  ),
                ],
              ),
            );

          case 6:
            return Padding(
              padding: EdgeInsets.all(padding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [dot(), dot(), dot()],
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [dot(), dot(), dot()],
                  ),
                ],
              ),
            );

          default:
            return SizedBox();
        }
      },
    );
  }
}

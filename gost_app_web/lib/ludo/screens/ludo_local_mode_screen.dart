// ============================================================
// LUDO MODULE - Local Mode Selection
// Choix: 2 joueurs (2 couleurs chacun) ou 4 joueurs
// ============================================================

import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../game/ludo_board_colors.dart';
import 'ludo_local_game_screen.dart';

class LudoLocalModeScreen extends StatelessWidget {
  const LudoLocalModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Jeu Local',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 40),

                // Description
                Text(
                  'Choisissez le mode de jeu',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 32),

                // Option 1: 2 Joueurs
                Expanded(
                  child: _ModeCard(
                    title: '2 Joueurs',
                    subtitle: 'Chaque joueur contrôle 2 couleurs',
                    colors: [
                      LudoBoardColors.red,
                      LudoBoardColors.yellow,
                    ],
                    colors2: [
                      LudoBoardColors.green,
                      LudoBoardColors.blue,
                    ],
                    playerCount: 2,
                    icon: Icons.people,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LudoLocalGameScreen(playerCount: 2),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 20),

                // Option 2: 4 Joueurs
                Expanded(
                  child: _ModeCard(
                    title: '4 Joueurs',
                    subtitle: 'Chaque joueur contrôle 1 couleur',
                    colors: [
                      LudoBoardColors.red,
                      LudoBoardColors.green,
                      LudoBoardColors.blue,
                      LudoBoardColors.yellow,
                    ],
                    playerCount: 4,
                    icon: Icons.groups,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LudoLocalGameScreen(playerCount: 4),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Color> colors;
  final List<Color>? colors2;
  final int playerCount;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.colors,
    this.colors2,
    required this.playerCount,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.divider.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icône
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGreen.withValues(alpha: 0.15),
              ),
              child: Icon(icon, size: 36, color: AppColors.neonGreen),
            ),
            SizedBox(height: 20),

            // Titre
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8),

            // Sous-titre
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 20),

            // Couleurs
            if (playerCount == 2) ...[
              // 2 joueurs: 2 groupes de couleurs
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _colorGroup(colors, 'Joueur 1'),
                  SizedBox(width: 24),
                  Text('VS', style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold)),
                  SizedBox(width: 24),
                  _colorGroup(colors2!, 'Joueur 2'),
                ],
              ),
            ] else ...[
              // 4 joueurs: 4 couleurs individuelles
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: colors.map((color) => _colorCircle(color)).toList(),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _colorGroup(List<Color> groupColors, String label) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: groupColors.map((c) => Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _colorCircle(c),
          )).toList(),
        ),
        SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _colorCircle(Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

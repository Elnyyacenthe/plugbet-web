// ============================================================
// AVIATOR – Écran d'accueil (règles + stats + lancer)
// ============================================================

import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'aviator_game_screen.dart';

class AviatorScreen extends StatelessWidget {
  const AviatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text('✈', style: TextStyle(fontSize: 18)),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Aviator',
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero banner ──────────────────────────────
              _heroBanner(context),
              SizedBox(height: 24),

              // ── Règles ───────────────────────────────────
              _sectionTitle('Comment jouer'),
              SizedBox(height: 12),
              _ruleCard(
                '1',
                'Misez vos coins',
                'Choisissez une mise (minimum 90 coins, pas de limite) avant le décollage.',
                Icons.monetization_on,
                AppColors.neonYellow,
              ),
              SizedBox(height: 8),
              _ruleCard(
                '2',
                'L\'avion décolle',
                'Le multiplicateur grimpe depuis ×1.00. Plus vous attendez, plus le gain potentiel est élevé.',
                Icons.flight_takeoff,
                const Color(0xFFF97316),
              ),
              SizedBox(height: 8),
              _ruleCard(
                '3',
                'Cash Out avant le crash',
                'Appuyez sur CASHOUT pour encaisser votre mise × multiplicateur actuel.',
                Icons.attach_money,
                AppColors.neonGreen,
              ),
              SizedBox(height: 8),
              _ruleCard(
                '4',
                'Crash = perte totale',
                'Si l\'avion s\'écrase avant votre cash out, vous perdez votre mise.',
                Icons.local_fire_department,
                AppColors.neonRed,
              ),

              SizedBox(height: 24),

              // ── Features ─────────────────────────────────
              _sectionTitle('Fonctionnalités'),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _featureChip('2 paris simultanés', Icons.add_card),
                  _featureChip('Auto Cash Out', Icons.timer),
                  _featureChip('Provably Fair', Icons.verified_user),
                  _featureChip('Mode Démo', Icons.play_circle),
                  _featureChip('Historique', Icons.history),
                ],
              ),

              SizedBox(height: 32),

              // ── Boutons action ────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const AviatorGameScreen(demoMode: true),
                        ),
                      ),
                      icon: Icon(Icons.play_circle_outline,
                          color: AppColors.textSecondary),
                      label: Text(AppLocalizations.of(context)!.gameDemoMode,
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AviatorGameScreen(),
                        ),
                      ),
                      icon: Text('✈', style: TextStyle(fontSize: 18)),
                      label: Text(AppLocalizations.of(context)!.gamePlayAction,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFF97316),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 4,
                        shadowColor:
                            const Color(0xFFF97316).withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A0A00),
            const Color(0xFF2D0F00),
            const Color(0xFFF97316).withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFFF97316).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('✈', style: TextStyle(fontSize: 42)),
              SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AVIATOR',
                    style: TextStyle(
                        color: Color(0xFFF97316),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3),
                  ),
                  Text(
                    'Crash multiplier game',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Misez, regardez voler l\'avion et encaissez avant le crash !',
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 14, height: 1.5),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _statBadge('Min: 90 coins', AppColors.neonGreen),
              _statBadge('Max: ∞', AppColors.neonOrange),
              _statBadge('2 paris/round', AppColors.neonBlue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBadge(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5),
    );
  }

  Widget _ruleCard(
      String num, String title, String desc, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(num,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                SizedBox(height: 3),
                Text(desc,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureChip(String label, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFFF97316)),
          SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ============================================================
// Solitaire – Écran principal (hub) — Multijoueur uniquement
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/wallet_provider.dart';
import 'game_screen.dart';
import 'solitaire_join_screen.dart';

class SolitaireScreen extends StatefulWidget {
  const SolitaireScreen({super.key});
  @override
  State<SolitaireScreen> createState() => _SolitaireScreenState();
}

class _SolitaireScreenState extends State<SolitaireScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refresh();
    });
  }

  void _startPractice() {
    Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SolitaireGameScreen(isPractice: true)))
        .then((_) { if (mounted) context.read<WalletProvider>().refresh(); });
  }

  void _startMultiplayer() {
    Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SolitaireJoinScreen()))
        .then((_) { if (mounted) context.read<WalletProvider>().refresh(); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        // Bouton retour
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
        SizedBox(height: 4),
        // Header
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.neonGreen.withValues(alpha: 0.15),
                AppColors.bgCard,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.neonGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.neonGreen.withValues(alpha: 0.4)),
                ),
                child: Center(
                    child: Text('🂡', style: TextStyle(fontSize: 32))),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Solitaire',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text('Multijoueur – Joueurs vs Joueurs',
                        style: TextStyle(
                            color: AppColors.neonGreen, fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 6),
                    Consumer<WalletProvider>(
                      builder: (_, wallet, __) => Row(children: [
                        Icon(Icons.monetization_on,
                            color: AppColors.neonYellow, size: 16),
                        SizedBox(width: 4),
                        Text('${wallet.coins} coins',
                            style: TextStyle(
                                color: AppColors.neonYellow,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20),

        // Règles Multijoueur
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.people_alt_rounded,
                    color: AppColors.neonGreen, size: 18),
                SizedBox(width: 8),
                Text('Règles du jeu',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.neonGreen)),
              ]),
              SizedBox(height: 14),
              _RuleRow(icon: '👥', text: '2 à 4 joueurs sur un plateau partagé'),
              _RuleRow(icon: '🔄', text: 'Chaque joueur joue 1 action à son tour'),
              _RuleRow(icon: '🎯', text: 'Score = cartes envoyées en fondation'),
              _RuleRow(icon: '💎', text: 'Mise configurable : 50 / 100 / 200 / 500 coins'),
              _RuleRow(icon: '🏆', text: 'Le meilleur score remporte le pot'),
              _RuleRow(icon: '⏱️', text: 'Partie limitée à 10 minutes'),
              _RuleRow(icon: '🤝', text: 'En cas d\'égalité, le pot est partagé'),
            ],
          ),
        ),
        SizedBox(height: 20),

        // Comment jouer
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCardLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.neonBlue, size: 16),
                SizedBox(width: 8),
                Text('Comment jouer',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ]),
              SizedBox(height: 12),
              _RuleRow(icon: '1️⃣', text: 'Crée une salle ou rejoins une salle publique'),
              _RuleRow(icon: '2️⃣', text: 'Attends que tous les joueurs soient prêts'),
              _RuleRow(icon: '3️⃣', text: 'Joue une carte quand c\'est ton tour'),
              _RuleRow(icon: '4️⃣', text: 'Envoie le maximum de cartes en fondation'),
            ],
          ),
        ),
        SizedBox(height: 24),

        // Boutons
        Row(
          children: [
            // Entraînement (gratuit, sans mise)
            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _startPractice,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bgCardLight,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                    side: BorderSide(
                        color: AppColors.neonBlue.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🎓', style: TextStyle(fontSize: 18)),
                      Text('S\'ENTRAÎNER',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            // Multijoueur
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _startMultiplayer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonGreen,
                    foregroundColor: AppColors.bgDark,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('👥', style: TextStyle(fontSize: 20)),
                      SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MULTIJOUEUR',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5)),
                          Text('Créer ou rejoindre',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 80),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  final String icon, text;
  const _RuleRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text(icon, style: TextStyle(fontSize: 16)),
        SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13))),
      ]),
    );
  }
}

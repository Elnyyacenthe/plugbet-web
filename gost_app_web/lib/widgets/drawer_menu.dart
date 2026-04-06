// ============================================================
// Plugbet – Drawer latéral
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../providers/wallet_provider.dart';
import '../providers/player_provider.dart';
import '../models/player_models.dart';
import '../screens/profile_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/support_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/favorites_screen.dart';

class AppDrawer extends StatelessWidget {
  final void Function(int index)? onTabChange;

  const AppDrawer({super.key, this.onTabChange});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final wallet = context.watch<WalletProvider>();
    final username = wallet.username.isNotEmpty
        ? wallet.username
        : (user?.email ?? '');

    return Drawer(
      backgroundColor: AppColors.bgDark,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                gradient: AppColors.headerGradient,
                border: Border(
                  bottom: BorderSide(color: AppColors.divider, width: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [
                        AppColors.neonGreen.withValues(alpha: 0.2),
                        AppColors.bgCard,
                      ]),
                      border: Border.all(
                        color: AppColors.neonGreen.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(Icons.sports_soccer,
                        color: AppColors.neonGreen, size: 24),
                  ),
                  SizedBox(height: 10),
                  // Nom app
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [AppColors.textPrimary, AppColors.neonGreen],
                      stops: [0.6, 1.0],
                    ).createShader(bounds),
                    child: Text('Plugbet',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                  // Username (entre logo et coins)
                  if (username.isNotEmpty) ...[
                    SizedBox(height: 3),
                    Text(username,
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                  SizedBox(height: 10),
                  // Solde coins
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.neonYellow.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.neonYellow.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.monetization_on,
                            color: AppColors.neonYellow, size: 14),
                        SizedBox(width: 5),
                        Text('${wallet.coins} coins',
                            style: TextStyle(
                                color: AppColors.neonYellow,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Contenu ──
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(vertical: 8),
                children: [
                  // --- Profil & Social ---
                  _sectionHeader('PROFIL & SOCIAL'),
                  Consumer<PlayerProvider>(
                    builder: (_, player, __) {
                      final rank = player.rank;
                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: rank.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(rank.icon, size: 14, color: rank.color),
                        ),
                        title: Text('Mon Profil',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        subtitle: Text('${rank.label} • ${player.xp} XP',
                            style: TextStyle(fontSize: 11, color: rank.color)),
                        trailing: Icon(Icons.chevron_right,
                            size: 18, color: AppColors.textMuted),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const ProfileScreen()));
                        },
                      );
                    },
                  ),
                  _menuItem(Icons.leaderboard_rounded, 'Classement', () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
                  }),
                  _menuItem(Icons.people_alt_rounded, 'Amis', () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const FriendsScreen()));
                  }),
                  _menuItem(Icons.star_rounded, 'Favoris', () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const FavoritesScreen()));
                  }),

                  Divider(color: AppColors.divider, height: 24, indent: 16, endIndent: 16),

                  // --- Info ---
                  _sectionHeader('INFO'),
                  _menuItem(Icons.help_outline, 'Aide', () {
                    Navigator.pop(context);
                    _showAideDialog(context);
                  }),
                  _menuItem(Icons.privacy_tip_outlined, 'Confidentialité', () {
                    Navigator.pop(context);
                    launchUrl(Uri.parse('https://plugbet.com/privacy'),
                        mode: LaunchMode.externalApplication);
                  }),
                  _menuItem(Icons.support_agent, 'Nous contacter', () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SupportScreen()));
                  }),
                ],
              ),
            ),

            // ── Footer ──
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.divider, width: 0.5),
                ),
              ),
              child: Text('v1.0.0',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAideDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Aide', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Plugbet – Chat & Bet\n\n'
          '• Matchs : scores en direct\n'
          '• Fantasy : créez votre équipe FPL\n'
          '• Jeux : Ludo, Cora Dice, Dames, Solitaire, Aviator\n'
          '• Chat : messagerie privée\n\n'
          'Pour toute question, utilisez le Support dans Réglages.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('OK', style: TextStyle(color: AppColors.neonGreen)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 1.5)),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: AppColors.textSecondary),
      title: Text(label,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary)),
      trailing: Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}

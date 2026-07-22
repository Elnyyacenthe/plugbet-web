// ============================================================
// Plugbet – Écran Menu (onglet grille de la barre principale)
// ============================================================
// Menu façon 1xbet : en-tête compte (avatar + solde), puis des groupes
// de lignes (icône + libellé + chevron) dans des cartes arrondies, et
// un bouton de déconnexion. Chrome sombre (#0B1120), accents verts.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../utils/currency.dart';
import '../providers/wallet_provider.dart';
import '../widgets/plugbet_wordmark.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'leaderboard_screen.dart';
import 'friends_screen.dart';
import 'favorites_screen.dart';
import 'games_screen.dart';
import 'support_screen.dart';
import 'faq_screen.dart';
import 'responsible_gaming_screen.dart';
import 'promotions/promotions_screen.dart';
import 'bonus_codes_screen.dart';

class MenuScreen extends StatelessWidget {
  final HiveService hiveService;
  final SupabaseService supabaseService;

  /// Appelé après déconnexion pour revenir à l'onglet Populaire.
  final VoidCallback? onLoggedOut;

  const MenuScreen({
    super.key,
    required this.hiveService,
    required this.supabaseService,
    this.onLoggedOut,
  });

  void _go(BuildContext context, WidgetBuilder builder) {
    Navigator.push(context, MaterialPageRoute(builder: builder));
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Déconnexion',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w900)),
        content: Text('Veux-tu vraiment te déconnecter ?',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Se déconnecter',
                style: TextStyle(
                    color: Color(0xFFFF6B6B), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await supabaseService.signOut();
    // Restaure une session invité pour que l'app reste fonctionnelle.
    await supabaseService.signInAnonymously();
    onLoggedOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final coins = context.watch<WalletProvider>().coins;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            // En-tête : logo + réglages.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const PlugbetLogoImage(height: 20),
                ),
                const Spacer(),
                _IconButtonSquare(
                  icon: AppIcons.settings,
                  onTap: () => _go(
                    context,
                    (_) => SettingsScreen(
                      hiveService: hiveService,
                      supabaseService: supabaseService,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Carte compte.
            _accountCard(context, coins),

            _group('Mon compte', [
              _MenuRow(
                icon: AppIcons.profile,
                label: 'Mon profil',
                onTap: () => _go(
                  context,
                  (_) => ProfileScreen(
                    hiveService: hiveService,
                    supabaseService: supabaseService,
                  ),
                ),
              ),
              _MenuRow(
                icon: AppIcons.settings,
                label: 'Réglages',
                onTap: () => _go(
                  context,
                  (_) => SettingsScreen(
                    hiveService: hiveService,
                    supabaseService: supabaseService,
                  ),
                ),
              ),
              _MenuRow(
                icon: AppIcons.star,
                label: 'Favoris',
                onTap: () => _go(context, (_) => const FavoritesScreen()),
              ),
            ]),

            _group('Social', [
              _MenuRow(
                icon: AppIcons.chat,
                label: 'Messagerie',
                onTap: () => _go(context, (_) => const ChatScreen()),
              ),
              _MenuRow(
                icon: AppIcons.friends,
                label: 'Amis',
                onTap: () => _go(context, (_) => const FriendsScreen()),
              ),
              _MenuRow(
                icon: AppIcons.leaderboard,
                label: 'Classement',
                onTap: () => _go(context, (_) => const LeaderboardScreen()),
              ),
            ]),

            _group('Jouer', [
              _MenuRow(
                icon: AppIcons.games,
                label: 'Jeux',
                onTap: () => _go(context, (_) => const GamesScreen()),
              ),
              _MenuRow(
                icon: AppIcons.gift,
                label: 'Promotions',
                trailing: 'HOT',
                onTap: () => _go(context, (_) => const PromotionsScreen()),
              ),
              _MenuRow(
                icon: Icons.card_giftcard_rounded,
                label: 'Mes bonus',
                onTap: () => _go(context, (_) => const BonusCodesScreen()),
              ),
            ]),

            _group('Aide & infos', [
              _MenuRow(
                icon: AppIcons.support,
                label: 'Assistance',
                onTap: () => _go(context, (_) => const SupportScreen()),
              ),
              _MenuRow(
                icon: AppIcons.help,
                label: 'FAQ & Règlement (2Up)',
                onTap: () => _go(context, (_) => const FaqScreen()),
              ),
              _MenuRow(
                icon: AppIcons.verified,
                label: 'Jeu responsable',
                onTap: () =>
                    _go(context, (_) => const ResponsibleGamingScreen()),
              ),
            ]),

            const SizedBox(height: 22),
            _logoutButton(context),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(BuildContext context, int coins) {
    return GestureDetector(
      onTap: () => _go(
        context,
        (_) => ProfileScreen(
          hiveService: hiveService,
          supabaseService: supabaseService,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPlugbetGreen.withValues(alpha: 0.16),
                border:
                    Border.all(color: kPlugbetGreen.withValues(alpha: 0.4)),
              ),
              child: const Icon(AppIcons.profile,
                  color: kPlugbetGreen, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mon compte',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text('Voir et modifier le profil',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Solde',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                const SizedBox(height: 2),
                Text(
                  Currency.format(coins, context),
                  style: const TextStyle(
                    color: kPlugbetGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(String title, List<_MenuRow> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(Divider(
          height: 1,
          thickness: 1,
          color: AppColors.divider,
          indent: 62,
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 0, 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _logoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () => _logout(context),
        icon: const Icon(AppIcons.logout,
            size: 20, color: Color(0xFFFF6B6B)),
        label: const Text(
          'Déconnexion',
          style: TextStyle(
            color: Color(0xFFFF6B6B),
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0x33FF6B6B)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: kPlugbetGreen.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: kPlugbetGreen, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kPlugbetGreen.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  trailing!,
                  style: const TextStyle(
                    color: kPlugbetGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _IconButtonSquare extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconButtonSquare({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 20),
      ),
    );
  }
}

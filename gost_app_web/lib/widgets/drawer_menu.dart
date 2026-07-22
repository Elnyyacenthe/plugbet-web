// ============================================================
// Plugbet – Drawer latéral
// ============================================================
// Panneau de métal brossé qui glisse par-dessus l'écran : arête claire
// sur son bord droit, ombre portée sur le contenu. Chaque entrée porte
// un médaillon d'icône bombé plutôt qu'une icône posée à plat.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_icons.dart';
import '../theme/app_reliefs.dart';
import '../theme/app_surfaces.dart';
import '../theme/app_theme.dart';
import '../app_version.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/wallet_provider.dart';
import '../providers/player_provider.dart';
import '../models/player_models.dart';
import '../services/hive_service.dart';
import '../services/supabase_service.dart';
import '../screens/profile_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/support_screen.dart';
import '../screens/friends_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/promotions/promotions_screen.dart';
import '../games/_hub/screens/games_home_page.dart';

class AppDrawer extends StatelessWidget {
  final HiveService hiveService;
  final SupabaseService supabaseService;
  final void Function(int index)? onTabChange;

  const AppDrawer({
    super.key,
    required this.hiveService,
    required this.supabaseService,
    this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final wallet = context.watch<WalletProvider>();
    final t = AppLocalizations.of(context)!;
    final username =
        wallet.username.isNotEmpty ? wallet.username : (user?.email ?? '');

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppSurfaces.metal,
          border: Border(
            right: BorderSide(color: AppSurfaces.edgeLight, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: AppColors.isDark ? 0.6 : 0.18),
              blurRadius: 24,
              offset: const Offset(6, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, username, wallet),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  children: [
                    _sectionHeader('PROFIL & SOCIAL'),
                    _buildRankTile(context, t),
                    _MenuItem(
                      icon: AppIcons.leaderboard,
                      color: AppColors.neonYellow,
                      label: t.drawerLeaderboard,
                      onTap: () => _go(context, const LeaderboardScreen()),
                    ),
                    _MenuItem(
                      icon: AppIcons.friends,
                      color: AppColors.neonBlue,
                      label: t.profileTabFriends,
                      onTap: () => _go(context, const FriendsScreen()),
                    ),
                    _MenuItem(
                      icon: AppIcons.starFilled,
                      color: AppColors.neonOrange,
                      label: t.drawerFavorites,
                      onTap: () => _go(context, const FavoritesScreen()),
                    ),
                    _MenuItem(
                      icon: AppIcons.gift,
                      color: AppColors.neonPurple,
                      label: 'Promotions',
                      onTap: () => _go(context, const PromotionsScreen()),
                    ),
                    const ReliefDivider(indent: 16, height: 26),
                    _sectionHeader('JEUX'),
                    _MenuItem(
                      icon: AppIcons.games,
                      color: AppColors.neonPurple,
                      label: t.tabGames,
                      onTap: () => _go(context, const GamesHomePage()),
                    ),
                    const ReliefDivider(indent: 16, height: 26),
                    _sectionHeader('INFO'),
                    _MenuItem(
                      icon: AppIcons.help,
                      color: AppColors.textSecondary,
                      label: t.drawerHelp,
                      onTap: () {
                        Navigator.pop(context);
                        _showAideDialog(context);
                      },
                    ),
                    _MenuItem(
                      icon: AppIcons.privacy,
                      color: AppColors.textSecondary,
                      label: t.drawerPrivacy,
                      onTap: () {
                        Navigator.pop(context);
                        launchUrl(Uri.parse('https://plugbet.com/privacy'),
                            mode: LaunchMode.externalApplication);
                      },
                    ),
                    _MenuItem(
                      icon: AppIcons.support,
                      color: AppColors.textSecondary,
                      label: t.drawerContact,
                      onTap: () => _go(context, const SupportScreen()),
                    ),
                  ],
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader(
      BuildContext context, String username, WalletProvider wallet) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        border: Border(
          bottom: BorderSide(color: AppSurfaces.edgeDark, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DomeIcon(
            icon: AppIcons.football,
            color: AppColors.primary,
            size: 52,
          ),
          const SizedBox(height: 12),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [AppColors.textPrimary, AppColors.primaryInk],
              stops: const [0.55, 1.0],
            ).createShader(bounds),
            child: const Text(
              'Plugbet',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                color: Colors.white,
              ),
            ),
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              username,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ReliefPill(
            label: '${wallet.coins} FCFA',
            icon: AppIcons.coinsFilled,
            color: AppColors.neonYellow,
            fontSize: 13,
          ),
        ],
      ),
    );
  }

  // ── Entrée « Mon profil », qui affiche le rang ──────────────
  Widget _buildRankTile(BuildContext context, AppLocalizations t) {
    return Consumer<PlayerProvider>(
      builder: (_, player, __) {
        final rank = player.rank;
        return _MenuItem(
          icon: rank.icon,
          color: rank.color,
          label: t.drawerMyProfile,
          subtitle: '${rank.label} • ${player.xp} XP',
          subtitleColor: rank.color,
          onTap: () => _go(
            context,
            ProfileScreen(
              hiveService: hiveService,
              supabaseService: supabaseService,
            ),
          ),
        );
      },
    );
  }

  // ── Footer ──────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppSurfaces.edgeDark, width: 1)),
      ),
      child: Text(
        'v$kAppVersion',
        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
    );
  }

  void _showAideDialog(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(color: AppColors.primaryInk.withValues(alpha: 0.4)),
        ),
        title:
            Text(t.drawerHelp, style: TextStyle(color: AppColors.textPrimary)),
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
            child:
                Text(t.commonOk, style: TextStyle(color: AppColors.primaryInk)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textMuted,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

// ── Entrée de menu ────────────────────────────────────────────

class _MenuItem extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.subtitleColor,
  });

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hover = true),
      onTapUp: (_) => setState(() => _hover = false),
      onTapCancel: () => setState(() => _hover = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: AppRadius.brSm,
          color: _hover
              ? widget.color.withValues(alpha: 0.10)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            DomeIcon(icon: widget.icon, color: widget.color, size: 34),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.subtitleColor ?? AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

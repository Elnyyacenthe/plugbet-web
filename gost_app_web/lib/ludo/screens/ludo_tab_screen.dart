// ============================================================
// LUDO MODULE - Écran principal (onglet Jeux)
// Affiche le wallet, accès au lobby, stats
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/wallet_provider.dart';
import '../../screens/auth_screen.dart';
import '../providers/ludo_provider.dart';
import '../services/audio_service.dart';
import 'ludo_lobby_screen.dart';
import 'ludo_room_screen.dart';
import 'ludo_local_mode_screen.dart';

class LudoTabScreen extends StatefulWidget {
  const LudoTabScreen({super.key});

  @override
  State<LudoTabScreen> createState() => _LudoTabScreenState();
}

class _LudoTabScreenState extends State<LudoTabScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LudoProvider>().loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Consumer<LudoProvider>(
            builder: (context, ludo, _) {
              if (!ludo.isLoggedIn) {
                return _buildLoginRequired(context);
              }

              if (ludo.isLoading && ludo.profile == null) {
                return Center(
                  child: CircularProgressIndicator(color: AppColors.neonGreen),
                );
              }

              return RefreshIndicator(
                onRefresh: () => ludo.refreshProfile(),
                color: AppColors.neonGreen,
                child: ListView(
                  padding: EdgeInsets.all(20),
                  children: [
                    _buildHeader(),
                    SizedBox(height: 24),
                    _buildWalletCard(ludo),
                    SizedBox(height: 20),
                    _buildPlayButton(context, ludo),
                    SizedBox(height: 16),
                    _buildLocalModeButton(context),
                    SizedBox(height: 16),
                    _buildRoomQuickActions(context),
                    SizedBox(height: 16),
                    _buildSoundToggle(),
                    SizedBox(height: 20),
                    _buildStatsCard(ludo),
                    SizedBox(height: 20),
                    _buildRulesCard(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoginRequired(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icone animee
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neonGreen.withValues(alpha: 0.1),
                border: Border.all(
                  color: AppColors.neonGreen.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(Icons.sports_esports,
                  size: 44, color: AppColors.neonGreen),
            ),
            SizedBox(height: 24),
            Text(
              'Connexion requise',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Creez un compte ou connectez-vous\npour acceder au Ludo multijoueur',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            SizedBox(height: 32),

            // Bouton S'inscrire (principal)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final ludoProvider = context.read<LudoProvider>();
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AuthScreen(startWithSignUp: true),
                    ),
                  );
                  if (result == true && mounted) {
                    ludoProvider.loadProfile();
                    setState(() {});
                  }
                },
                icon: Icon(Icons.person_add, size: 20),
                label: Text(
                  'Creer un compte',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neonGreen,
                  foregroundColor: AppColors.bgDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            SizedBox(height: 12),

            // Bouton Se connecter (secondaire)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ludoProvider = context.read<LudoProvider>();
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AuthScreen(startWithSignUp: false),
                    ),
                  );
                  if (result == true && mounted) {
                    ludoProvider.loadProfile();
                    setState(() {});
                  }
                },
                icon: Icon(Icons.login, size: 20),
                label: Text(
                  'Se connecter',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.neonGreen,
                  side: BorderSide(color: AppColors.neonGreen, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

            SizedBox(height: 20),
            // Info bonus
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.neonYellow.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.monetization_on,
                      color: AppColors.neonYellow, size: 18),
                  SizedBox(width: 8),
                  Text(
                    '500 FCFA offerts a l\'inscription !',
                    style: TextStyle(
                      color: AppColors.neonYellow,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bouton retour
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Retour',
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.sports_esports, color: AppColors.neonGreen, size: 28),
            SizedBox(width: 10),
            Text(
              'Ludo Arena',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        SizedBox(height: 4),
        Text(
          'Defiez vos amis et gagnez des coins !',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildWalletCard(LudoProvider ludo) {
    final profile = ludo.profile;
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonBlue.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                profile?.username ?? 'Joueur',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.white70, size: 14),
                    SizedBox(width: 4),
                    Text('Wallet', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.monetization_on, color: AppColors.neonYellow, size: 36),
              SizedBox(width: 10),
              Text(
                '${context.watch<WalletProvider>().coins}',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              SizedBox(width: 6),
              Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'COINS',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton(BuildContext context, LudoProvider ludo) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LudoLobbyScreen()),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00C853), Color(0xFF00E676)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonGreen.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
            SizedBox(width: 8),
            Text(
              'JOUER MAINTENANT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalModeButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LudoLocalModeScreen()),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7B1FA2), Color(0xFF9C27B0)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonPurple.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group, color: Colors.white, size: 26),
            SizedBox(width: 12),
            Text(
              'JEU LOCAL (2-4 JOUEURS)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LudoRoomScreen(isCreating: true),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.neonGreen.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline,
                      color: AppColors.neonGreen, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Creer salle',
                    style: TextStyle(
                      color: AppColors.neonGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LudoRoomScreen(isCreating: false),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.neonBlue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login_rounded,
                      color: AppColors.neonBlue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Rejoindre',
                    style: TextStyle(
                      color: AppColors.neonBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSoundToggle() {
    final audio = AudioService.instance;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.volume_up, color: AppColors.textSecondary, size: 20),
          SizedBox(width: 10),
          Text(
            'Sons',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          StatefulBuilder(
            builder: (context, setLocal) => Switch(
              value: audio.soundEnabled,
              onChanged: (v) {
                setLocal(() => audio.toggleSound(v));
              },
              activeColor: AppColors.neonGreen,
            ),
          ),
          SizedBox(width: 8),
          Icon(Icons.music_note, color: AppColors.textSecondary, size: 20),
          SizedBox(width: 4),
          Text(
            'Musique',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          SizedBox(width: 4),
          StatefulBuilder(
            builder: (context, setLocal) => Switch(
              value: audio.musicEnabled,
              onChanged: (v) {
                setLocal(() => audio.toggleMusic(v));
              },
              activeColor: AppColors.neonGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(LudoProvider ludo) {
    final profile = ludo.profile;
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, color: AppColors.neonBlue, size: 20),
              SizedBox(width: 8),
              Text(
                'Statistiques',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              _statItem('Parties', '${profile?.gamesPlayed ?? 0}', Icons.gamepad),
              SizedBox(width: 16),
              _statItem('Victoires', '${profile?.gamesWon ?? 0}', Icons.emoji_events),
              SizedBox(width: 16),
              _statItem(
                'Win Rate',
                '${profile?.winRate.toStringAsFixed(0) ?? 0}%',
                Icons.trending_up,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.neonGreen, size: 20),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesCard() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.neonOrange, size: 20),
              SizedBox(width: 8),
              Text(
                'Comment jouer',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _RuleItem(icon: '1', text: 'Entrez dans le Lobby et defiez un joueur en ligne'),
          _RuleItem(icon: '2', text: 'Choisissez votre mise en FCFA'),
          _RuleItem(icon: '3', text: 'Lancez le de et deplacez vos pions'),
          _RuleItem(icon: '4', text: 'Un 6 fait sortir un pion ou donne un tour bonus'),
          _RuleItem(icon: '5', text: 'Le premier a amener ses 4 pions au centre gagne le pot !'),
        ],
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  final String icon;
  final String text;

  const _RuleItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                icon,
                style: TextStyle(
                  color: AppColors.neonGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// UserProfileScreen – Profil d'un utilisateur + demande d'ami
// ============================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../models/player_models.dart';
import '../providers/player_provider.dart';
import '../providers/messaging_provider.dart';
import 'chat_detail_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String username;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _client = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _requestSent = false;
  bool _alreadyFriend = false;
  bool _sendingRequest = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final myId = _client.auth.currentUser?.id;

      // Charger profil
      final profile = await _client
          .from('user_profiles')
          .select('id, username, xp, coins, total_wins')
          .eq('id', widget.userId)
          .maybeSingle();

      // Vérifier si déjà ami ou demande existante
      bool alreadyFriend = false;
      bool requestSent = false;

      if (myId != null) {
        final friendship = await _client
            .from('friendships')
            .select('id')
            .eq('user_id', myId)
            .eq('friend_id', widget.userId)
            .maybeSingle();
        alreadyFriend = friendship != null;

        if (!alreadyFriend) {
          final pending = await _client
              .from('friend_requests')
              .select('id')
              .eq('from_id', myId)
              .eq('to_id', widget.userId)
              .eq('status', 'pending')
              .maybeSingle();
          requestSent = pending != null;
        }
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _alreadyFriend = alreadyFriend;
          _requestSent = requestSent;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendFriendRequest() async {
    setState(() => _sendingRequest = true);
    final ok =
        await context.read<PlayerProvider>().sendFriendRequest(widget.userId);
    if (mounted) {
      setState(() {
        _sendingRequest = false;
        if (ok) _requestSent = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Demande envoyée à ${widget.username} !'
              : 'Erreur lors de l\'envoi'),
          backgroundColor: ok ? AppColors.neonGreen : AppColors.neonRed,
        ),
      );
    }
  }

  Future<void> _sendMessage() async {
    final provider = context.read<MessagingProvider>();
    final conversationId = await provider.startConversation(widget.userId);
    if (conversationId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            conversationId: conversationId,
            otherUsername: widget.username,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'Profil du joueur',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AppColors.neonGreen))
                    : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_profile == null) {
      return Center(
        child: Text('Profil introuvable',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }

    final username = _profile!['username'] as String? ?? widget.username;
    final xp = (_profile!['xp'] as int?) ?? 0;
    final coins = (_profile!['coins'] as int?) ?? 0;
    final totalWins = (_profile!['total_wins'] as int?) ?? 0;
    final rank = rankFromXp(xp);
    final initials = username.isNotEmpty ? username[0].toUpperCase() : '?';

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 80),
      children: [
        // Avatar + nom
        Center(
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: rank.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: rank.color.withValues(alpha: 0.5), width: 2),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: rank.color,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 14),
              Text(
                username,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 6),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: rank.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: rank.color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(rank.icon, size: 14, color: rank.color),
                    SizedBox(width: 5),
                    Text(
                      rank.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: rank.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 28),

        // Stats
        Row(
          children: [
            _StatCard(label: 'XP', value: '$xp', icon: Icons.bolt_rounded,
                color: AppColors.neonYellow),
            SizedBox(width: 12),
            _StatCard(label: 'Victoires', value: '$totalWins',
                icon: Icons.emoji_events_rounded, color: AppColors.neonGreen),
            SizedBox(width: 12),
            _StatCard(label: 'Coins', value: '$coins',
                icon: Icons.monetization_on_rounded,
                color: AppColors.neonOrange),
          ],
        ),
        SizedBox(height: 28),

        // Bouton Ajouter en ami
        if (!_alreadyFriend)
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed:
                  (_requestSent || _sendingRequest) ? null : _sendFriendRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: _requestSent
                    ? AppColors.bgCardLight
                    : AppColors.neonGreen,
                foregroundColor: _requestSent
                    ? AppColors.textMuted
                    : AppColors.bgDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: _requestSent ? 0 : 4,
                side: _requestSent
                    ? BorderSide(
                        color: AppColors.textMuted.withValues(alpha: 0.3))
                    : null,
              ),
              icon: _sendingRequest
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.bgDark))
                  : Icon(_requestSent
                      ? Icons.hourglass_top_rounded
                      : Icons.person_add_rounded),
              label: Text(
                _requestSent ? 'Demande envoyée' : 'Ajouter en ami',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),

        if (_alreadyFriend)
          Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.neonGreen.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded,
                    color: AppColors.neonGreen, size: 18),
                SizedBox(width: 8),
                Text('Déjà ami',
                    style: TextStyle(
                        color: AppColors.neonGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ],
            ),
          ),

        SizedBox(height: 12),

        // Bouton Envoyer un message
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _sendMessage,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.neonBlue,
              side: BorderSide(
                  color: AppColors.neonBlue.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text('Envoyer un message',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PlayersLeaderboard — Top joueurs (XP / wins) avec bouton message
// ============================================================
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../screens/chat_detail_screen.dart';
import '../services/messaging_service.dart';
import '../utils/logger.dart';

class PlayersLeaderboard extends StatefulWidget {
  const PlayersLeaderboard({super.key});

  @override
  State<PlayersLeaderboard> createState() => _PlayersLeaderboardState();
}

class _PlayersLeaderboardState extends State<PlayersLeaderboard> {
  static const _log = Logger('LEADERBOARD');
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _players = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client
          .from('user_profiles')
          .select('id, username, avatar_url, xp, total_wins, coins, rank, is_online')
          .neq('role', 'banned')
          .order('xp', ascending: false)
          .limit(10);
      if (mounted) {
        setState(() {
          _players = List<Map<String, dynamic>>.from(res);
          _loading = false;
        });
      }
    } catch (e, s) {
      _log.error('load leaderboard', e, s);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat(Map<String, dynamic> player) async {
    final myId = _client.auth.currentUser?.id;
    if (myId == null) return;
    final otherId = player['id'] as String;
    if (myId == otherId) return; // pas de chat avec soi-meme

    try {
      final convId = await MessagingService().getOrCreateConversation(otherId);
      if (!mounted || convId == null) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          conversationId: convId,
          otherUsername: player['username'] as String? ?? 'Joueur',
          otherAvatarUrl: player['avatar_url'] as String?,
          isOnline: (player['is_online'] as bool?) ?? false,
        ),
      ));
    } catch (e, s) {
      _log.error('openChat', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d\'ouvrir le chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.neonYellow.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonYellow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.emoji_events, color: AppColors.neonYellow, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Top joueurs',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.neonYellow.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'XP global',
                    style: TextStyle(
                      color: AppColors.neonYellow,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Liste
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_players.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Aucun joueur classé',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              itemCount: _players.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: AppColors.divider.withValues(alpha: 0.3),
                indent: 60,
                endIndent: 16,
              ),
              itemBuilder: (context, i) => _row(_players[i], i + 1),
            ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> p, int rank) {
    final username = p['username'] as String? ?? 'Joueur';
    final xp = (p['xp'] as num?)?.toInt() ?? 0;
    final wins = (p['total_wins'] as num?)?.toInt() ?? 0;
    final coins = (p['coins'] as num?)?.toInt() ?? 0;
    final isOnline = (p['is_online'] as bool?) ?? false;
    final avatarUrl = p['avatar_url'] as String?;
    final myId = _client.auth.currentUser?.id;
    final isMe = p['id'] == myId;

    Color rankColor;
    IconData? rankIcon;
    if (rank == 1) {
      rankColor = AppColors.neonYellow;
      rankIcon = Icons.emoji_events;
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
      rankIcon = Icons.emoji_events;
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32);
      rankIcon = Icons.emoji_events;
    } else {
      rankColor = AppColors.textMuted;
      rankIcon = null;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // Rang
          SizedBox(
            width: 30,
            child: rankIcon != null
                ? Icon(rankIcon, color: rankColor, size: 18)
                : Text(
                    '#$rank',
                    style: TextStyle(
                      color: rankColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          // Avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.bgElevated,
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? Text(
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      )
                    : null,
              ),
              if (isOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgCard, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          // Username + stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        username,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMe ? AppColors.neonGreen : AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(toi)',
                        style: TextStyle(
                          color: AppColors.neonGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.bolt, size: 10, color: AppColors.neonYellow),
                    const SizedBox(width: 2),
                    Text(
                      '$xp XP',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.military_tech, size: 10, color: AppColors.neonGreen),
                    const SizedBox(width: 2),
                    Text(
                      '$wins W',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.monetization_on, size: 10, color: AppColors.neonOrange),
                    const SizedBox(width: 2),
                    Text(
                      '${coins ~/ 1000}k',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Bouton message (sauf soi-meme)
          if (!isMe)
            IconButton(
              icon: Icon(
                Icons.chat_bubble_outline,
                color: AppColors.neonBlue,
                size: 18,
              ),
              onPressed: () => _openChat(p),
              tooltip: AppLocalizations.of(context)!.chatNewMessage,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 18,
            ),
        ],
      ),
    );
  }
}

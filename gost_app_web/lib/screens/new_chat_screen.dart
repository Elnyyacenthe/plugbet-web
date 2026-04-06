// ============================================================
// Plugbet – Nouveau message (uniquement amis acceptés)
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/player_models.dart';
import '../providers/player_provider.dart';
import '../providers/messaging_provider.dart';
import 'chat_detail_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _searchCtrl = TextEditingController();
  List<FriendModel> _allFriends = [];
  List<FriendModel> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFriends());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final friends = await context.read<PlayerProvider>().getFriends();
    if (mounted) {
      setState(() {
        _allFriends = friends;
        _filtered = friends;
        _loading = false;
      });
    }
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allFriends
          : _allFriends
              .where((f) => f.username.toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _startChat(FriendModel friend) async {
    final provider = context.read<MessagingProvider>();
    final conversationId = await provider.startConversation(friend.oddsId);
    if (conversationId != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            conversationId: conversationId,
            otherUsername: friend.username,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgBlueNight,
        title: Text('Nouveau message'),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Column(
          children: [
            // Barre de recherche parmi les amis
            Padding(
              padding: EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider, width: 0.5),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Rechercher parmi vos amis...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 15),
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, size: 18),
                            color: AppColors.textMuted,
                            onPressed: () {
                              _searchCtrl.clear();
                              _filter('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onChanged: _filter,
                ),
              ),
            ),

            // Info
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
                  SizedBox(width: 6),
                  Text('Seuls vos amis peuvent recevoir des messages',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            SizedBox(height: 8),

            // Liste
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: AppColors.neonGreen))
                  : _filtered.isEmpty
                      ? _buildEmpty()
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final friend = _filtered[i];
                            return _FriendChatTile(
                              friend: friend,
                              onTap: () => _startChat(friend),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    if (_allFriends.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48,
                color: AppColors.textMuted.withValues(alpha: 0.3)),
            SizedBox(height: 12),
            Text('Aucun ami pour le moment',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
            SizedBox(height: 4),
            Text('Ajoutez des amis depuis l\'écran Amis',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48,
              color: AppColors.textMuted.withValues(alpha: 0.3)),
          SizedBox(height: 12),
          Text('Aucun ami trouvé',
              style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _FriendChatTile extends StatelessWidget {
  final FriendModel friend;
  final VoidCallback onTap;

  const _FriendChatTile({required this.friend, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initials = friend.username.isNotEmpty
        ? friend.username[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: friend.rank.color.withValues(alpha: 0.15),
                border: Border.all(color: friend.rank.color.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(initials,
                    style: TextStyle(
                        color: friend.rank.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(friend.username,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text('${friend.rank.label} • ${friend.xp} XP',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chat_bubble_outline, color: AppColors.neonGreen, size: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Plugbet – Ecran liste des conversations
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/chat_models.dart';
import '../providers/messaging_provider.dart';
import 'chat_detail_screen.dart';
import 'new_chat_screen.dart';
import 'user_search_screen.dart';
import 'auth_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessagingProvider>().loadConversations();
    });
    // Rafraîchir la liste des conversations toutes les 8 secondes
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        context.read<MessagingProvider>().loadConversations();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Consumer<MessagingProvider>(
            builder: (context, provider, _) {
              if (!provider.isAuthenticated) {
                return _buildNotAuthenticated();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  Expanded(
                    child: provider.isLoading && provider.conversations.isEmpty
                        ? Center(
                            child: CircularProgressIndicator(
                                color: AppColors.neonGreen))
                        : provider.conversations.isEmpty
                            ? _buildEmptyState()
                            : _buildConversationList(provider),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: Row(
        children: [
          Text(
            'Messages',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -1,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.neonBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.person_search_rounded,
                  color: AppColors.neonBlue, size: 20),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserSearchScreen()),
            ),
            tooltip: 'Trouver des joueurs',
          ),
          IconButton(
            icon: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.neonGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.edit_outlined,
                  color: AppColors.neonGreen, size: 20),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NewChatScreen()),
            ),
            tooltip: 'Nouveau message',
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList(MessagingProvider provider) {
    return RefreshIndicator(
      color: AppColors.neonGreen,
      backgroundColor: AppColors.bgCard,
      onRefresh: provider.loadConversations,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16),
        itemCount: provider.conversations.length,
        itemBuilder: (context, index) {
          return _ConversationTile(
            conversation: provider.conversations[index],
            onTap: () => _openConversation(provider.conversations[index]),
          );
        },
      ),
    );
  }

  void _openConversation(Conversation conv) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          conversationId: conv.id,
          otherUsername: conv.otherUsername,
          isOnline: conv.isOnline,
          lastSeenAt: conv.lastSeenAt,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 64, color: AppColors.textMuted.withValues(alpha: 0.3)),
            SizedBox(height: 16),
            Text(
              'Aucune conversation',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              'Demarrez une conversation avec\nun autre utilisateur',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewChatScreen()),
              ),
              icon: Icon(Icons.add),
              label: Text('Nouvelle conversation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonGreen,
                foregroundColor: AppColors.bgDark,
                padding:
                    EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotAuthenticated() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 64, color: AppColors.textMuted.withValues(alpha: 0.3)),
            SizedBox(height: 16),
            Text(
              'Connectez-vous',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              'Creez un compte pour envoyer\ndes messages prives',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuthScreen()),
              ),
              icon: Icon(Icons.login),
              label: Text('Se connecter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.neonBlue,
                foregroundColor: Colors.white,
                padding:
                    EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Tile de conversation dans la liste
// ============================================================
class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'maintenant';
    if (diff.inHours < 1) return '${diff.inMinutes}min';
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return '${diff.inDays}j';
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;
    final initials = conversation.otherUsername.isNotEmpty
        ? conversation.otherUsername[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hasUnread
              ? AppColors.neonGreen.withValues(alpha: 0.05)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasUnread
                ? AppColors.neonGreen.withValues(alpha: 0.2)
                : AppColors.divider,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            // Avatar + online dot
            Stack(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.neonBlue.withValues(alpha: 0.3),
                        AppColors.neonPurple.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (conversation.isOnline)
                  Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.neonGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bgDark, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: 12),
            // Contenu
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.otherUsername,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3),
                  Text(
                    conversation.lastMessage ?? 'Nouvelle conversation',
                    style: TextStyle(
                      fontSize: 13,
                      color: hasUnread
                          ? AppColors.textSecondary
                          : AppColors.textMuted,
                      fontWeight:
                          hasUnread ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            // Heure + badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime(conversation.updatedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: hasUnread
                        ? AppColors.neonGreen
                        : AppColors.textMuted,
                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (hasUnread) ...[
                  SizedBox(height: 4),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${conversation.unreadCount}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.bgDark,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

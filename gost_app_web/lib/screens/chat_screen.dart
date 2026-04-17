// ============================================================
// Plugbet – Ecran liste des conversations
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/messaging_service.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/chat_models.dart';
import '../providers/messaging_provider.dart';
import '../widgets/user_avatar.dart';
import 'add_status_screen.dart';
import 'chat_detail_screen.dart';
import 'new_chat_screen.dart';
import 'status_viewer_screen.dart';
import 'user_search_screen.dart';
import 'auth_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Timer? _refreshTimer;
  final _service = MessagingService();

  // Lock global partage entre _pickAvatar et _createStatus pour eviter
  // l'erreur "Image picker is already active" quand l'utilisateur tape vite.
  static bool _pickerBusy = false;

  List<UserStatusGroup> _statusGroups = [];
  String? _myAvatarUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessagingProvider>().loadConversations();
      _loadStatuses();
      _loadMyAvatar();
    });
    // Rafraichir la liste des conversations toutes les 8 secondes
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

  Future<void> _loadStatuses() async {
    final groups = await _service.getActiveStatusGroups();
    if (mounted) setState(() => _statusGroups = groups);
  }

  Future<void> _loadMyAvatar() async {
    final url = await _service.getMyAvatarUrl();
    if (mounted) setState(() => _myAvatarUrl = url);
  }

  /// Ouvre le picker pour creer un nouveau statut
  Future<void> _createStatus() async {
    if (_pickerBusy) return;
    _pickerBusy = true;
    try {
      final ok = await AddStatusScreen.pickAndOpen(context);
      if (ok && mounted) _loadStatuses();
    } catch (e) {
      debugPrint('[CHAT] _createStatus: $e');
    } finally {
      _pickerBusy = false;
    }
  }

  /// Ouvre le visualiseur de statuts
  void _openStatusViewer(int groupIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatusViewerScreen(
          groups: _statusGroups,
          initialGroupIndex: groupIndex,
        ),
      ),
    ).then((_) => _loadStatuses());
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
                  _buildStatusBar(provider.myUserId),
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
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: Row(
        children: [
          Text(
            t.tabChat,
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
            tooltip: t.chatNewMessage,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS BAR — Stories 24h style WhatsApp
  // ============================================================
  Widget _buildStatusBar(String? myUserId) {
    final t = AppLocalizations.of(context)!;
    // Separer mon statut et ceux des autres
    UserStatusGroup? myGroup;
    final others = <UserStatusGroup>[];
    for (final g in _statusGroups) {
      if (g.userId == myUserId) {
        myGroup = g;
      } else {
        others.add(g);
      }
    }

    return Container(
      height: 108,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Mon statut
          _StatusBubble(
            username: t.chatMyStatus,
            avatarUrl: _myAvatarUrl,
            ringColor: myGroup != null
                ? (myGroup.hasUnseen
                    ? AppColors.neonGreen
                    : AppColors.textMuted)
                : null,
            showAddButton: myGroup == null,
            onTap: () {
              if (myGroup != null) {
                final index = _statusGroups.indexOf(myGroup);
                _openStatusViewer(index);
              } else {
                _createStatus();
              }
            },
            onAddTap: _createStatus,
          ),
          // Statuts des autres
          ...others.asMap().entries.map((e) {
            final realIndex = _statusGroups.indexOf(e.value);
            return _StatusBubble(
              username: e.value.username,
              avatarUrl: e.value.avatarUrl,
              ringColor: e.value.hasUnseen
                  ? AppColors.neonGreen
                  : AppColors.textMuted.withValues(alpha: 0.6),
              showAddButton: false,
              onTap: () => _openStatusViewer(realIndex),
            );
          }),
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
          otherAvatarUrl: conv.otherAvatarUrl,
          isOnline: conv.isOnline,
          lastSeenAt: conv.lastSeenAt,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = AppLocalizations.of(context)!;
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
              t.chatNoConversations,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              t.chatStartConversation,
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
            UserAvatar(
              avatarUrl: conversation.otherAvatarUrl,
              username: conversation.otherUsername,
              size: 46,
              isOnline: conversation.isOnline,
            ),
            SizedBox(width: 12),
            // Contenu
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          conversation.otherUsername,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.comboCount > 0) ...[
                        const SizedBox(width: 6),
                        _ComboBadge(combo: conversation.comboCount),
                      ],
                    ],
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

// ============================================================
// Status Bubble — bulle d'avatar avec ring colore pour les statuts
// ============================================================
class _StatusBubble extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final Color? ringColor;
  final bool showAddButton;
  final VoidCallback onTap;
  final VoidCallback? onAddTap;

  const _StatusBubble({
    required this.username,
    required this.avatarUrl,
    required this.ringColor,
    required this.showAddButton,
    required this.onTap,
    this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(
                  avatarUrl: avatarUrl,
                  username: username,
                  size: 62,
                  showOnlineDot: false,
                  ringColor: ringColor,
                  ringWidth: ringColor != null ? 2.5 : 0,
                ),
                // Bouton + pour ajouter un statut
                if (showAddButton)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GestureDetector(
                      onTap: onAddTap,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.neonGreen,
                          border: Border.all(
                              color: AppColors.bgDark, width: 2),
                        ),
                        child: const Icon(Icons.add,
                            size: 14, color: Colors.black),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Badge Combo — style multiplicateur paris (x12, x25, x50...)
// Couleur evolutive selon le niveau du combo
// ============================================================
class _ComboBadge extends StatelessWidget {
  final int combo;

  const _ComboBadge({required this.combo});

  // Palier : embleme + degrade selon le niveau
  // 1-9    → medaille bronze
  // 10-24  → medaille argent
  // 25-49  → medaille or
  // 50-99  → trophee
  // 100+   → couronne
  (String, Color, Color) get _tier {
    if (combo >= 100) {
      return ('👑', const Color(0xFFFFD700), const Color(0xFFFFB300));
    }
    if (combo >= 50) {
      return ('🏆', const Color(0xFFFF7043), const Color(0xFFD84315));
    }
    if (combo >= 25) {
      return ('🥇', const Color(0xFFFFCA28), const Color(0xFFF9A825));
    }
    if (combo >= 10) {
      return ('🥈', const Color(0xFFB0BEC5), const Color(0xFF78909C));
    }
    return ('🥉', const Color(0xFFBF8970), const Color(0xFF8D5524));
  }

  @override
  Widget build(BuildContext context) {
    final (emoji, c1, c2) = _tier;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: c1.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 3),
          Text(
            '$combo',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.3,
              shadows: [
                Shadow(
                    color: Colors.black38,
                    offset: Offset(0, 1),
                    blurRadius: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

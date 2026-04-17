// ============================================================
// Plugbet – Écran de conversation privée (WhatsApp-like)
// Typing, reply, delete, reactions, image, voice, search
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/chat_models.dart';
import '../providers/messaging_provider.dart';
import '../widgets/user_avatar.dart';
import '../widgets/chat/date_separator.dart';
import '../widgets/chat/message_bubble.dart';
import '../widgets/chat/typing_dots.dart';
import '../widgets/chat/chat_combo_badge.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String otherUsername;
  final String? otherAvatarUrl;
  final bool isOnline;
  final DateTime? lastSeenAt;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.otherUsername,
    this.otherAvatarUrl,
    this.isOnline = false,
    this.lastSeenAt,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  late MessagingProvider _provider;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<PrivateMessage> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _provider = context.read<MessagingProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.openConversation(widget.conversationId);
    });
    _messageController.addListener(() {
      _provider.onTextChanged(_messageController.text);
    });
  }

  @override
  void dispose() {
    _provider.closeConversation();
    _messageController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    await _provider.sendMessage(text);
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 75,
      );
      if (xfile == null) return;

      final file = File(xfile.path);
      await _provider.sendImage(file);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.chatCannotOpenGallery), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        imageQuality: 75,
      );
      if (xfile == null) return;

      final file = File(xfile.path);
      await _provider.sendImage(file);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.chatCannotOpenCamera), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _attachOption(Icons.photo_library, 'Galerie', AppColors.neonGreen, () {
              Navigator.pop(ctx);
              _pickImage();
            }),
            _attachOption(Icons.camera_alt, 'Caméra', AppColors.neonBlue, () {
              Navigator.pop(ctx);
              _takePhoto();
            }),
          ],
        ),
      ),
    );
  }

  Widget _attachOption(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          SizedBox(height: 8),
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'en ligne';
    if (diff.inMinutes < 60) return 'vu il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'vu il y a ${diff.inHours}h';
    return 'vu il y a ${diff.inDays}j';
  }

  void _showReactions(PrivateMessage msg) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: emojis.map((emoji) => GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              _provider.toggleReaction(msg.id, emoji);
            },
            child: Text(emoji, style: TextStyle(fontSize: 32)),
          )).toList(),
        ),
      ),
    );
  }

  void _showMessageOptions(PrivateMessage msg, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
            SizedBox(height: 16),
            if (!msg.isDeleted) ...[
              _optionTile(Icons.reply, 'Répondre', () {
                Navigator.pop(ctx);
                _provider.setReplyTo(msg);
                _focusNode.requestFocus();
              }),
              _optionTile(Icons.emoji_emotions_outlined, 'Réagir', () {
                Navigator.pop(ctx);
                _showReactions(msg);
              }),
              _optionTile(Icons.copy, AppLocalizations.of(context)!.commonCopy, () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(AppLocalizations.of(context)!.commonCopied), duration: Duration(seconds: 1)),
                );
              }),
              if (isMe)
                _optionTile(Icons.delete_outline, AppLocalizations.of(context)!.commonDelete, () {
                  Navigator.pop(ctx);
                  _confirmDelete(msg);
                }, color: AppColors.neonRed),
            ],
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textPrimary, size: 22),
      title: Text(label, style: TextStyle(color: color ?? AppColors.textPrimary, fontSize: 15)),
      onTap: onTap,
    );
  }

  void _confirmDelete(PrivateMessage msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context)!.chatDeleteMessageTitle,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text(AppLocalizations.of(context)!.chatDeleteMessageConfirm,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel, style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _provider.deleteMessage(msg.id);
            },
            child: Text(AppLocalizations.of(context)!.commonDelete, style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: _isSearching ? _buildSearchAppBar() : _buildNormalAppBar(),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.bgGradient),
        child: Column(
          children: [
            // Typing indicator
            Consumer<MessagingProvider>(
              builder: (context, provider, _) {
                if (!provider.otherIsTyping) return SizedBox.shrink();
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20, height: 12,
                        child: const TypingDots(),
                      ),
                      SizedBox(width: 8),
                      Text('${widget.otherUsername} écrit...',
                          style: TextStyle(color: AppColors.neonGreen, fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                  ),
                );
              },
            ),

            // Messages
            Expanded(
              child: Consumer<MessagingProvider>(
                builder: (context, provider, _) {
                  final messages = _isSearching && _searchResults.isNotEmpty
                      ? _searchResults
                      : provider.currentMessages;

                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline, color: AppColors.textMuted.withValues(alpha: 0.3), size: 48),
                          SizedBox(height: 12),
                          Text(AppLocalizations.of(context)!.chatSendFirstMessage,
                              style: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.5), fontSize: 14)),
                        ],
                      ),
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                  return ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg.fromUserId == provider.myUserId;

                      // Séparateur de date
                      Widget? dateSeparator;
                      if (index == 0 || !_sameDay(messages[index - 1].createdAt, msg.createdAt)) {
                        dateSeparator = DateSeparator(date: msg.createdAt);
                      }

                      return Column(
                        children: [
                          if (dateSeparator != null) dateSeparator,
                          GestureDetector(
                            onLongPress: () => _showMessageOptions(msg, isMe),
                            onDoubleTap: () {
                              if (!msg.isDeleted) _showReactions(msg);
                            },
                            child: MessageBubble(
                              message: msg,
                              isMe: isMe,
                              allMessages: messages,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            // Reply preview
            Consumer<MessagingProvider>(
              builder: (context, provider, _) {
                final reply = provider.replyTo;
                if (reply == null) return SizedBox.shrink();
                return Container(
                  padding: EdgeInsets.fromLTRB(16, 8, 8, 0),
                  decoration: BoxDecoration(
                    color: AppColors.bgCard,
                    border: Border(top: BorderSide(color: AppColors.neonGreen.withValues(alpha: 0.3))),
                  ),
                  child: Row(
                    children: [
                      Container(width: 3, height: 36, color: AppColors.neonGreen),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppLocalizations.of(context)!.chatReply,
                                style: TextStyle(color: AppColors.neonGreen, fontSize: 11, fontWeight: FontWeight.w700)),
                            Text(reply.content,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: AppColors.textMuted),
                        onPressed: () => provider.setReplyTo(null),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Input
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      backgroundColor: AppColors.bgBlueNight,
      title: Row(
        children: [
          UserAvatar(
            avatarUrl: widget.otherAvatarUrl,
            username: widget.otherUsername,
            size: 36,
            isOnline: widget.isOnline,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(widget.otherUsername,
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    // Badge combo (rebuild seulement quand le combo change)
                    Selector<MessagingProvider, int>(
                      selector: (_, p) {
                        final conv = p.conversations.cast<Conversation?>().firstWhere(
                              (c) => c?.id == widget.conversationId,
                              orElse: () => null,
                            );
                        return conv?.comboCount ?? 0;
                      },
                      builder: (_, combo, __) {
                        if (combo <= 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChatComboBadge(combo: combo),
                        );
                      },
                    ),
                  ],
                ),
                if (widget.isOnline)
                  Text(AppLocalizations.of(context)!.chatOnline, style: TextStyle(fontSize: 11, color: AppColors.neonGreen))
                else if (widget.lastSeenAt != null)
                  Text(_formatLastSeen(widget.lastSeenAt),
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.search, color: AppColors.textSecondary),
          onPressed: () => setState(() => _isSearching = true),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: AppColors.bgBlueNight,
      leading: IconButton(
        icon: Icon(Icons.arrow_back),
        onPressed: () => setState(() {
          _isSearching = false;
          _searchResults = [];
          _searchController.clear();
        }),
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Rechercher...',
          hintStyle: TextStyle(color: AppColors.textMuted),
          border: InputBorder.none,
        ),
        onChanged: (q) async {
          if (q.length >= 2) {
            final results = await _provider.searchMessages(q);
            setState(() => _searchResults = results);
          } else {
            setState(() => _searchResults = []);
          }
        },
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.divider.withValues(alpha: 0.5), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Attach button
            GestureDetector(
              onTap: _showAttachMenu,
              child: Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.attach_file, color: AppColors.textSecondary, size: 22),
              ),
            ),
            SizedBox(width: 4),

            // Text field
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.divider.withValues(alpha: 0.5), width: 0.5),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Votre message...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            SizedBox(width: 8),

            // Send button
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.neonGreen,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.send_rounded, color: AppColors.bgDark, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

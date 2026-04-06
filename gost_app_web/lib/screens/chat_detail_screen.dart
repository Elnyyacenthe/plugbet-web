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
import '../models/chat_models.dart';
import '../providers/messaging_provider.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String otherUsername;
  final bool isOnline;
  final DateTime? lastSeenAt;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.otherUsername,
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
          SnackBar(content: Text('Impossible d\'ouvrir la galerie'), backgroundColor: Colors.red),
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
          SnackBar(content: Text('Impossible d\'ouvrir la caméra'), backgroundColor: Colors.red),
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
              _optionTile(Icons.copy, 'Copier', () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copié'), duration: Duration(seconds: 1)),
                );
              }),
              if (isMe)
                _optionTile(Icons.delete_outline, 'Supprimer', () {
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
        title: Text('Supprimer ce message ?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('Cette action est irréversible.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _provider.deleteMessage(msg.id);
            },
            child: Text('Supprimer', style: TextStyle(color: AppColors.neonRed)),
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
                        child: _TypingDots(),
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
                          Text('Envoyez le premier message !',
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
                        dateSeparator = _DateSeparator(date: msg.createdAt);
                      }

                      return Column(
                        children: [
                          if (dateSeparator != null) dateSeparator,
                          GestureDetector(
                            onLongPress: () => _showMessageOptions(msg, isMe),
                            onDoubleTap: () {
                              if (!msg.isDeleted) _showReactions(msg);
                            },
                            child: _MessageBubble(
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
                            Text('Réponse',
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
          Stack(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [
                    AppColors.neonBlue.withValues(alpha: 0.3),
                    AppColors.neonPurple.withValues(alpha: 0.3),
                  ]),
                ),
                child: Center(
                  child: Text(
                    widget.otherUsername.isNotEmpty ? widget.otherUsername[0].toUpperCase() : '?',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (widget.isOnline)
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bgBlueNight, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.otherUsername,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                if (widget.isOnline)
                  Text('En ligne', style: TextStyle(fontSize: 11, color: AppColors.neonGreen))
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

// ============================================================
// Séparateur de date
// ============================================================
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  String _format() {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return "Aujourd'hui";
    }
    final yesterday = now.subtract(Duration(days: 1));
    if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
      return 'Hier';
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.bgElevated.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(_format(),
              style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

// ============================================================
// Bulle de message WhatsApp-like
// ============================================================
class _MessageBubble extends StatelessWidget {
  final PrivateMessage message;
  final bool isMe;
  final List<PrivateMessage> allMessages;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.allMessages,
  });

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: message.reactions.isEmpty ? 4 : 14),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMe) SizedBox(width: 50),
          Flexible(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppColors.neonGreen.withValues(alpha: 0.15)
                        : AppColors.bgElevated,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                    border: Border.all(
                      color: isMe
                          ? AppColors.neonGreen.withValues(alpha: 0.2)
                          : AppColors.divider.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reply preview
                      if (message.replyToId != null) _buildReplyPreview(),

                      // Content
                      if (message.isDeleted)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.block, size: 14, color: AppColors.textMuted),
                            SizedBox(width: 4),
                            Text('Message supprimé',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontStyle: FontStyle.italic)),
                          ],
                        )
                      else if (message.messageType == MessageType.image && message.mediaUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            message.mediaUrl!,
                            width: 220,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return SizedBox(
                                width: 220, height: 150,
                                child: Center(child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.neonGreen)),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              width: 220, height: 100,
                              color: AppColors.bgCard,
                              child: Icon(Icons.broken_image, color: AppColors.textMuted),
                            ),
                          ),
                        )
                      else if (message.messageType == MessageType.voice)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mic, size: 18, color: AppColors.neonGreen),
                            SizedBox(width: 6),
                            Text('${message.mediaDuration ?? 0}s',
                                style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                            SizedBox(width: 8),
                            Container(
                              width: 120, height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.neonGreen.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2)),
                            ),
                          ],
                        )
                      else
                        Text(message.content,
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),

                      SizedBox(height: 3),

                      // Time + status
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.isEdited) ...[
                            Text('modifié ', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontStyle: FontStyle.italic)),
                          ],
                          Text(_formatTime(message.createdAt),
                              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                          if (isMe && !message.isDeleted) ...[
                            SizedBox(width: 3),
                            Icon(
                              message.isRead ? Icons.done_all : Icons.done,
                              size: 13,
                              color: message.isRead ? AppColors.neonGreen : AppColors.textMuted,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Reactions overlay
                if (message.reactions.isNotEmpty)
                  Positioned(
                    bottom: -10,
                    right: isMe ? null : 8,
                    left: isMe ? 8 : null,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _buildReactionChips(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!isMe) SizedBox(width: 50),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    // Chercher le message original dans la liste
    final original = allMessages.where((m) => m.id == message.replyToId).firstOrNull;
    final previewText = original?.content ?? '...';

    return Container(
      margin: EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.bgDark.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppColors.neonGreen, width: 3)),
      ),
      child: Text(
        previewText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    );
  }

  List<Widget> _buildReactionChips() {
    final grouped = <String, int>{};
    for (final r in message.reactions) {
      grouped[r.emoji] = (grouped[r.emoji] ?? 0) + 1;
    }
    return grouped.entries.map((e) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: Text('${e.key}${e.value > 1 ? e.value : ''}',
          style: TextStyle(fontSize: 12)),
    )).toList();
  }
}

// ============================================================
// Animation "en train d'écrire" (3 points)
// ============================================================
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final offset = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
          final opacity = (1 - (offset - 0.5).abs() * 2).clamp(0.3, 1.0);
          return Container(
            width: 5, height: 5,
            margin: EdgeInsets.only(right: i < 2 ? 3 : 0),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

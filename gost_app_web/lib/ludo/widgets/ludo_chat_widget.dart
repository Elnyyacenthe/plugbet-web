import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../models/ludo_models.dart';
import '../services/ludo_service.dart';

class LudoChatWidget extends StatefulWidget {
  final String gameId;

  const LudoChatWidget({super.key, required this.gameId});

  @override
  State<LudoChatWidget> createState() => _LudoChatWidgetState();
}

class _LudoChatWidgetState extends State<LudoChatWidget> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _service = LudoService();
  List<ChatMessage> _messages = [];
  RealtimeChannel? _chatChannel;

  static const _quickMessages = [
    'Bien joue !',
    'GG',
    'Lol',
    'Bonne chance',
    'Bravo !',
    'Oups...',
  ];

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribe();
  }

  @override
  void dispose() {
    if (_chatChannel != null) _service.unsubscribe(_chatChannel!);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final msgs = await _service.getChatMessages(widget.gameId);
    if (mounted) {
      setState(() => _messages = msgs);
      _scrollToBottom();
    }
  }

  void _subscribe() {
    _chatChannel = _service.subscribeChatMessages(widget.gameId, (msg) {
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _controller.clear();
    await _service.sendChatMessage(widget.gameId, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final myId = _service.currentUserId;

    return Container(
      height: MediaQuery.of(context).size.height * 0.45,
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Chat',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),

          // Quick messages
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 12),
              itemCount: _quickMessages.length,
              separatorBuilder: (_, __) => SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _sendMessage(_quickMessages[i]),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    _quickMessages[i],
                    style: TextStyle(
                      color: AppColors.neonGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 8),

          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Aucun message',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      final isMe = msg.userId == myId;
                      return _buildBubble(msg, isMe);
                    },
                  ),
          ),

          // Input bar
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 8, 12),
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        hintStyle: TextStyle(color: AppColors.textMuted),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: AppColors.neonGreen),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _sendMessage(_controller.text),
                    icon: Icon(Icons.send_rounded, color: AppColors.neonGreen),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 3),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.neonGreen.withValues(alpha: 0.15)
              : AppColors.bgDark,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(12),
          ),
        ),
        child: Text(
          msg.message,
          style: TextStyle(
            color: isMe ? AppColors.neonGreen : AppColors.textPrimary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

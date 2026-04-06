// ============================================================
// Plugbet – Provider de messagerie privée (WhatsApp-like)
// Typing indicator, online status, reactions, media, search
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_models.dart';
import '../services/notification_service.dart';
import '../services/messaging_service.dart';

class MessagingProvider extends ChangeNotifier {
  final MessagingService _service = MessagingService();

  List<Conversation> _conversations = [];
  List<PrivateMessage> _currentMessages = [];
  String? _currentConversationId;
  bool _isLoading = false;
  bool _otherIsTyping = false;
  Timer? _typingTimer;
  bool _iAmTyping = false;

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _conversationsChannel;
  RealtimeChannel? _typingChannel;
  RealtimeChannel? _reactionsChannel;
  Timer? _reactionDebounce;

  // ── Getters ───────────────────────────────────────────────
  List<Conversation> get conversations => _conversations;
  List<PrivateMessage> get currentMessages => _currentMessages;
  bool get isLoading => _isLoading;
  String? get currentConversationId => _currentConversationId;
  bool get otherIsTyping => _otherIsTyping;

  int get unreadTotal =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  bool get isAuthenticated =>
      Supabase.instance.client.auth.currentUser != null;

  String? get myUserId => Supabase.instance.client.auth.currentUser?.id;

  // ── Message en réponse ────────────────────────────────────
  PrivateMessage? _replyTo;
  PrivateMessage? get replyTo => _replyTo;

  void setReplyTo(PrivateMessage? msg) {
    _replyTo = msg;
    notifyListeners();
  }

  // ============================================================
  // PRESENCE
  // ============================================================

  Future<void> goOnline() async => _service.updatePresence(true);
  Future<void> goOffline() async => _service.updatePresence(false);

  // ============================================================
  // CONVERSATIONS
  // ============================================================

  Future<void> loadConversations() async {
    if (!isAuthenticated) return;

    _isLoading = true;
    notifyListeners();

    _conversations = await _service.getConversations();

    _isLoading = false;
    notifyListeners();

    _subscribeToConversations();
  }

  void _subscribeToConversations() {
    if (_conversationsChannel != null) return;
    _conversationsChannel = _service.subscribeToConversations(() {
      loadConversations();
    });
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  Future<void> openConversation(String conversationId) async {
    _currentConversationId = conversationId;
    _currentMessages = [];
    _replyTo = null;
    _otherIsTyping = false;
    notifyListeners();

    _currentMessages = await _service.getMessages(conversationId);
    notifyListeners();

    await _service.markAsRead(conversationId);

    _conversations = _conversations.map((c) {
      if (c.id == conversationId) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();
    notifyListeners();

    _subscribeToMessages(conversationId);
    _subscribeToTyping(conversationId);
    _subscribeToReactions(conversationId);
  }

  void _subscribeToMessages(String conversationId) {
    if (_messagesChannel != null) {
      _service.unsubscribe(_messagesChannel!);
    }

    _messagesChannel = _service.subscribeToMessages(conversationId, (msg) {
      if (!_currentMessages.any((m) => m.id == msg.id)) {
        _currentMessages = [..._currentMessages, msg];
        notifyListeners();

        if (msg.fromUserId != myUserId) {
          _service.markAsRead(conversationId);
          // Notification push locale
          final conv = _conversations.cast<Conversation?>().firstWhere(
            (c) => c!.id == conversationId, orElse: () => null);
          NotificationService.instance.showMessageNotification(
            senderName: conv?.otherUsername ?? 'Nouveau message',
            messagePreview: msg.content.length > 80
                ? '${msg.content.substring(0, 80)}...'
                : msg.content,
            conversationId: conversationId,
          );
        }
      }
    });
  }

  void _subscribeToTyping(String conversationId) {
    if (_typingChannel != null) {
      _service.unsubscribe(_typingChannel!);
    }

    _typingChannel = _service.subscribeToTyping(conversationId, (isTyping) {
      _otherIsTyping = isTyping;
      notifyListeners();
    });
  }

  void _subscribeToReactions(String conversationId) {
    if (_reactionsChannel != null) {
      _service.unsubscribe(_reactionsChannel!);
    }

    _reactionsChannel = _service.subscribeToReactions(conversationId, () {
      // Debounce : recharger les réactions max 1x / 2s (pas à chaque emoji)
      _reactionDebounce?.cancel();
      _reactionDebounce = Timer(const Duration(seconds: 2), () {
        _reloadMessages();
      });
    });
  }

  Future<void> _reloadMessages() async {
    if (_currentConversationId == null) return;
    _currentMessages = await _service.getMessages(_currentConversationId!);
    notifyListeners();
  }

  // ============================================================
  // TYPING INDICATOR
  // ============================================================

  void onTextChanged(String text) {
    if (_currentConversationId == null) return;

    if (!_iAmTyping && text.isNotEmpty) {
      _iAmTyping = true;
      _service.setTyping(_currentConversationId!, true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _iAmTyping = false;
      if (_currentConversationId != null) {
        _service.setTyping(_currentConversationId!, false);
      }
    });
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_iAmTyping && _currentConversationId != null) {
      _iAmTyping = false;
      _service.setTyping(_currentConversationId!, false);
    }
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<bool> sendMessage(String content, {
    MessageType messageType = MessageType.text,
    String? mediaUrl,
    int? mediaDuration,
  }) async {
    if (_currentConversationId == null) return false;

    _stopTyping();

    final ok = await _service.sendMessage(
      _currentConversationId!,
      content,
      replyToId: _replyTo?.id,
      messageType: messageType,
      mediaUrl: mediaUrl,
      mediaDuration: mediaDuration,
    );

    if (ok) {
      _replyTo = null;
      notifyListeners();
    }

    return ok;
  }

  // ============================================================
  // MEDIA
  // ============================================================

  Future<bool> sendImage(File imageFile) async {
    if (_currentConversationId == null) return false;

    final url = await _service.uploadMedia(imageFile, folder: 'chat/images');
    if (url == null) return false;

    return sendMessage('', messageType: MessageType.image, mediaUrl: url);
  }

  Future<bool> sendVoice(File voiceFile, int durationSecs) async {
    if (_currentConversationId == null) return false;

    final url = await _service.uploadMedia(voiceFile, folder: 'chat/voice');
    if (url == null) return false;

    return sendMessage('', messageType: MessageType.voice,
        mediaUrl: url, mediaDuration: durationSecs);
  }

  // ============================================================
  // REACTIONS
  // ============================================================

  Future<void> toggleReaction(String messageId, String emoji) async {
    final existing = _currentMessages
        .firstWhere((m) => m.id == messageId, orElse: () => _currentMessages.first)
        .reactions
        .where((r) => r.userId == myUserId && r.emoji == emoji);

    if (existing.isNotEmpty) {
      await _service.removeReaction(messageId);
    } else {
      await _service.addReaction(messageId, emoji);
    }
  }

  // ============================================================
  // DELETE MESSAGE
  // ============================================================

  Future<bool> deleteMessage(String messageId) async {
    final ok = await _service.deleteMessage(messageId);
    if (ok) {
      _currentMessages = _currentMessages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(deletedAt: DateTime.now());
        }
        return m;
      }).toList();
      notifyListeners();
    }
    return ok;
  }

  // ============================================================
  // SEARCH
  // ============================================================

  Future<List<PrivateMessage>> searchMessages(String query) async {
    if (_currentConversationId == null) return [];
    return _service.searchMessages(_currentConversationId!, query);
  }

  // ============================================================
  // CONVERSATION ACTIONS
  // ============================================================

  Future<void> togglePin(String convId) async {
    final conv = _conversations.firstWhere((c) => c.id == convId);
    final isUser1 = Supabase.instance.client.auth.currentUser?.id == conv.otherUserId ? false : true;
    await _service.togglePin(convId, !conv.isPinned, isUser1);
    await loadConversations();
  }

  Future<void> toggleMute(String convId) async {
    final conv = _conversations.firstWhere((c) => c.id == convId);
    final isUser1 = Supabase.instance.client.auth.currentUser?.id == conv.otherUserId ? false : true;
    await _service.toggleMute(convId, !conv.isMuted, isUser1);
    await loadConversations();
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void closeConversation() {
    _stopTyping();
    if (_messagesChannel != null) {
      _service.unsubscribe(_messagesChannel!);
      _messagesChannel = null;
    }
    if (_typingChannel != null) {
      _service.unsubscribe(_typingChannel!);
      _typingChannel = null;
    }
    if (_reactionsChannel != null) {
      _service.unsubscribe(_reactionsChannel!);
      _reactionsChannel = null;
    }
    _currentConversationId = null;
    _currentMessages = [];
    _replyTo = null;
    _otherIsTyping = false;
  }

  Future<String?> startConversation(String otherUserId) async {
    return _service.getOrCreateConversation(otherUserId);
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    return _service.searchUsers(query);
  }

  // ============================================================
  // PUSH TOKEN
  // ============================================================

  Future<void> savePushToken(String token) async {
    await _service.savePushToken(token);
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  @override
  void dispose() {
    _stopTyping();
    _reactionDebounce?.cancel();
    if (_messagesChannel != null) _service.unsubscribe(_messagesChannel!);
    if (_conversationsChannel != null) _service.unsubscribe(_conversationsChannel!);
    if (_typingChannel != null) _service.unsubscribe(_typingChannel!);
    if (_reactionsChannel != null) _service.unsubscribe(_reactionsChannel!);
    super.dispose();
  }
}

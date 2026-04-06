// ============================================================
// Plugbet – Service de messagerie privée (Supabase) – WhatsApp-like
// Tables : conversations, private_messages, user_profiles,
//          message_reactions, typing_indicators, push_tokens
// ============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_models.dart';

class MessagingService {
  final SupabaseClient _client;

  MessagingService() : _client = Supabase.instance.client;

  String? get _myId => _client.auth.currentUser?.id;

  // ============================================================
  // CONVERSATIONS
  // ============================================================

  Future<List<Conversation>> getConversations() async {
    final myId = _myId;
    if (myId == null) return [];

    try {
      final data = await _client
          .from('conversations')
          .select()
          .or('user1_id.eq.$myId,user2_id.eq.$myId')
          .order('updated_at', ascending: false);

      final conversations = <Conversation>[];
      for (final row in data as List) {
        final conv = row as Map<String, dynamic>;

        final otherUserId =
            conv['user1_id'] == myId ? conv['user2_id'] : conv['user1_id'];
        try {
          final profile = await _client
              .from('user_profiles')
              .select('username, is_online, last_seen_at')
              .eq('id', otherUserId as String)
              .maybeSingle();
          final key = conv['user1_id'] == myId ? 'user2_username' : 'user1_username';
          conv[key] = profile?['username'] ?? 'Utilisateur';
          conv['other_online'] = profile?['is_online'] ?? false;
          conv['other_last_seen'] = profile?['last_seen_at'];
        } catch (_) {
          conv[conv['user1_id'] == myId ? 'user2_username' : 'user1_username'] =
              'Utilisateur';
        }

        try {
          final unreadData = await _client
              .from('private_messages')
              .select()
              .eq('conversation_id', conv['id'] as String)
              .eq('is_read', false)
              .neq('from_user_id', myId)
              .count(CountOption.exact);
          conv['unread_count'] = unreadData.count;
        } catch (_) {
          conv['unread_count'] = 0;
        }

        conversations.add(Conversation.fromJson(conv, myId));
      }

      return conversations;
    } catch (e) {
      debugPrint('[MESSAGING] Erreur getConversations: $e');
      return [];
    }
  }

  Future<String?> getOrCreateConversation(String otherUserId) async {
    final myId = _myId;
    if (myId == null) return null;

    try {
      final existing = await _client
          .from('conversations')
          .select('id')
          .or('and(user1_id.eq.$myId,user2_id.eq.$otherUserId),and(user1_id.eq.$otherUserId,user2_id.eq.$myId)')
          .maybeSingle();

      if (existing != null) return existing['id'] as String;

      final result = await _client.from('conversations').insert({
        'user1_id': myId,
        'user2_id': otherUserId,
      }).select('id').single();

      return result['id'] as String;
    } catch (e) {
      debugPrint('[MESSAGING] Erreur getOrCreateConversation: $e');
      return null;
    }
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  Future<List<PrivateMessage>> getMessages(String conversationId,
      {int limit = 100}) async {
    try {
      final data = await _client
          .from('private_messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .limit(limit);

      final messages = (data as List)
          .map((row) => PrivateMessage.fromJson(row as Map<String, dynamic>))
          .toList();

      // Charger les réactions pour chaque message
      if (messages.isNotEmpty) {
        try {
          final messageIds = messages.map((m) => m.id).toList();
          final reactionsData = await _client
              .from('message_reactions')
              .select()
              .inFilter('message_id', messageIds);
          final reactionsByMsg = <String, List<MessageReaction>>{};
          for (final r in reactionsData as List) {
            final reaction = MessageReaction.fromJson(r as Map<String, dynamic>);
            reactionsByMsg.putIfAbsent(reaction.messageId, () => []).add(reaction);
          }
          return messages.map((m) {
            final reactions = reactionsByMsg[m.id] ?? [];
            return reactions.isEmpty ? m : m.copyWith(reactions: reactions);
          }).toList();
        } catch (_) {
          // Réactions pas encore disponibles, continuer sans
        }
      }

      return messages;
    } catch (e) {
      debugPrint('[MESSAGING] Erreur getMessages: $e');
      return [];
    }
  }

  /// Envoyer un message texte
  Future<bool> sendMessage(
    String conversationId,
    String content, {
    String? replyToId,
    MessageType messageType = MessageType.text,
    String? mediaUrl,
    int? mediaDuration,
  }) async {
    final myId = _myId;
    if (myId == null) return false;
    if (messageType == MessageType.text && content.trim().isEmpty) return false;

    try {
      await _client.from('private_messages').insert({
        'conversation_id': conversationId,
        'from_user_id': myId,
        'content': content.trim(),
        'message_type': messageTypeToString(messageType),
        if (replyToId != null) 'reply_to_id': replyToId,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaDuration != null) 'media_duration': mediaDuration,
      });

      // Preview du dernier message
      String preview = content.trim();
      if (messageType == MessageType.image) preview = '📷 Photo';
      if (messageType == MessageType.voice) preview = '🎤 Message vocal';

      await _client.from('conversations').update({
        'last_message': preview,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', conversationId);

      return true;
    } catch (e) {
      debugPrint('[MESSAGING] Erreur sendMessage: $e');
      return false;
    }
  }

  /// Marquer comme lus + timestamp
  Future<void> markAsRead(String conversationId) async {
    final myId = _myId;
    if (myId == null) return;

    try {
      await _client
          .from('private_messages')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('conversation_id', conversationId)
          .neq('from_user_id', myId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('[MESSAGING] Erreur markAsRead: $e');
    }
  }

  /// Supprimer un message (soft delete)
  Future<bool> deleteMessage(String messageId) async {
    final myId = _myId;
    if (myId == null) return false;

    try {
      await _client
          .from('private_messages')
          .update({
            'deleted_at': DateTime.now().toIso8601String(),
            'content': '',
            'media_url': null,
          })
          .eq('id', messageId)
          .eq('from_user_id', myId); // Seul l'auteur peut supprimer
      return true;
    } catch (e) {
      debugPrint('[MESSAGING] Erreur deleteMessage: $e');
      return false;
    }
  }

  // ============================================================
  // RÉACTIONS
  // ============================================================

  Future<bool> addReaction(String messageId, String emoji) async {
    final myId = _myId;
    if (myId == null) return false;

    try {
      await _client.from('message_reactions').upsert({
        'message_id': messageId,
        'user_id': myId,
        'emoji': emoji,
      }, onConflict: 'message_id,user_id');
      return true;
    } catch (e) {
      debugPrint('[MESSAGING] Erreur addReaction: $e');
      return false;
    }
  }

  Future<bool> removeReaction(String messageId) async {
    final myId = _myId;
    if (myId == null) return false;

    try {
      await _client
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', myId);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // TYPING INDICATOR
  // ============================================================

  Future<void> setTyping(String conversationId, bool isTyping) async {
    final myId = _myId;
    if (myId == null) return;

    try {
      await _client.from('typing_indicators').upsert({
        'user_id': myId,
        'conversation_id': conversationId,
        'is_typing': isTyping,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,conversation_id');
    } catch (_) {}
  }

  RealtimeChannel subscribeToTyping(
    String conversationId,
    void Function(bool isTyping) onTypingChanged,
  ) {
    final myId = _myId;
    return _client
        .channel('typing-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'typing_indicators',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record['user_id'] != myId) {
              onTypingChanged(record['is_typing'] as bool? ?? false);
            }
          },
        )
        .subscribe();
  }

  // ============================================================
  // PRESENCE (en ligne / dernière connexion)
  // ============================================================

  Future<void> updatePresence(bool online) async {
    try {
      await _client.rpc('update_user_presence', params: {'p_online': online});
    } catch (e) {
      debugPrint('[MESSAGING] Erreur updatePresence: $e');
    }
  }

  // ============================================================
  // MEDIA UPLOAD (images & voix)
  // ============================================================

  Future<String?> uploadMedia(File file, {String folder = 'chat'}) async {
    final myId = _myId;
    if (myId == null) return null;

    try {
      final ext = file.path.split('.').last;
      final fileName = '${myId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = '$folder/$fileName';

      await _client.storage.from('chat-media').upload(path, file);
      final url = _client.storage.from('chat-media').getPublicUrl(path);
      return url;
    } catch (e) {
      debugPrint('[MESSAGING] Erreur uploadMedia: $e');
      return null;
    }
  }

  // ============================================================
  // RECHERCHE DE MESSAGES
  // ============================================================

  Future<List<PrivateMessage>> searchMessages(
    String conversationId,
    String query,
  ) async {
    if (query.trim().isEmpty) return [];

    try {
      final data = await _client
          .from('private_messages')
          .select()
          .eq('conversation_id', conversationId)
          .ilike('content', '%${query.trim()}%')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(50);

      return (data as List)
          .map((row) => PrivateMessage.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[MESSAGING] Erreur searchMessages: $e');
      return [];
    }
  }

  // ============================================================
  // CONVERSATION ACTIONS (pin, mute)
  // ============================================================

  Future<void> togglePin(String convId, bool isPinned, bool isUser1) async {
    final col = isUser1 ? 'is_pinned_user1' : 'is_pinned_user2';
    try {
      await _client.from('conversations').update({col: isPinned}).eq('id', convId);
    } catch (_) {}
  }

  Future<void> toggleMute(String convId, bool isMuted, bool isUser1) async {
    final col = isUser1 ? 'is_muted_user1' : 'is_muted_user2';
    try {
      await _client.from('conversations').update({col: isMuted}).eq('id', convId);
    } catch (_) {}
  }

  // ============================================================
  // RECHERCHE UTILISATEURS
  // ============================================================

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final myId = _myId;
    if (myId == null || query.trim().isEmpty) return [];

    try {
      final data = await _client
          .from('user_profiles')
          .select('id, username')
          .ilike('username', '%${query.trim()}%')
          .neq('id', myId)
          .limit(20);

      return (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[MESSAGING] Erreur searchUsers: $e');
      return [];
    }
  }

  // ============================================================
  // PUSH TOKEN
  // ============================================================

  Future<void> savePushToken(String token, {String platform = 'android'}) async {
    final myId = _myId;
    if (myId == null) return;

    try {
      await _client.from('push_tokens').upsert({
        'user_id': myId,
        'token': token,
        'platform': platform,
      }, onConflict: 'user_id,token');
    } catch (_) {}
  }

  // ============================================================
  // REALTIME
  // ============================================================

  RealtimeChannel subscribeToMessages(
    String conversationId,
    void Function(PrivateMessage) onMessage,
  ) {
    return _client
        .channel('chat-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'private_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            try {
              final msg = PrivateMessage.fromJson(payload.newRecord);
              onMessage(msg);
            } catch (e) {
              debugPrint('[MESSAGING] Erreur parsing realtime message: $e');
            }
          },
        )
        .subscribe();
  }

  RealtimeChannel subscribeToReactions(
    String conversationId,
    void Function() onReactionChanged,
  ) {
    return _client
        .channel('reactions-$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (_) => onReactionChanged(),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToConversations(void Function() onUpdate) {
    return _client
        .channel('my-conversations')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          callback: (_) => onUpdate(),
        )
        .subscribe();
  }

  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}

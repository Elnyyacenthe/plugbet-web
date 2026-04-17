// ============================================================
// Plugbet – Modèles de messagerie privée (WhatsApp-like)
// ============================================================

// ── Types de message ────────────────────────────────────────
enum MessageType { text, image, voice, system }

MessageType messageTypeFromString(String? s) {
  switch (s) {
    case 'image': return MessageType.image;
    case 'voice': return MessageType.voice;
    case 'system': return MessageType.system;
    default: return MessageType.text;
  }
}

String messageTypeToString(MessageType t) {
  switch (t) {
    case MessageType.image: return 'image';
    case MessageType.voice: return 'voice';
    case MessageType.system: return 'system';
    case MessageType.text: return 'text';
  }
}

// ── Conversation ────────────────────────────────────────────
class Conversation {
  final String id;
  final String otherUserId;
  final String otherUsername;
  final String? otherAvatarUrl;
  final String? lastMessage;
  final DateTime updatedAt;
  final int unreadCount;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final bool isPinned;
  final bool isMuted;
  final int comboCount;
  final int comboMax;

  const Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    this.otherAvatarUrl,
    this.lastMessage,
    required this.updatedAt,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastSeenAt,
    this.isPinned = false,
    this.isMuted = false,
    this.comboCount = 0,
    this.comboMax = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json, String myUserId) {
    final user1Id = json['user1_id'] as String;
    final user2Id = json['user2_id'] as String;
    final isUser1 = myUserId == user1Id;

    return Conversation(
      id: json['id'] as String,
      otherUserId: isUser1 ? user2Id : user1Id,
      otherUsername: (isUser1
              ? json['user2_username']
              : json['user1_username']) as String? ??
          'Utilisateur',
      otherAvatarUrl: (isUser1
          ? json['user2_avatar_url']
          : json['user1_avatar_url']) as String?,
      lastMessage: json['last_message'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      isOnline: (json['other_online'] as bool?) == true,
      lastSeenAt: json['other_last_seen'] != null
          ? DateTime.tryParse(json['other_last_seen'] as String)
          : null,
      isPinned: isUser1
          ? (json['is_pinned_user1'] as bool? ?? false)
          : (json['is_pinned_user2'] as bool? ?? false),
      isMuted: isUser1
          ? (json['is_muted_user1'] as bool? ?? false)
          : (json['is_muted_user2'] as bool? ?? false),
      comboCount: (json['combo_count'] as num?)?.toInt() ?? 0,
      comboMax: (json['combo_max'] as num?)?.toInt() ?? 0,
    );
  }

  Conversation copyWith({
    int? unreadCount,
    String? lastMessage,
    DateTime? updatedAt,
    bool? isOnline,
    bool? isPinned,
    bool? isMuted,
    int? comboCount,
    int? comboMax,
  }) {
    return Conversation(
      id: id,
      otherUserId: otherUserId,
      otherUsername: otherUsername,
      otherAvatarUrl: otherAvatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      comboCount: comboCount ?? this.comboCount,
      comboMax: comboMax ?? this.comboMax,
    );
  }
}

// ============================================================
// Statut / Story (duree 24h)
// ============================================================
class UserStatus {
  final String id;
  final String userId;
  final String username;
  final String? avatarUrl;
  final String mediaUrl;
  final String mediaType; // 'image' | 'text'
  final String? caption;
  final String? bgColor;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool viewedByMe;

  const UserStatus({
    required this.id,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.mediaUrl,
    this.mediaType = 'image',
    this.caption,
    this.bgColor,
    required this.createdAt,
    required this.expiresAt,
    this.viewedByMe = false,
  });

  factory UserStatus.fromJson(Map<String, dynamic> json) {
    return UserStatus(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String? ?? 'Utilisateur',
      avatarUrl: json['avatar_url'] as String?,
      mediaUrl: json['media_url'] as String,
      mediaType: json['media_type'] as String? ?? 'image',
      caption: json['caption'] as String?,
      bgColor: json['bg_color'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      viewedByMe: json['viewed_by_me'] as bool? ?? false,
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Groupe de statuts d'un utilisateur (pour l'affichage en liste)
class UserStatusGroup {
  final String userId;
  final String username;
  final String? avatarUrl;
  final List<UserStatus> statuses;

  const UserStatusGroup({
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.statuses,
  });

  bool get hasUnseen => statuses.any((s) => !s.viewedByMe);
  DateTime get latestAt => statuses
      .map((s) => s.createdAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

// ── Message privé ───────────────────────────────────────────
class PrivateMessage {
  final String id;
  final String conversationId;
  final String fromUserId;
  final String content;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? readAt;
  final MessageType messageType;
  final String? mediaUrl;
  final int? mediaDuration; // secondes (voice)
  final String? replyToId;
  final PrivateMessage? replyTo; // message cité (chargé séparément)
  final DateTime? deletedAt;
  final DateTime? editedAt;
  final List<MessageReaction> reactions;

  const PrivateMessage({
    required this.id,
    required this.conversationId,
    required this.fromUserId,
    required this.content,
    required this.createdAt,
    this.isRead = false,
    this.readAt,
    this.messageType = MessageType.text,
    this.mediaUrl,
    this.mediaDuration,
    this.replyToId,
    this.replyTo,
    this.deletedAt,
    this.editedAt,
    this.reactions = const [],
  });

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
  bool get isMedia => messageType == MessageType.image || messageType == MessageType.voice;

  factory PrivateMessage.fromJson(Map<String, dynamic> json) {
    return PrivateMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      fromUserId: json['from_user_id'] as String,
      content: json['content'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      messageType: messageTypeFromString(json['message_type'] as String?),
      mediaUrl: json['media_url'] as String?,
      mediaDuration: (json['media_duration'] as num?)?.toInt(),
      replyToId: json['reply_to_id'] as String?,
      deletedAt: json['deleted_at'] != null
          ? DateTime.tryParse(json['deleted_at'] as String)
          : null,
      editedAt: json['edited_at'] != null
          ? DateTime.tryParse(json['edited_at'] as String)
          : null,
    );
  }

  PrivateMessage copyWith({
    List<MessageReaction>? reactions,
    PrivateMessage? replyTo,
    DateTime? deletedAt,
  }) {
    return PrivateMessage(
      id: id,
      conversationId: conversationId,
      fromUserId: fromUserId,
      content: content,
      createdAt: createdAt,
      isRead: isRead,
      readAt: readAt,
      messageType: messageType,
      mediaUrl: mediaUrl,
      mediaDuration: mediaDuration,
      replyToId: replyToId,
      replyTo: replyTo ?? this.replyTo,
      deletedAt: deletedAt ?? this.deletedAt,
      editedAt: editedAt,
      reactions: reactions ?? this.reactions,
    );
  }
}

// ── Réaction à un message ───────────────────────────────────
class MessageReaction {
  final String id;
  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  const MessageReaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      id: json['id'] as String,
      messageId: json['message_id'] as String,
      userId: json['user_id'] as String,
      emoji: json['emoji'] as String? ?? '👍',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

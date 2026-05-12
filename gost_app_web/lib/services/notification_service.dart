// ============================================================
// Plugbet – Service de notifications locales (v20+)
// ============================================================

import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

const _log = Logger('NOTIF');

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );
      _initialized = true;
      _log.info('Service initialisé');
    } catch (e) {
      _log.info('Init échoué (rebuild nécessaire): $e');
    }
  }

  Future<bool> requestPermission() async {
    try {
      final status = await Permission.notification.request();
      _log.info('Permission: $status');
      return status.isGranted;
    } catch (e) {
      _log.info('Permission request échoué: $e');
      return false;
    }
  }

  Future<bool> isPermissionGranted() async {
    return await Permission.notification.isGranted;
  }

  Future<void> showMessageNotification({
    required String senderName,
    required String messagePreview,
    String? conversationId,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'chat_messages',
      'Messages',
      channelDescription: 'Notifications de nouveaux messages',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
      groupKey: 'com.plugbet.messages',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      id: conversationId.hashCode,
      title: senderName,
      body: messagePreview,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: conversationId,
    );
  }

  Future<void> showFriendRequestNotification({
    required String fromUsername,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'friend_requests',
      'Demandes d\'amitié',
      channelDescription: 'Notifications de demandes d\'amitié',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.show(
      id: fromUsername.hashCode,
      title: 'Nouvelle demande d\'ami',
      body: '$fromUsername veut être votre ami',
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }

  /// Notification generique (utilise par PushService pour les messages FCM en foreground)
  Future<void> showPushNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'push_messages',
      'Notifications push',
      channelDescription: 'Notifications recues via Firebase',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ============================================================
  // BROADCAST ANNOUNCEMENTS (admin → tous les joueurs)
  // ============================================================
  RealtimeChannel? _announcementChannel;
  final Set<String> _shownAnnouncements = {};

  /// A appeler une fois au boot (apres auth) depuis main.dart.
  /// Ecoute la table app_announcements et affiche une notif locale
  /// pour chaque nouvelle annonce active concernant l'utilisateur.
  Future<void> subscribeToAnnouncements() async {
    if (_announcementChannel != null) return; // deja abonne
    final client = Supabase.instance.client;

    // 1) Charger les annonces actives recentes au demarrage (catch-up)
    try {
      final data = await client
          .from('app_announcements')
          .select()
          .eq('active', true)
          .or('expires_at.is.null,expires_at.gt.${DateTime.now().toUtc().toIso8601String()}')
          .order('sent_at', ascending: false)
          .limit(5);
      for (final row in (data as List)) {
        await _maybeShowAnnouncement(Map<String, dynamic>.from(row));
      }
    } catch (e) {
      _log.warn('subscribeToAnnouncements catch-up failed: $e');
    }

    // 2) S'abonner aux nouvelles
    _announcementChannel = client
        .channel('app-announcements-rt')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'app_announcements',
          callback: (payload) async {
            await _maybeShowAnnouncement(payload.newRecord);
          },
        )
        .subscribe();
  }

  Future<void> _maybeShowAnnouncement(Map<String, dynamic> row) async {
    try {
      final id = row['id']?.toString();
      if (id == null || _shownAnnouncements.contains(id)) return;
      _shownAnnouncements.add(id);

      // Filtre : retracted / expirees
      if (row['active'] == false) return;
      final expiresAt = row['expires_at'];
      if (expiresAt is String && expiresAt.isNotEmpty) {
        final exp = DateTime.tryParse(expiresAt);
        if (exp != null && exp.isBefore(DateTime.now().toUtc())) return;
      }

      // Filtre cible (les autres roles seront filtres par RLS au SELECT)
      final target = row['target_role']?.toString() ?? 'all';
      if (target != 'all' && target != 'user') return;

      final title = row['title']?.toString() ?? 'Plugbet';
      final body = row['body']?.toString() ?? '';
      await showPushNotification(title: title, body: body, payload: 'announcement:$id');

      // Marquer comme lue cote serveur (best-effort)
      try {
        await Supabase.instance.client.rpc('mark_announcement_read', params: {'p_id': id});
      } catch (_) {}
    } catch (e) {
      _log.warn('show announcement failed: $e');
    }
  }

  Future<void> unsubscribeFromAnnouncements() async {
    if (_announcementChannel != null) {
      await Supabase.instance.client.removeChannel(_announcementChannel!);
      _announcementChannel = null;
    }
  }

  // ============================================================
  // CHAT MESSAGES (global - independant de l'ecran courant)
  // ============================================================
  // Notif locale a chaque nouveau message recu, peu importe ou est
  // l'utilisateur dans l'app. RLS filtre cote serveur les messages
  // qui ne concernent pas le user, donc on s'abonne sans filtre client.
  RealtimeChannel? _chatChannel;
  StreamSubscription<AuthState>? _authSub;
  String? _activeConversationId;
  final Map<String, String> _usernameCache = {};

  /// L'ecran de conversation appelle ceci quand il ouvre/ferme une conv
  /// pour eviter de notifier sur une conv deja affichee.
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
  }

  /// A appeler une fois au boot (apres signInAnonymously dans main).
  /// Etablit un canal realtime global pour les messages prives + re-etablit
  /// le canal a chaque changement d'auth (signIn / signOut).
  Future<void> subscribeToChatMessages() async {
    final client = Supabase.instance.client;

    _authSub ??= client.auth.onAuthStateChange.listen((data) async {
      // A chaque login/logout, on recree le canal pour que les events
      // soient filtres par la nouvelle session (RLS).
      await _resetChatChannel();
      if (client.auth.currentUser != null) {
        _setupChatChannel();
      }
    });

    if (client.auth.currentUser != null) {
      _setupChatChannel();
    }
  }

  void _setupChatChannel() {
    if (_chatChannel != null) return;
    final client = Supabase.instance.client;
    _chatChannel = client
        .channel('chat-notifs-global')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'private_messages',
          callback: (payload) async {
            await _maybeShowChatNotification(payload.newRecord);
          },
        )
        .subscribe();
  }

  Future<void> _maybeShowChatNotification(Map<String, dynamic> row) async {
    try {
      final client = Supabase.instance.client;
      final myId = client.auth.currentUser?.id;
      if (myId == null) return;

      final fromUserId = row['from_user_id']?.toString();
      final convId = row['conversation_id']?.toString();
      if (fromUserId == null || convId == null) return;

      // Skip mes propres messages
      if (fromUserId == myId) return;
      // Skip si la conversation est deja ouverte a l'ecran
      if (_activeConversationId == convId) return;

      // Recuperer le nom de l'expediteur (avec cache)
      var senderName = _usernameCache[fromUserId];
      if (senderName == null) {
        try {
          final profile = await client
              .from('user_profiles')
              .select('username')
              .eq('id', fromUserId)
              .maybeSingle();
          senderName =
              profile?['username']?.toString() ?? 'Nouveau message';
          _usernameCache[fromUserId] = senderName;
        } catch (_) {
          senderName = 'Nouveau message';
        }
      }

      // Preview du contenu
      String content = row['content']?.toString() ?? '';
      final messageType = row['message_type']?.toString() ?? 'text';
      if (messageType == 'image') content = '📷 Photo';
      if (messageType == 'voice') content = '🎤 Message vocal';
      if (content.isEmpty) content = 'Nouveau message';

      await showMessageNotification(
        senderName: senderName,
        messagePreview: content.length > 80
            ? '${content.substring(0, 80)}...'
            : content,
        conversationId: convId,
      );
    } catch (e) {
      _log.warn('chat notif failed: $e');
    }
  }

  Future<void> _resetChatChannel() async {
    if (_chatChannel != null) {
      await Supabase.instance.client.removeChannel(_chatChannel!);
      _chatChannel = null;
    }
  }

  Future<void> unsubscribeFromChatMessages() async {
    await _resetChatChannel();
    await _authSub?.cancel();
    _authSub = null;
  }
}

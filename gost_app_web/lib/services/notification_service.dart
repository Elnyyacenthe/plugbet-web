// ============================================================
// Plugbet – Service de notifications locales (v20+)
// ============================================================

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
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
}

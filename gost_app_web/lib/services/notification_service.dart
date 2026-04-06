// ============================================================
// Plugbet – Service de notifications locales (v20+)
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

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
      debugPrint('[NOTIF] Service initialisé');
    } catch (e) {
      debugPrint('[NOTIF] Init échoué (rebuild nécessaire): $e');
    }
  }

  Future<bool> requestPermission() async {
    try {
      final status = await Permission.notification.request();
      debugPrint('[NOTIF] Permission: $status');
      return status.isGranted;
    } catch (e) {
      debugPrint('[NOTIF] Permission request échoué: $e');
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

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}

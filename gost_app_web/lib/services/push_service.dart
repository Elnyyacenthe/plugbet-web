// ============================================================
// PushService — FCM (Firebase Cloud Messaging)
// Initialisation, recuperation du token, ecoute des messages
// ============================================================
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';
import 'notification_service.dart';

/// Handler de message en background (DOIT etre top-level + annote).
/// Appele quand l'app est tuee/en background et qu'un push arrive.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Pas de logging cote isolate background — juste recevoir le payload
}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _log = Logger('PUSH');
  final SupabaseClient _client = Supabase.instance.client;

  bool _initialized = false;

  /// Initialise FCM et enregistre le token de l'appareil.
  /// Appeler une fois au demarrage, apres la connexion Supabase.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // 1. Init Firebase
      await Firebase.initializeApp();

      // 2. Background handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 3. Demande de permission (iOS + Android 13+)
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _log.info('Permission: ${settings.authorizationStatus}');

      // 4. Recuperer le token et l'enregistrer cote backend
      final token = await messaging.getToken();
      if (token != null) {
        await registerToken(token);
      }

      // 5. Mise a jour du token si Firebase le regenere
      messaging.onTokenRefresh.listen(registerToken);

      // 6. Message recu en foreground (app ouverte) → relay vers notif locale
      FirebaseMessaging.onMessage.listen((msg) {
        _log.info('Foreground message: ${msg.notification?.title}');
        final notif = msg.notification;
        if (notif != null) {
          NotificationService.instance.showPushNotification(
            title: notif.title ?? 'Plugbet',
            body: notif.body ?? '',
            payload: msg.data['type'] as String?,
          );
        }
      });

      // 7. App ouverte depuis un push (utilisateur a tape sur la notif)
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        _log.info('Opened from push: ${msg.data}');
        // TODO: navigation vers l'ecran concerne selon msg.data['type']
      });
    } catch (e, s) {
      _log.error('init', e, s);
    }
  }

  /// Enregistre le token FCM dans Supabase (table `push_tokens`).
  Future<void> registerToken(String token) async {
    try {
      final platform = Platform.isAndroid ? 'android' : 'ios';
      await _client.rpc('register_push_token', params: {
        'p_token': token,
        'p_platform': platform,
      });
      _log.info('Token enregistre ($platform)');
    } catch (e, s) {
      _log.error('registerToken', e, s);
    }
  }

  /// Supprime le token de l'appareil (a appeler au logout).
  Future<void> unregister() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
      _log.info('Token supprime');
    } catch (e, s) {
      _log.error('unregister', e, s);
    }
  }
}

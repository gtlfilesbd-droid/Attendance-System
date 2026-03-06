import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Channel ID used by backend for duty reminder FCM messages. Must match tracking/tasks.py.
const String _dutyReminderChannelId = 'duty_reminder';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Notification is shown by the system when app is in background/terminated
}

/// Handles FCM token and registration with backend for duty reminder push notifications.
/// Call registerFCMToken() after login so the server can send 9:00 and 9:28 reminders.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static bool _initialized = false;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<String>? _onTokenRefreshSub;

  /// Initialize Firebase. Call from main() before runApp.
  static Future<void> initialize() async {
    if (_initialized) return;
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request notification permission (Android 13+) and create channel for FCM
    if (Platform.isAndroid) {
      await Permission.notification.request();
      const channel = AndroidNotificationChannel(
        _dutyReminderChannelId,
        'Duty Reminder',
        description: '9:00 and 9:28 AM duty start reminders',
        importance: Importance.high,
        playSound: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Init local notifications for foreground display
      const initSettings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
      await _localNotifications.initialize(initSettings);
    }

    // Show notification when app is in foreground (FCM does not auto-show)
    _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notif = message.notification;
      if (notif != null && Platform.isAndroid) {
        _localNotifications.show(
          message.hashCode,
          notif.title ?? 'Genesis',
          notif.body ?? '',
          const NotificationDetails(android: AndroidNotificationDetails(_dutyReminderChannelId, 'Duty Reminder')),
        );
      }
    });

    _initialized = true;

    // Listen for token refresh (e.g. app reinstall) and re-register
    _onTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _registerTokenWithBackend(newToken);
    });
  }

  /// Cancel FCM listeners. Call on logout so subscriptions are not leaked.
  static void cancelListeners() {
    _onMessageSub?.cancel();
    _onTokenRefreshSub?.cancel();
    _onMessageSub = null;
    _onTokenRefreshSub = null;
    _initialized = false;
  }

  /// Get FCM token and register with backend. Call after successful login.
  Future<void> registerFCMToken() async {
    final isLoggedIn = await AuthService().isLoggedIn();
    if (!isLoggedIn) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerTokenWithBackend(token);
      }
    } catch (e) {
      print('PushNotificationService: getToken failed: $e');
    }
  }

  static Future<void> _registerTokenWithBackend(String fcmToken) async {
    final isLoggedIn = await AuthService().isLoggedIn();
    if (!isLoggedIn) return;

    try {
      ApiService().initialize();
      await ApiService().client.post(
        AppConfig.registerDeviceEndpoint,
        data: {
          'fcm_token': fcmToken,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        },
      );
    } catch (e) {
      print('PushNotificationService: register device failed: $e');
    }
  }
}

import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_navigator.dart';
import '../models/todo_task.dart';
import '../screens/login_screen.dart';
import '../screens/todo_detail_screen.dart';
import '../screens/todo_list_screen.dart';
import '../utils/android_sdk.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Channel ID used by backend for duty reminder FCM messages. Must match tracking/tasks.py.
const String _dutyReminderChannelId = 'duty_reminder';

/// Channel ID used by backend for todo assignment pushes. Must match todos/notifications.py.
const String _todoAssignedChannelId = 'todo_assigned';

const String _dataTypeTodoAssigned = 'todo_assigned';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Notification is shown by the system when app is in background/terminated
}

/// Handles FCM token registration and notification tap → deep navigation.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static bool _initialized = false;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onOpenedSub;
  static StreamSubscription<String>? _onTokenRefreshSub;

  static String? _pendingTaskId;
  static bool _openingTodo = false;
  static String? _lastOpenedTaskId;
  static DateTime? _lastOpenedAt;

  /// Initialize Firebase. Call from main() before runApp.
  static Future<void> initialize() async {
    if (_initialized) return;
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    if (Platform.isAndroid) {
      if (await AndroidSdk.isAtLeast33) {
        await Permission.notification.request();
      }
      const dutyChannel = AndroidNotificationChannel(
        _dutyReminderChannelId,
        'Duty Reminder',
        description: '9:00 and 9:28 AM duty start reminders',
        importance: Importance.high,
        playSound: true,
      );
      const todoChannel = AndroidNotificationChannel(
        _todoAssignedChannelId,
        'Task Assigned',
        description: 'Notifications when a TO-DO task is assigned to you',
        importance: Importance.high,
        playSound: true,
      );
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(dutyChannel);
      await androidPlugin?.createNotificationChannel(todoChannel);

      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onLocalNotificationTap,
      );
    }

    _attachListeners();

    // Cold start: store pending deep link; HomeScreen flushes after login splash.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final initialTaskId = _taskIdFromMessage(initial);
    if (initialTaskId != null) {
      _pendingTaskId = initialTaskId;
    }

    _initialized = true;
  }

  static void _attachListeners() {
    _onMessageSub ??= FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _onOpenedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
    _onTokenRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _registerTokenWithBackend(newToken);
    });
  }

  static void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      unawaited(openTodoFromNotification(payload));
    }
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null || !Platform.isAndroid) return;

    final taskId = _taskIdFromMessage(message);
    final isTodo = taskId != null;
    final channelId = isTodo ? _todoAssignedChannelId : _dutyReminderChannelId;
    final channelName = isTodo ? 'Task Assigned' : 'Duty Reminder';

    await _localNotifications.show(
      message.hashCode,
      notif.title ?? 'Genesis',
      notif.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(channelId, channelName),
      ),
      payload: taskId,
    );
  }

  static void _onMessageOpened(RemoteMessage message) {
    final taskId = _taskIdFromMessage(message);
    if (taskId != null) {
      unawaited(openTodoFromNotification(taskId));
    }
  }

  static String? _taskIdFromMessage(RemoteMessage? message) {
    if (message == null) return null;
    final data = message.data;
    if (data['type'] != _dataTypeTodoAssigned) return null;
    final taskId = data['task_id']?.toString().trim();
    if (taskId == null || taskId.isEmpty) return null;
    return taskId;
  }

  /// Call from HomeScreen after login so cold-start taps open the task.
  static Future<void> flushPendingDeepLink() async {
    final taskId = _pendingTaskId;
    if (taskId == null || taskId.isEmpty) return;
    _pendingTaskId = null;
    await openTodoFromNotification(taskId);
  }

  /// Navigate to task detail for [taskId]. Safe if logged out / fetch fails.
  static Future<void> openTodoFromNotification(String taskId) async {
    final id = taskId.trim();
    if (id.isEmpty) return;

    final now = DateTime.now();
    if (_lastOpenedTaskId == id &&
        _lastOpenedAt != null &&
        now.difference(_lastOpenedAt!) < const Duration(seconds: 3)) {
      return;
    }
    if (_openingTodo) {
      _pendingTaskId = id;
      return;
    }

    _openingTodo = true;
    _lastOpenedTaskId = id;
    _lastOpenedAt = now;

    try {
      final isLoggedIn = await AuthService().isLoggedIn();
      if (!isLoggedIn) {
        _pendingTaskId = id;
        final nav = rootNavigatorKey?.currentState;
        nav?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        return;
      }

      final navigator = await _waitForNavigator();
      if (navigator == null) {
        _pendingTaskId = id;
        return;
      }

      ApiService().initialize();
      final data = await ApiService().getTodo(id);
      if (data == null) {
        navigator.push(
          MaterialPageRoute(builder: (_) => const TodoListScreen()),
        );
        return;
      }

      final task = TodoTask.fromJson(data);
      navigator.push(
        MaterialPageRoute(builder: (_) => TodoDetailScreen(task: task)),
      );
    } catch (e) {
      print('PushNotificationService: openTodoFromNotification failed: $e');
      _pendingTaskId = id;
    } finally {
      _openingTodo = false;
      final pending = _pendingTaskId;
      if (pending != null && pending != id) {
        _pendingTaskId = null;
        unawaited(openTodoFromNotification(pending));
      }
    }
  }

  static Future<NavigatorState?> _waitForNavigator({
    int attempts = 20,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    for (var i = 0; i < attempts; i++) {
      final nav = rootNavigatorKey?.currentState;
      if (nav != null && nav.mounted) return nav;
      await Future.delayed(delay);
    }
    return rootNavigatorKey?.currentState;
  }

  /// Cancel FCM listeners. Call on logout so subscriptions are not leaked.
  static void cancelListeners() {
    _onMessageSub?.cancel();
    _onOpenedSub?.cancel();
    _onTokenRefreshSub?.cancel();
    _onMessageSub = null;
    _onOpenedSub = null;
    _onTokenRefreshSub = null;
    _pendingTaskId = null;
    // Keep _initialized true so channels stay created; re-attach on next register.
  }

  /// Get FCM token and register with backend. Call after successful login.
  Future<void> registerFCMToken() async {
    final isLoggedIn = await AuthService().isLoggedIn();
    if (!isLoggedIn) return;

    if (!_initialized) {
      try {
        await initialize();
      } catch (e) {
        print('PushNotificationService: initialize failed: $e');
        return;
      }
    } else {
      _attachListeners();
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerTokenWithBackend(token);
      }
    } catch (e) {
      print('PushNotificationService: getToken failed: $e');
    }

    unawaited(flushPendingDeepLink());
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

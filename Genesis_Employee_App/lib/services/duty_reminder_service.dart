import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;

/// Duty reminders are now sent via FCM from the backend (9:00 and 9:28 Asia/Dhaka, Mon-Thu and Sat-Sun).
/// This service keeps cancelAll() for logout (clears any legacy local schedules) and leaves
/// scheduleDutyReminders() unused in production.
class DutyReminderService {
  static final DutyReminderService _instance = DutyReminderService._internal();
  factory DutyReminderService() => _instance;
  DutyReminderService._internal();

  static const int _idBase = 901;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@drawable/ic_bg_service_small');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  /// Cancels any previously scheduled local duty reminders (e.g. from before FCM).
  Future<void> cancelAll() async {
    await ensureInitialized();
    for (int i = 0; i < 12; i++) {
      await _plugin.cancel(_idBase + i);
    }
  }
}

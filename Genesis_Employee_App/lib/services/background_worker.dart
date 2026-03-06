import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import '../config/app_config.dart';
import 'location_service.dart';
import 'api_service.dart';

// Top-level function for WorkManager.
// WorkManager is only allowed to stop or clean up; it must NEVER start the tracking service.
// Tracking lifecycle is fully controlled by Start Duty / End Duty (user action only).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("WORKMANAGER: Task $task started");

    if (task == 'check_tracking_schedule') {
      // Only stop the service when outside working hours (for when real hours are enabled).
      // Never start the service here.
      if (!LocationService.isWorkingHoursStatic()) {
        final service = FlutterBackgroundService();
        if (await service.isRunning()) {
          print("WORKMANAGER: Stopping background service (outside hours)");
          service.invoke("stopService");
        }
      }
    }
    return Future.value(true);
  });
}

@pragma('vm:entry-point')
class BackgroundWorker {
  static final BackgroundWorker _instance = BackgroundWorker._internal();
  
  factory BackgroundWorker() {
    return _instance;
  }
  
  BackgroundWorker._internal();

  static const String notificationChannelId = 'genesis_tracking_channel';
  static const int notificationId = 888;

  Future<void> initialize() async {
    print("BackgroundWorker: Initializing...");

    // Initialize WorkManager
    await Workmanager().initialize(callbackDispatcher);

    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Genesis Tracking Service',
      description: 'Background location tracking for attendance',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Genesis Tracking',
        initialNotificationContent: 'Initializing location service...',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    
    print("BackgroundWorker: Initialized");
  }

  Future<void> startService() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  Future<void> stopService() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke("stopService");
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // Re-initialize API Service in background isolate
    ApiService().initialize();

    final Battery battery = Battery();
    final DateTime serviceStartDate = DateTime.now();
    int sessionCheckTickCount = 0;
    const int checkIntervalSeconds = 15;
    // Derive session-check tick count from AppConfig so it is tunable in one place.
    const int sessionCheckIntervalTicks =
        (AppConfig.sessionCheckIntervalMinutes * 60) ~/ checkIntervalSeconds;

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    // Cached position from stream; used for adaptive send
    Position? cachedPosition;
    StreamSubscription<Position>? positionSubscription;
    Timer? sendTimer;
    // Track last sent position for displacement-based and adaptive-interval sending
    double? lastSentLat;
    double? lastSentLng;
    DateTime? lastSentTime;
    // Phase 1: Watchdog – if no location sent for 15 min, stop service (app will restart on resume). Heartbeat removed to reduce battery drain.
    const int watchdogInactiveMinutes = 15;

    // Adaptive distanceFilter state
    bool isStationaryMode = false;
    DateTime lastPositionTime = DateTime.now();

    // Restarts the GPS stream with the given distanceFilter.
    // Called on service start and whenever stationary/moving mode switches.
    void restartPositionStream(int filterMeters) {
      positionSubscription?.cancel();
      positionSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: filterMeters,
        ),
      ).listen((Position position) {
        cachedPosition = position;
        lastPositionTime = DateTime.now();
      }, onError: (e) {
        print('BackgroundWorker: Position stream error $e');
      });
    }

    service.on('stopService').listen((event) {
      positionSubscription?.cancel();
      sendTimer?.cancel();
      service.stopSelf();
    });

    // Battery level cache: re-read at most every 3 minutes to avoid IPC on every tick.
    int cachedBatLevel = 100;
    DateTime? lastBatReadTime;

    // Start position stream in moving mode.
    restartPositionStream(AppConfig.distanceFilterMovingMeters);

    // Adaptive send: check every 15s; send if displacement >= 30m OR time since last >= interval (15s when moving, 60s when still)
    sendTimer = Timer.periodic(
      const Duration(seconds: checkIntervalSeconds),
      (timer) async {
        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            service.setForegroundNotificationInfo(
              title: "Genesis Tracking",
              content:
                  "Attendance tracking active. Last update: ${DateTime.now().hour}:${DateTime.now().minute}",
            );
          }
        }

        try {
          final now = DateTime.now();
          if (now.day != serviceStartDate.day ||
              now.month != serviceStartDate.month ||
              now.year != serviceStartDate.year) {
            print('BackgroundWorker: Date changed – auto-stopping service');
            service.invoke('stopService');
            return;
          }
          if (now.difference(serviceStartDate).inHours >=
              AppConfig.maxDutyDurationHours) {
            print(
                'BackgroundWorker: Max duty duration (${AppConfig.maxDutyDurationHours}h) reached – auto-stopping');
            service.invoke('stopService');
            return;
          }
          // Adaptive distanceFilter: switch GPS stream mode based on movement.
          final int minutesSinceLastPosition =
              now.difference(lastPositionTime).inMinutes;
          if (!isStationaryMode &&
              minutesSinceLastPosition >=
                  AppConfig.stationaryThresholdMinutes) {
            isStationaryMode = true;
            restartPositionStream(AppConfig.distanceFilterStationaryMeters);
            print(
                'BackgroundWorker: Stationary detected – GPS distanceFilter → ${AppConfig.distanceFilterStationaryMeters}m');
          } else if (isStationaryMode &&
              minutesSinceLastPosition <
                  AppConfig.stationaryThresholdMinutes) {
            isStationaryMode = false;
            restartPositionStream(AppConfig.distanceFilterMovingMeters);
            print(
                'BackgroundWorker: Movement detected – GPS distanceFilter → ${AppConfig.distanceFilterMovingMeters}m');
          }

          sessionCheckTickCount++;
          if (sessionCheckTickCount >= sessionCheckIntervalTicks) {
            sessionCheckTickCount = 0;
            final bool? hasActive = await ApiService().hasActiveDutySession();
            if (hasActive == false) {
              print('BackgroundWorker: No active duty session on server – auto-stopping service');
              service.invoke('stopService');
              return;
            }
          }
          Position? position = cachedPosition;
          position ??= await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          // ignore: unnecessary_null_comparison - position can be null if getCurrentPosition failed
          if (position == null) return;
          final bool neverSent = lastSentLat == null || lastSentLng == null || lastSentTime == null;
          double displacementMeters = double.infinity;
          if (!neverSent && lastSentLat != null && lastSentLng != null) {
            final meters = Geolocator.distanceBetween(
              lastSentLat!,
              lastSentLng!,
              position.latitude,
              position.longitude,
            );
            displacementMeters = meters.toDouble();
          }

          // Phase 5: Battery-aware interval – use longer intervals when battery is low.
          // Re-read battery at most every 3 minutes to avoid repeated IPC calls.
          if (lastBatReadTime == null ||
              now.difference(lastBatReadTime!).inSeconds >= 180) {
            cachedBatLevel = await battery.batteryLevel;
            lastBatReadTime = now;
          }
          final int batLevel = cachedBatLevel;
          final bool powerSave = batLevel <= AppConfig.batteryLowThresholdPercent;
          final int intervalWhenDuty = powerSave
              ? AppConfig.locationUpdateIntervalSecondsWhenDutyPowerSave
              : AppConfig.locationUpdateIntervalSecondsWhenDuty;
          final int intervalWhenMoving = powerSave
              ? AppConfig.locationUpdateIntervalSecondsWhenMovingPowerSave
              : AppConfig.locationUpdateIntervalSecondsWhenMoving;
          final double speedMps = position.speed >= 0 ? position.speed : 0.0;
          final int intervalSeconds = speedMps >= AppConfig.speedThresholdMovingMps
              ? intervalWhenMoving
              : intervalWhenDuty;
          final int elapsed = lastSentTime != null
              ? now.difference(lastSentTime!).inSeconds
              : intervalSeconds + 1;

          final bool shouldSend = neverSent ||
              displacementMeters >= AppConfig.minDisplacementToSendMeters ||
              elapsed >= intervalSeconds;

          if (shouldSend) {
            await LocationService.sendLocationToBackend(position, battery);
            await LocationService.syncOfflineData();
            lastSentLat = position.latitude;
            lastSentLng = position.longitude;
            lastSentTime = now;
          }

          // Phase 1 watchdog: if no location sent for 15 min, stop service (app will restart on resume)
          final lastActivity = lastSentTime;
          if (lastActivity != null &&
              now.difference(lastActivity).inMinutes >= watchdogInactiveMinutes) {
            print('BackgroundWorker: No activity for $watchdogInactiveMinutes min – stopping service (watchdog)');
            service.invoke('stopService');
            return;
          }
        } catch (e) {
          print('BackgroundWorker: Error getting location $e');
        }
      },
    );

    // Initial send: stream may take a moment; use getCurrentPosition for immediate first point
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      cachedPosition = position;
      await LocationService.sendLocationToBackend(position, battery);
      lastSentLat = position.latitude;
      lastSentLng = position.longitude;
      lastSentTime = DateTime.now();
    } catch (e) {
      print("BackgroundWorker: Initial location error $e");
    }
  }
}

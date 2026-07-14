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

  /// Prevents double configure() in the same UI process (splash + home).
  static bool _configuredInThisProcess = false;

  static void _log(String event, [String? detail]) {
    final suffix = detail == null || detail.isEmpty ? '' : ' | $detail';
    print('BG_SAFEFIX: $event$suffix');
  }

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

    final bool alreadyRunning = await service.isRunning();
    if (alreadyRunning) {
      _log('configure_skipped_running');
      print(
          'BackgroundWorker: service already running – skipping configure');
      print("BackgroundWorker: Initialized");
      return;
    }

    if (_configuredInThisProcess) {
      _log('configure_skipped_latch');
      print(
          'BackgroundWorker: already configured in this process – skipping configure');
      print("BackgroundWorker: Initialized");
      return;
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
    _configuredInThisProcess = true;
    _log('configure_ok');

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
    // Phase 1: Watchdog – if no location sent for 15 min, stop service (app will restart on resume).
    const int watchdogInactiveMinutes = 15;

    // Adaptive distanceFilter state
    bool isStationaryMode = false;
    DateTime lastPositionTime = DateTime.now();
    DateTime? lastStreamRestartAt;
    bool streamHealthy = true;
    DateTime? streamCooldownUntil;
    int consecutiveFallbackFailures = 0;
    bool streamRestartInFlight = false;

    Future<bool> restartPositionStream(int filterMeters,
        {bool force = false}) async {
      if (streamRestartInFlight) {
        _log('stream_restart_skipped_inflight');
        return false;
      }
      final now = DateTime.now();
      if (!force &&
          lastStreamRestartAt != null &&
          now.difference(lastStreamRestartAt!).inSeconds <
              AppConfig.bgStreamRestartDebounceSeconds) {
        _log(
          'stream_restart_debounced',
          'wantedFilter=${filterMeters}m',
        );
        return false;
      }

      streamRestartInFlight = true;
      try {
        await positionSubscription?.cancel();
        positionSubscription = null;
        // Brief gap so native NMEA/fused listeners can finish teardown.
        await Future<void>.delayed(const Duration(milliseconds: 200));

        positionSubscription = Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: filterMeters,
          ),
        ).listen((Position position) {
          cachedPosition = position;
          lastPositionTime = DateTime.now();
          if (!streamHealthy) {
            streamHealthy = true;
            streamCooldownUntil = null;
            consecutiveFallbackFailures = 0;
            _log('stream_recovered');
          }
        }, onError: (Object e, StackTrace st) async {
          _log('stream_error_count', e.toString());
          print('BackgroundWorker: Position stream error $e');
          streamHealthy = false;
          streamCooldownUntil = DateTime.now().add(
            const Duration(seconds: AppConfig.bgStreamErrorCooldownSeconds),
          );
          _log(
            'stream_cooldown_entered',
            '${AppConfig.bgStreamErrorCooldownSeconds}s',
          );
          try {
            await positionSubscription?.cancel();
          } catch (_) {}
          positionSubscription = null;
          // Do not recreate immediately — send loop falls back to getCurrentPosition.
        }, cancelOnError: false);

        lastStreamRestartAt = DateTime.now();
        streamHealthy = true;
        _log('stream_restart_ok', 'filter=${filterMeters}m');
        return true;
      } catch (e) {
        streamHealthy = false;
        streamCooldownUntil = DateTime.now().add(
          const Duration(seconds: AppConfig.bgStreamErrorCooldownSeconds),
        );
        _log('stream_restart_failed', e.toString());
        print('BackgroundWorker: Position stream restart failed $e');
        return false;
      } finally {
        streamRestartInFlight = false;
      }
    }

    service.on('stopService').listen((event) async {
      try {
        await positionSubscription?.cancel();
      } catch (_) {}
      positionSubscription = null;
      sendTimer?.cancel();
      service.stopSelf();
    });

    // Battery level cache: re-read at most every 3 minutes to avoid IPC on every tick.
    int cachedBatLevel = 100;
    DateTime? lastBatReadTime;

    // Start position stream in moving mode (force=true so first start ignores debounce).
    await restartPositionStream(AppConfig.distanceFilterMovingMeters,
        force: true);

    // Adaptive send: check every 15s; send if displacement >= 30m OR time since last >= interval
    sendTimer = Timer.periodic(
      const Duration(seconds: checkIntervalSeconds),
      (timer) async {
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

          // Recover stream after cooldown if it had failed.
          if (!streamHealthy &&
              streamCooldownUntil != null &&
              !now.isBefore(streamCooldownUntil!)) {
            _log('stream_cooldown_retry');
            await restartPositionStream(
              isStationaryMode
                  ? AppConfig.distanceFilterStationaryMeters
                  : AppConfig.distanceFilterMovingMeters,
              force: true,
            );
          }

          // Adaptive distanceFilter: switch GPS stream mode based on movement.
          final int minutesSinceLastPosition =
              now.difference(lastPositionTime).inMinutes;
          if (streamHealthy) {
            if (!isStationaryMode &&
                minutesSinceLastPosition >=
                    AppConfig.stationaryThresholdMinutes) {
              final switched = await restartPositionStream(
                  AppConfig.distanceFilterStationaryMeters);
              if (switched) {
                isStationaryMode = true;
                print(
                    'BackgroundWorker: Stationary detected – GPS distanceFilter → ${AppConfig.distanceFilterStationaryMeters}m');
              }
            } else if (isStationaryMode &&
                minutesSinceLastPosition <
                    AppConfig.stationaryThresholdMinutes) {
              // Hysteresis: leave stationary only when fresh stream positions arrived.
              final switched = await restartPositionStream(
                  AppConfig.distanceFilterMovingMeters);
              if (switched) {
                isStationaryMode = false;
                print(
                    'BackgroundWorker: Movement detected – GPS distanceFilter → ${AppConfig.distanceFilterMovingMeters}m');
              }
            }
          }

          sessionCheckTickCount++;
          if (sessionCheckTickCount >= sessionCheckIntervalTicks) {
            sessionCheckTickCount = 0;
            final bool? hasActive = await ApiService().hasActiveDutySession();
            if (hasActive == false) {
              print(
                  'BackgroundWorker: No active duty session on server – auto-stopping service');
              service.invoke('stopService');
              return;
            }
          }

          late final Position position;
          if (streamHealthy && cachedPosition != null) {
            position = cachedPosition!;
          } else {
            try {
              position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              );
              consecutiveFallbackFailures = 0;
              if (!streamHealthy) {
                _log('fallback_poll_success');
              }
            } catch (e) {
              consecutiveFallbackFailures++;
              _log(
                'fallback_poll_fail',
                '$consecutiveFallbackFailures/${AppConfig.bgFallbackPollFailLimit} $e',
              );
              if (consecutiveFallbackFailures >=
                  AppConfig.bgFallbackPollFailLimit) {
                _log('service_watchdog_stop', 'fallback_poll_fail_limit');
                print(
                    'BackgroundWorker: Too many fallback GPS failures – stopping service');
                service.invoke('stopService');
              }
              return;
            }
          }

          final bool neverSent =
              lastSentLat == null || lastSentLng == null || lastSentTime == null;
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
          if (lastBatReadTime == null ||
              now.difference(lastBatReadTime!).inSeconds >= 180) {
            cachedBatLevel = await battery.batteryLevel;
            lastBatReadTime = now;
          }
          final int batLevel = cachedBatLevel;
          final bool powerSave =
              batLevel <= AppConfig.batteryLowThresholdPercent;
          final int intervalWhenDuty = powerSave
              ? AppConfig.locationUpdateIntervalSecondsWhenDutyPowerSave
              : AppConfig.locationUpdateIntervalSecondsWhenDuty;
          final int intervalWhenMoving = powerSave
              ? AppConfig.locationUpdateIntervalSecondsWhenMovingPowerSave
              : AppConfig.locationUpdateIntervalSecondsWhenMoving;
          final double speedMps = position.speed >= 0 ? position.speed : 0.0;
          final int intervalSeconds =
              speedMps >= AppConfig.speedThresholdMovingMps
                  ? intervalWhenMoving
                  : intervalWhenDuty;
          final int elapsed = lastSentTime != null
              ? now.difference(lastSentTime!).inSeconds
              : intervalSeconds + 1;

          final bool shouldSend = neverSent ||
              displacementMeters >= AppConfig.minDisplacementToSendMeters ||
              elapsed >= intervalSeconds;

          if (shouldSend) {
            final bool actualSent =
                await LocationService.sendLocationToBackend(position, battery);
            await LocationService.syncOfflineData();
            lastSentLat = position.latitude;
            lastSentLng = position.longitude;
            lastSentTime = now;
            if (actualSent &&
                service is AndroidServiceInstance &&
                await service.isForegroundService()) {
              service.setForegroundNotificationInfo(
                title: 'Genesis Tracking',
                content:
                    'Attendance tracking active. Last update: ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
              );
            }
          }

          final lastActivity = lastSentTime;
          if (lastActivity != null &&
              now.difference(lastActivity).inMinutes >=
                  watchdogInactiveMinutes) {
            _log('service_watchdog_stop', 'inactive_${watchdogInactiveMinutes}m');
            print(
                'BackgroundWorker: No activity for $watchdogInactiveMinutes min – stopping service (watchdog)');
            service.invoke('stopService');
            return;
          }
        } catch (e) {
          print('BackgroundWorker: Error getting location $e');
          _log('send_loop_error', e.toString());
        }
      },
    );

    // Initial send: stream may take a moment; use getCurrentPosition for immediate first point
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      cachedPosition = position;
      final bool initialSent =
          await LocationService.sendLocationToBackend(position, battery);
      lastSentLat = position.latitude;
      lastSentLng = position.longitude;
      lastSentTime = DateTime.now();
      if (initialSent &&
          service is AndroidServiceInstance &&
          await service.isForegroundService()) {
        final t = lastSentTime!;
        service.setForegroundNotificationInfo(
          title: 'Genesis Tracking',
          content:
              'Attendance tracking active. Last update: ${t.hour}:${t.minute.toString().padLeft(2, '0')}',
        );
      }
    } catch (e) {
      print("BackgroundWorker: Initial location error $e");
      _log('initial_position_error', e.toString());
    }
  }
}

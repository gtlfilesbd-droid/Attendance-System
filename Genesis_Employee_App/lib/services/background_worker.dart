import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'location_service.dart';
import 'api_service.dart';

// Top-level function for WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("WORKMANAGER: Task $task started");
    
    if (task == 'check_tracking_schedule') {
      if (LocationService.isWorkingHoursStatic()) {
        final service = FlutterBackgroundService();
        if (!await service.isRunning()) {
           print("WORKMANAGER: Starting background service");
           await service.startService();
        }
      } else {
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
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true 
    );

    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Genesis Tracking Service',
      description: 'Background location tracking for attendance',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    if (await service.isAndroid) {
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
    
    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Tracking Loop (Every 5 minutes)
    Timer.periodic(const Duration(minutes: 5), (timer) async {
      final isWorkingHours = LocationService.isWorkingHoursStatic();

      if (!isWorkingHours) {
        if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Genesis Tracking",
              content: "Paused (Outside working hours)",
            );
        }
        return; 
      }

      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: "Genesis Tracking",
            content: "Attendance tracking active. Last update: ${DateTime.now().hour}:${DateTime.now().minute}",
          );
        }
      }

      try {
        final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        
        await LocationService.sendLocationToBackend(position, battery);
        await LocationService.syncOfflineData();

      } catch (e) {
        print('BackgroundWorker: Error getting location $e');
      }
    });
    
    // Initial check
    try {
        final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        await LocationService.sendLocationToBackend(position, battery);
    } catch (e) {
        print("BackgroundWorker: Initial location error $e");
    }
  }
}

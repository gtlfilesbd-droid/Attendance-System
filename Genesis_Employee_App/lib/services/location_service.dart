import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';
import '../utils/working_hours.dart' as wh;
import 'auth_service.dart';
import 'api_service.dart';
import 'background_worker.dart';

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  
  factory LocationService() {
    return _instance;
  }
  
  LocationService._internal();

  /// Initialize: Request permissions and setup background worker
  Future<void> initializeService() async {
    print("LocationService: Initializing...");
    
    // 1. Request Permissions
    await _requestPermissions();

    // 2. Initialize Background Worker
    await BackgroundWorker().initialize();
    
    print("LocationService: Initialized");
  }
  
  Future<void> _requestPermissions() async {
    // Request location permissions
    var status = await Permission.location.status;
    if (!status.isGranted) {
      status = await Permission.location.request();
    }
    
    // Request background location (Android 10+)
    if (status.isGranted) {
      var bgStatus = await Permission.locationAlways.status;
      if (!bgStatus.isGranted) {
        await Permission.locationAlways.request();
      }
    }

    // Request notification permission (Android 13+)
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    
    // Request battery optimization ignore
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// Time limit disabled: always allows tracking when duty is active (Instance method)
  bool isWorkingHours() {
    return isWorkingHoursStatic();
  }

  /// Time limit disabled: always allows tracking when duty is active (Static method).
  /// [now] is optional for testing; defaults to DateTime.now().
  static bool isWorkingHoursStatic([DateTime? now]) => wh.isWorkingHours(now);

  /// Schedule periodic checks using WorkManager
  void scheduleTracking() {
    Workmanager().registerPeriodicTask(
      "periodic_tracking_check",
      "check_tracking_schedule",
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
    print("LocationService: Scheduled periodic tracking check");
  }

  /// Start Tracking Manually (Start duty) - runs until user presses End duty
  Future<void> startTracking() async {
    await BackgroundWorker().startService();
  }

  /// Stop Tracking
  Future<void> stopTracking() async {
    await BackgroundWorker().stopService();
  }

  static Future<void> sendLocationToBackend(
    Position position,
    Battery battery,
  ) async {
    try {
      final batteryLevel = await battery.batteryLevel;
      final timestamp = DateTime.now().toIso8601String();

      // Detailed logging: auth and config
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) {
        print('FLUTTER_BG_SERVICE: ERROR No auth token found - cannot send location');
        await _saveOffline({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': timestamp,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'battery_level': batteryLevel,
        });
        return;
      }
      print('FLUTTER_BG_SERVICE: Token present (length=${token.length})');

      print(
        'FLUTTER_BG_SERVICE: Sending location lat=${position.latitude}, lng=${position.longitude}, '
        'accuracy=${position.accuracy}, battery=$batteryLevel, timestamp=$timestamp',
      );

      final success = await ApiService().logLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        batteryLevel: batteryLevel,
        speed: position.speed,
      );

      if (success) {
        print('FLUTTER_BG_SERVICE: Location sent successfully to API');
      } else {
        print('FLUTTER_BG_SERVICE: API returned failure (no 200/201). Saving offline.');
        await _saveOffline({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': timestamp,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'battery_level': batteryLevel,
        });
      }
    } catch (e, stackTrace) {
      print('FLUTTER_BG_SERVICE: ERROR sending location: $e');
      print('FLUTTER_BG_SERVICE: Stack trace: $stackTrace');
      await _saveOffline({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'accuracy': position.accuracy,
        'speed': position.speed,
        'battery_level': await battery.batteryLevel,
      });
    }
  }

  static Future<void> _saveOffline(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> offlineData = prefs.getStringList('offline_locations') ?? [];
      
      offlineData.add(jsonEncode(data));
      
      // Limit storage to prevent explosion (e.g. keep last 1000 points)
      if (offlineData.length > 1000) {
        offlineData.removeAt(0);
      }
      
      await prefs.setStringList('offline_locations', offlineData);
      print("FLUTTER_BG_SERVICE: Saved to offline storage. Count: ${offlineData.length}");
    } catch (e) {
      print("FLUTTER_BG_SERVICE: Error saving offline $e");
    }
  }

  static Future<void> syncOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> offlineData = prefs.getStringList('offline_locations') ?? [];
      
      if (offlineData.isEmpty) return;
      
      print("FLUTTER_BG_SERVICE: Syncing ${offlineData.length} offline records...");
      
      final List<String> remainingData = [];
      
      for (String jsonStr in offlineData) {
        try {
          final data = jsonDecode(jsonStr);
          final success = await ApiService().logLocation(
             latitude: data['latitude'], 
             longitude: data['longitude'], 
             accuracy: data['accuracy'], 
             batteryLevel: data['battery_level'],
             speed: data['speed']
          );
          
          if (!success) {
             remainingData.add(jsonStr);
          }
        } catch (e) {
          // Failed again, keep it
          remainingData.add(jsonStr);
        }
      }
      
      if (remainingData.length != offlineData.length) {
         await prefs.setStringList('offline_locations', remainingData);
         print("FLUTTER_BG_SERVICE: Sync complete. Remaining: ${remainingData.length}");
      }
      
    } catch (e) {
      print("FLUTTER_BG_SERVICE: Error syncing $e");
    }
  }
}

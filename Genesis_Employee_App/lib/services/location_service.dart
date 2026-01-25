import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';
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

  /// Check if current time is within 9:30 AM - 6:30 PM (Instance method)
  bool isWorkingHours() {
    return isWorkingHoursStatic();
  }

  /// Check if current time is within 9:30 AM - 6:30 PM (Static method)
  static bool isWorkingHoursStatic() {
    final now = DateTime.now();
    final startWork = DateTime(now.year, now.month, now.day, 9, 30);
    final endWork = DateTime(now.year, now.month, now.day, 18, 30);

    return now.isAfter(startWork) && now.isBefore(endWork);
  }

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

  /// Start Tracking Manually
  Future<void> startTracking() async {
    if (!isWorkingHours()) {
      print("LocationService: Starting tracking (User initiated outside hours)");
    }
    await BackgroundWorker().startService();
  }

  /// Stop Tracking
  Future<void> stopTracking() async {
    await BackgroundWorker().stopService();
  }

  static Future<void> sendLocationToBackend(
    Position position, 
    Battery battery
  ) async {
    try {
      // Get battery level
      int batteryLevel = await battery.batteryLevel;
      
      print('FLUTTER_BG_SERVICE: Sending Location ${position.latitude}, ${position.longitude}');

      // Use ApiService to send data
      final success = await ApiService().logLocation(
        latitude: position.latitude, 
        longitude: position.longitude, 
        accuracy: position.accuracy, 
        batteryLevel: batteryLevel,
        speed: position.speed
      );
      
      if (success) {
        print('FLUTTER_BG_SERVICE: Sent to API');
      } else {
        print('FLUTTER_BG_SERVICE: API failed. Saving offline.');
        await _saveOffline({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': DateTime.now().toIso8601String(),
          'accuracy': position.accuracy,
          'speed': position.speed,
          'battery_level': batteryLevel,
        });
      }
    } catch (e) {
      print('FLUTTER_BG_SERVICE: Logic Error $e');
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

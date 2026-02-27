import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
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
  
  /// Request permissions in correct order: "while using" first, then "all the time".
  /// Handles denial gracefully; does not throw.
  Future<void> _requestPermissions() async {
    // 1. Request "while using the app" location first (required before "all the time" on Android 11+)
    var locationStatus = await Permission.location.status;
    if (!locationStatus.isGranted) {
      locationStatus = await Permission.location.request();
    }
    if (!locationStatus.isGranted) {
      // Permanently denied or denied once; do not request background
      return;
    }

    // 2. Request "allow all the time" (background) only after foreground is granted
    var bgStatus = await Permission.locationAlways.status;
    if (!bgStatus.isGranted) {
      await Permission.locationAlways.request();
    }

    // 3. Notification permission (Android 13+) - needed for foreground service notification
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // 4. Battery optimization (optional)
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// True if at least foreground (while using) location is granted. Required before starting tracking.
  Future<bool> hasLocationPermissionForTracking() async {
    return await Permission.location.isGranted;
  }

  /// Request location permission if not granted. Returns true if we have at least foreground location.
  Future<bool> requestLocationPermissionIfNeeded() async {
    var status = await Permission.location.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    status = await Permission.location.request();
    return status.isGranted;
  }

  /// True if background location ("all the time") is granted. Caller may show a hint if false.
  Future<bool> hasBackgroundLocationPermission() async {
    return await Permission.locationAlways.isGranted;
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

  static const String _keyLastSentLat = 'last_sent_lat';
  static const String _keyLastSentLng = 'last_sent_lng';
  static const String _keyLastSentTimestamp = 'last_sent_timestamp';

  /// Clear last-sent location (call when user ends duty so next Start duty sends first point).
  static Future<void> clearLastSentLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLastSentLat);
      await prefs.remove(_keyLastSentLng);
      await prefs.remove(_keyLastSentTimestamp);
    } catch (e) {
      print('LocationService: clearLastSentLocation error: $e');
    }
  }

  static Future<void> sendLocationToBackend(
    Position position,
    Battery battery,
  ) async {
    try {
      final batteryLevel = await battery.batteryLevel;
      final timestamp = DateTime.now().toIso8601String();

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

      // Send-side filter: skip bad GPS (adaptive thresholds in AppConfig)
      if (position.accuracy > AppConfig.maxAccuracyToSendMeters) {
        print('FLUTTER_BG_SERVICE: Skipping send (accuracy ${position.accuracy}m > ${AppConfig.maxAccuracyToSendMeters}m)');
        return;
      }

      // Send-side filter: skip if standing still (no filter on first send).
      // Optional: use position.speed to classify walking/running/driving and apply
      // different minMovementToSendMeters (see AppConfig docs).
      final prefs = await SharedPreferences.getInstance();
      final lastLat = prefs.getDouble(_keyLastSentLat);
      final lastLng = prefs.getDouble(_keyLastSentLng);
      final lastTs = prefs.getString(_keyLastSentTimestamp);
      if (lastLat != null && lastLng != null && lastTs != null) {
        final distM = Geolocator.distanceBetween(
          lastLat, lastLng, position.latitude, position.longitude,
        );
        final lastTime = DateTime.tryParse(lastTs);
        final elapsedSec = lastTime != null
            ? DateTime.now().difference(lastTime).inSeconds
            : AppConfig.maxIntervalWhenStillSeconds + 1;
        if (distM < AppConfig.minMovementToSendMeters &&
            elapsedSec < AppConfig.maxIntervalWhenStillSeconds) {
          print('FLUTTER_BG_SERVICE: Skipping send (standing still: ${distM.toStringAsFixed(0)}m moved, ${elapsedSec}s since last)');
          return;
        }
      }

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
        await prefs.setDouble(_keyLastSentLat, position.latitude);
        await prefs.setDouble(_keyLastSentLng, position.longitude);
        await prefs.setString(_keyLastSentTimestamp, timestamp);
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

  /// Max wall-clock time for one sync run; rest is synced on next resume or pull-to-refresh.
  static const Duration maxSyncDuration = Duration(seconds: 90);
  /// Max points to process per sync run to avoid long blocks; rest on next run.
  static const int maxPointsPerSyncRun = 150;

  /// Returns true if there are offline locations waiting to be synced.
  static Future<bool> hasPendingOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('offline_locations') ?? [];
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static const int _bulkThreshold = 5;
  static const int _bulkMaxPerRequest = 200;

  static Future<void> syncOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> offlineData = prefs.getStringList('offline_locations') ?? [];

      if (offlineData.isEmpty) return;

      print("FLUTTER_BG_SERVICE: Syncing ${offlineData.length} offline records...");
      final stopAt = DateTime.now().add(maxSyncDuration);
      List<String> remainingData = List<String>.from(offlineData);

      if (remainingData.length >= _bulkThreshold) {
        final batchSize = remainingData.length.clamp(0, _bulkMaxPerRequest).clamp(0, maxPointsPerSyncRun);
        final batch = remainingData.take(batchSize).toList();
        final List<Map<String, dynamic>> payloads = [];
        for (final jsonStr in batch) {
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final lat = data['latitude'];
            final lng = data['longitude'];
            final acc = data['accuracy'];
            final bat = data['battery_level'];
            if (lat == null || lng == null || acc == null || bat == null) continue;
            final accuracy = (acc is num) ? acc.toDouble() : null;
            final batteryLevel = (bat is int) ? bat : (bat is num ? (bat as num).toInt() : null);
            if (accuracy == null || batteryLevel == null) continue;
            payloads.add({
              'latitude': (lat is num) ? lat.toDouble() : 0.0,
              'longitude': (lng is num) ? lng.toDouble() : 0.0,
              'accuracy': accuracy,
              'battery_level': batteryLevel,
              'speed': data['speed'] is num ? (data['speed'] as num).toDouble() : null,
              'timestamp': data['timestamp'] is String ? data['timestamp'] as String : DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }
        final created = payloads.isEmpty ? 0 : await ApiService().logLocationBulk(payloads);
        if (created > 0) {
          final rest = remainingData.sublist(batch.length);
          final failedInBatch = batch.sublist(created > batch.length ? batch.length : created);
          remainingData = failedInBatch + rest;
          await prefs.setStringList('offline_locations', remainingData);
          print("FLUTTER_BG_SERVICE: Bulk sync created $created. Remaining: ${remainingData.length}");
        }
        return;
      }

      int processed = 0;
      const int chunkSize = 8;
      for (int i = 0; i < remainingData.length; i++) {
        if (DateTime.now().isAfter(stopAt) || processed >= maxPointsPerSyncRun) break;
        final String jsonStr = remainingData[i];
        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final lat = data['latitude'];
          final lng = data['longitude'];
          final acc = data['accuracy'];
          final bat = data['battery_level'];
          if (lat == null || lng == null || acc == null || bat == null) continue;
          final latitude = (lat is num) ? lat.toDouble() : null;
          final longitude = (lng is num) ? lng.toDouble() : null;
          final accuracy = (acc is num) ? acc.toDouble() : null;
          final batteryLevel = (bat is int) ? bat : (bat is num ? (bat as num).toInt() : null);
          if (latitude == null || longitude == null || accuracy == null || batteryLevel == null) continue;
          final speed = data['speed'] is num ? (data['speed'] as num).toDouble() : null;
          final timestamp = data['timestamp'] is String ? data['timestamp'] as String? : null;
          final success = await ApiService().logLocation(
            latitude: latitude,
            longitude: longitude,
            accuracy: accuracy,
            batteryLevel: batteryLevel,
            speed: speed,
            timestamp: timestamp,
          );
          if (success) {
            remainingData.removeAt(i);
            processed++;
            i--;
          }
        } catch (_) {}
        if ((i + 1) % chunkSize == 0) await Future.delayed(Duration.zero);
      }

      if (remainingData.length != offlineData.length || remainingData.isNotEmpty) {
        await prefs.setStringList('offline_locations', remainingData);
        print("FLUTTER_BG_SERVICE: Sync run done. Remaining: ${remainingData.length}");
      }
    } catch (e) {
      print("FLUTTER_BG_SERVICE: Error syncing $e");
    }
  }
}

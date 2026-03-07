import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';
import '../utils/working_hours.dart' as wh;
import 'auth_service.dart';
import 'api_service.dart';
import 'app_log_upload_service.dart';
import 'background_worker.dart';
import 'offline_queue_crypto.dart';

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  
  factory LocationService() {
    return _instance;
  }
  
  LocationService._internal();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

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
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
    print("LocationService: Scheduled periodic tracking check");
  }

  /// Start Tracking Manually (Start duty) - runs until user presses End duty
  Future<void> startTracking() async {
    await BackgroundWorker().startService();
    _startConnectivityListener();
  }

  /// Stop Tracking
  Future<void> stopTracking() async {
    _stopConnectivityListener();
    await BackgroundWorker().stopService();
  }

  /// Phase 1: When network returns (WiFi/Mobile), trigger sync so offline data goes up quickly.
  void _startConnectivityListener() {
    _stopConnectivityListener();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> result) {
      final connected = result.any((r) =>
          r == ConnectivityResult.mobile || r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
      if (connected) {
        print('LocationService: Network restored – triggering sync');
        // Location sync and log upload are separate flows; run in parallel, no shared queue.
        syncOfflineData();
        AppLogUploadService().uploadBatch();
      }
    });
  }

  void _stopConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
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

  /// Returns [true] only when the location was successfully delivered to the
  /// API. Returns [false] when the send was skipped (filter), saved offline,
  /// or failed. Callers can use this to decide whether to update UI elements
  /// such as the foreground notification timestamp.
  static Future<bool> sendLocationToBackend(
    Position position,
    Battery battery,
  ) async {
    try {
      final batteryLevel = await battery.batteryLevel;
      final timestamp = DateTime.now().toIso8601String();

      // In background isolate, FlutterSecureStorage may be unavailable due to
      // multi-engine plugin channel conflict. AuthService.getToken() already
      // falls back to SharedPreferences, so this call works in both isolates.
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
        return false;
      }

      // Send-side filter: skip bad GPS (adaptive thresholds in AppConfig)
      if (position.accuracy > AppConfig.maxAccuracyToSendMeters) {
        print('FLUTTER_BG_SERVICE: Skipping send (accuracy ${position.accuracy}m > ${AppConfig.maxAccuracyToSendMeters}m)');
        return false;
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
          return false;
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
        return true;
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
        return false;
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
      return false;
    }
  }

  /// Phase 8: Offline queue encrypted at rest (AES-256); key in secure storage.
  static const int _offlineQueueMaxSize = 1000;
  static const String _offlineQueueKey = 'offline_locations';

  static Future<void> _saveOffline(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_offlineQueueKey) ?? [];
      final offlineData = await OfflineQueueCrypto.decryptList(rawList);
      offlineData.add(jsonEncode(data));
      if (offlineData.length > _offlineQueueMaxSize) offlineData.removeAt(0);
      final encrypted = await OfflineQueueCrypto.encryptList(offlineData);
      await prefs.setStringList(_offlineQueueKey, encrypted);
      print("FLUTTER_BG_SERVICE: Saved to offline storage (encrypted). Count: ${offlineData.length}");
    } catch (e) {
      print("FLUTTER_BG_SERVICE: Error saving offline $e");
    }
  }

  /// Max wall-clock time for one sync run; rest is synced on next resume or pull-to-refresh.
  static const Duration maxSyncDuration = Duration(seconds: 90);
  /// Max points to process per sync run to avoid long blocks; rest on next run.
  static const int maxPointsPerSyncRun = 150;

  /// Phase 4: Sync state – only one sync runs at a time.
  static bool _syncInProgress = false;
  /// Current offline location sync state.
  static bool get isSyncInProgress => _syncInProgress;
  /// Idle = no sync running; Syncing = [syncOfflineData] in progress (further calls no-op).
  static String get offlineSyncState => _syncInProgress ? 'syncing' : 'idle';

  /// Returns true if there are offline locations waiting to be synced.
  static Future<bool> hasPendingOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_offlineQueueKey) ?? [];
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Phase 3: Use bulk upload whenever there is at least one offline point.
  static const int _bulkThreshold = 1;
  static const int _bulkMaxPerRequest = 200;

  static Future<void> syncOfflineData() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_offlineQueueKey) ?? [];
      final offlineData = await OfflineQueueCrypto.decryptList(rawList);

      if (offlineData.isEmpty) {
        _syncInProgress = false;
        return;
      }

      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) {
        _syncInProgress = false;
        return;
      }

      print("FLUTTER_BG_SERVICE: Syncing ${offlineData.length} offline records...");
      final stopAt = DateTime.now().add(maxSyncDuration);
      List<String> remainingData = List<String>.from(offlineData);

      if (remainingData.length >= _bulkThreshold) {
        final batchSize = remainingData.length.clamp(0, _bulkMaxPerRequest).clamp(0, maxPointsPerSyncRun);
        final batch = remainingData.take(batchSize).toList();
        final List<Map<String, dynamic>> payloads = [];
        final List<int> batchIndexForPayload = []; // payload index -> batch index
        for (int bi = 0; bi < batch.length; bi++) {
          final jsonStr = batch[bi];
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final lat = data['latitude'];
            final lng = data['longitude'];
            final acc = data['accuracy'];
            final bat = data['battery_level'];
            if (lat == null || lng == null || acc == null || bat == null) continue;
            final accuracy = (acc is num) ? acc.toDouble() : null;
            final batteryLevel = (bat is int) ? bat : (bat is num ? bat.toInt() : null);
            if (accuracy == null || batteryLevel == null) continue;
            final speedVal = data['speed'];
            payloads.add({
              'latitude': (lat is num) ? lat.toDouble() : 0.0,
              'longitude': (lng is num) ? lng.toDouble() : 0.0,
              'accuracy': accuracy,
              'battery_level': batteryLevel,
              'speed': speedVal is num ? speedVal.toDouble() : null,
              'timestamp': data['timestamp'] is String ? data['timestamp'] as String : DateTime.now().toIso8601String(),
            });
            batchIndexForPayload.add(bi);
          } catch (_) {}
        }
        final result = payloads.isEmpty ? null : await ApiService().logLocationBulk(payloads);
        if (result != null) {
          final created = result['created'] as int? ?? 0;
          final errorIndices = (result['errorIndices'] as List<dynamic>?)?.cast<int>() ?? <int>[];
          final failedBatchIndices = errorIndices
              .where((pi) => pi >= 0 && pi < batchIndexForPayload.length)
              .map((pi) => batchIndexForPayload[pi])
              .toSet();
          final failedBatch = <String>[];
          for (int i = 0; i < batch.length; i++) {
            if (failedBatchIndices.contains(i)) failedBatch.add(batch[i]);
          }
          final rest = remainingData.length > batch.length ? remainingData.sublist(batch.length) : <String>[];
          remainingData = failedBatch + rest;
          final toStore = remainingData.isEmpty
              ? <String>[]
              : await OfflineQueueCrypto.encryptList(remainingData);
          await prefs.setStringList(_offlineQueueKey, toStore);
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
          final batteryLevel = (bat is int) ? bat : (bat is num ? bat.toInt() : null);
          if (latitude == null || longitude == null || accuracy == null || batteryLevel == null) continue;
          final speedVal = data['speed'];
          final speed = speedVal is num ? speedVal.toDouble() : null;
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
        } catch (_) {
          // Phase 8: Drop unparseable/corrupt entries so they do not accumulate
          remainingData.removeAt(i);
          i--;
        }
        if ((i + 1) % chunkSize == 0) await Future.delayed(Duration.zero);
      }

      if (remainingData.length != offlineData.length || remainingData.isNotEmpty) {
        final toStore = remainingData.isEmpty
            ? <String>[]
            : await OfflineQueueCrypto.encryptList(remainingData);
        await prefs.setStringList(_offlineQueueKey, toStore);
        print("FLUTTER_BG_SERVICE: Sync run done. Remaining: ${remainingData.length}");
      }
    } catch (e) {
      print("FLUTTER_BG_SERVICE: Error syncing $e");
    } finally {
      _syncInProgress = false;
    }
  }
}

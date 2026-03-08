import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../database/app_log_db.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Phase 2: Upload app logs to backend. Exponential backoff; runs when network available.
class AppLogUploadService {
  static final AppLogUploadService _instance = AppLogUploadService._internal();
  factory AppLogUploadService() => _instance;
  AppLogUploadService._internal();

  static const int maxPerBatch = 500;
  // ignore: unused_field - reserved for future backoff
  int _retryCount = 0;
  /// Phase 4: Only one upload at a time (connectivity + foreground can both trigger).
  bool _uploadInProgress = false;

  /// Try to upload one batch of unuploaded logs. Call when app resumes or periodically.
  Future<bool> uploadBatch() async {
    if (_uploadInProgress) return false;
    _uploadInProgress = true;
    try {
      final token = await AuthService().getToken();
      if (token == null || token.isEmpty) return false;
      final results = await Connectivity().checkConnectivity();
      final connected = results.any((r) =>
          r == ConnectivityResult.mobile || r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
      if (!connected) return false;

      final rows = await AppLogDb.getUnuploaded(limit: maxPerBatch);
      if (rows.isEmpty) return true;

      final device = _deviceFromRows(rows);
      final logs = rows.map((r) => _rowToPayload(r)).toList();
      try {
        final response = await ApiService().client.post(
          AppConfig.mobileLogsBulkEndpoint,
          data: {'device': device, 'logs': logs},
        );
        if (response.statusCode == 200) {
          final ids = rows.map((r) => r['id'] as int).toList();
          await AppLogDb.markUploaded(ids);
          _retryCount = 0;
          if (kDebugMode) print('AppLogUploadService: uploaded ${ids.length} logs');
          return true;
        }
      } catch (e) {
        if (kDebugMode) print('AppLogUploadService upload error: $e');
      }
      _retryCount++;
      return false;
    } finally {
      _uploadInProgress = false;
    }
  }

  Map<String, String?> _deviceFromRows(List<Map<String, dynamic>> rows) {
    final first = rows.first;
    return {
      'android_version': first['device_android_version']?.toString(),
      'brand': first['device_brand']?.toString(),
      'model': first['device_model']?.toString(),
    };
  }

  Map<String, dynamic> _rowToPayload(Map<String, dynamic> r) {
    final ts = r['timestamp'];
    final tsIso = ts != null ? _msToIso(ts as int) : null;
    return {
      'timestamp': tsIso,
      'level': r['level'],
      'category': r['category'],
      'message': r['message'],
      'extra_json': r['extra_json'],
      'stack_trace': r['stack_trace'],
      'duration_ms': r['duration_ms'],
    };
  }

  String _msToIso(int ms) {
    return DateTime.fromMillisecondsSinceEpoch(ms).toUtc().toIso8601String();
  }
}

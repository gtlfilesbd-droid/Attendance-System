import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/app_log_db.dart';

/// Phase 2: Singleton app log service. Writes to SQLite with device info (offline-first).
class AppLogService {
  static final AppLogService _instance = AppLogService._internal();
  factory AppLogService() => _instance;
  AppLogService._internal();

  static const String levelDebug = 'DEBUG';
  static const String levelInfo = 'INFO';
  static const String levelWarn = 'WARN';
  static const String levelError = 'ERROR';

  String? _deviceBrand;
  String? _deviceModel;
  String? _deviceAndroidVersion;
  bool _deviceFetched = false;

  Future<Map<String, String?>> _getDeviceInfo() async {
    if (_deviceFetched) {
      return {
        'brand': _deviceBrand,
        'model': _deviceModel,
        'android_version': _deviceAndroidVersion,
      };
    }
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await deviceInfo.androidInfo;
        _deviceBrand = android.brand;
        _deviceModel = android.model;
        _deviceAndroidVersion = android.version.sdkInt.toString();
      } else {
        _deviceBrand = null;
        _deviceModel = null;
        _deviceAndroidVersion = null;
      }
    } catch (_) {
      _deviceBrand = _deviceModel = _deviceAndroidVersion = null;
    }
    _deviceFetched = true;
    return {'brand': _deviceBrand, 'model': _deviceModel, 'android_version': _deviceAndroidVersion};
  }

  /// Log a message. [extra] can be Map or will be stringified. [stackTrace] optional.
  Future<void> log(
    String level,
    String category,
    String message, {
    Map<String, dynamic>? extra,
    String? stackTrace,
    int? durationMs,
  }) async {
    try {
      final device = await _getDeviceInfo();
      String? extraJson;
      if (extra != null && extra.isNotEmpty) {
        extraJson = jsonEncode(extra);
        if (extraJson.length > 10000) extraJson = extraJson.substring(0, 10000);
      }
      final trace = stackTrace != null && stackTrace.length > 20000 ? stackTrace.substring(0, 20000) : stackTrace;
      await AppLogDb.insert(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        level: level,
        category: category,
        message: message.length > 10000 ? message.substring(0, 10000) : message,
        extraJson: extraJson,
        stackTrace: trace,
        durationMs: durationMs,
        deviceAndroidVersion: device['android_version'],
        deviceBrand: device['brand'],
        deviceModel: device['model'],
      );
    } catch (e) {
      if (kDebugMode) print('AppLogService log error: $e');
    }
  }

  Future<void> info(String category, String message, {Map<String, dynamic>? extra, int? durationMs}) =>
      log(levelInfo, category, message, extra: extra, durationMs: durationMs);

  Future<void> warn(String category, String message, {Map<String, dynamic>? extra, String? stackTrace}) =>
      log(levelWarn, category, message, extra: extra, stackTrace: stackTrace);

  Future<void> error(String category, String message, {Map<String, dynamic>? extra, String? stackTrace}) =>
      log(levelError, category, message, extra: extra, stackTrace: stackTrace);
}

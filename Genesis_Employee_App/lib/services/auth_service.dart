import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'api_service.dart';
import 'app_log_service.dart';
import 'duty_reminder_service.dart';
import 'push_notification_service.dart';

/// Result of a token refresh attempt. Used to decide whether to logout or retry.
enum RefreshResult {
  success,
  invalidToken,
  networkOrTransientError,
}

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  
  factory AuthService() {
    return _instance;
  }
  
  AuthService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// SharedPreferences key for background-isolate-readable token backup.
  /// Background Flutter engines cannot reliably access FlutterSecureStorage
  /// (plugin channel conflict in multi-engine setup), so we keep a plain-prefs
  /// copy that both the main and background isolates can read.
  static const String _bgTokenKey = 'bg_auth_token';

  /// Login with email and password.
  /// Returns null on success, or error message String on failure (Phase 7: includes 429 throttle message).
  Future<String?> login(String email, String password) async {
    try {
      ApiService().initialize();
      final response = await ApiService().login(email, password);

      if (response['success'] == true) {
        final data = response['data'];
        final access = data['access'];
        final refresh = data['refresh'];
        final employee = data['employee'];

        await _storage.write(key: AppConfig.tokenKey, value: access);
        await _storage.write(key: AppConfig.refreshTokenKey, value: refresh);
        // Also persist token in SharedPreferences so the background isolate can read it.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_bgTokenKey, access as String);
        } catch (_) {}
        if (employee != null) {
          await _storage.write(key: 'employee_data', value: jsonEncode(employee));
          if (employee['employee_id'] != null) {
            await _storage.write(key: AppConfig.employeeIdKey, value: employee['employee_id']);
          }
          if (employee['email'] != null) {
            await _storage.write(key: AppConfig.employeeEmailKey, value: employee['email']);
          }
        }
        try {
          await PushNotificationService().registerFCMToken();
        } catch (_) {}
        return null;
      }
      return response['message'] as String? ?? 'Login failed';
    } catch (e) {
      print('Login error: $e');
      return 'Connection error';
    }
  }

  /// Logout
  /// [reason] e.g. TOKEN_REFRESH_FAILED, MANUAL_LOGOUT – sent to backend for audit (Phase 1).
  /// Notifies backend (for audit log), then clears all stored data and stops location tracking.
  Future<void> logout({String? reason}) async {
    try {
      await AppLogService().info('SESSION', 'Logout reason=${reason ?? "unknown"}', extra: {'reason': reason});
    } catch (_) {}
    try {
      await ApiService().logout(reason: reason);
    } catch (_) {
      // Proceed with local logout even if API call fails (e.g. offline)
    }
    // Clear secure storage and SharedPreferences token backup
    await _storage.deleteAll();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bgTokenKey);
    } catch (_) {}
    
    // Stop background location service
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke("stopService");
    }
    // Cancel scheduled duty reminders
    await DutyReminderService().cancelAll();
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  /// Get stored JWT token.
  /// Falls back to SharedPreferences when FlutterSecureStorage returns null
  /// (e.g. background isolate plugin-channel conflict after multi-engine start).
  Future<String?> getToken() async {
    try {
      final token = await _storage.read(key: AppConfig.tokenKey);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}
    // Fallback: SharedPreferences copy (reliable across isolates)
    try {
      final prefs = await SharedPreferences.getInstance();
      final bg = prefs.getString(_bgTokenKey);
      if (bg != null && bg.isNotEmpty) return bg;
    } catch (_) {}
    return null;
  }

  /// Update stored employee data (e.g. after fetching fresh profile from GET /me/).
  Future<void> saveEmployeeData(Map<String, dynamic> data) async {
    await _storage.write(
      key: 'employee_data',
      value: jsonEncode(data),
    );
  }

  /// Get stored employee data
  Future<Map<String, dynamic>?> getEmployeeData() async {
    final data = await _storage.read(key: 'employee_data');
    if (data != null) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (e) {
        print('Error parsing employee data: $e');
        return null;
      }
    }
    return null;
  }

  /// Get stored refresh token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: AppConfig.refreshTokenKey);
  }

  /// Refresh access token using refresh token.
  /// Returns [RefreshResult.success] on 200 with access token;
  /// [RefreshResult.invalidToken] on 401/4xx (refresh token expired or invalid);
  /// [RefreshResult.networkOrTransientError] on timeout, connection error, or 5xx.
  Future<RefreshResult> refreshToken() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return RefreshResult.invalidToken;
      }

      ApiService().initialize();
      final dio = ApiService().client;
      final response = await dio.post(
        AppConfig.tokenRefreshEndpoint,
        data: {'refresh': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final access = data['access'];
        if (access != null) {
          await _storage.write(key: AppConfig.tokenKey, value: access.toString());
          if (data['refresh'] != null) {
            await _storage.write(key: AppConfig.refreshTokenKey, value: data['refresh'].toString());
          }
          // Keep SharedPreferences copy in sync
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_bgTokenKey, access.toString());
          } catch (_) {}
          return RefreshResult.success;
        }
      }
      // Non-200 success path (e.g. missing access in body)
      return RefreshResult.invalidToken;
    } on DioException catch (e) {
      print('Token refresh error: $e');
      final status = e.response?.statusCode;
      if (status != null && status >= 400 && status < 500) {
        return RefreshResult.invalidToken;
      }
      return RefreshResult.networkOrTransientError;
    } catch (e) {
      print('Token refresh error: $e');
      return RefreshResult.networkOrTransientError;
    }
  }
}

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

  /// Guard key stored in SharedPreferences (always wiped by "Clear Data" in
  /// App Info, unlike Android Keystore entries which survive on many OEMs).
  /// Used to detect stale Keystore tokens after Clear Data or reinstall.
  static const String _storageGuardKey = 'storage_guard_v1';

  /// Detects and purges stale Keystore tokens left over from a previous install
  /// or after "Clear Data" in App Info on OEMs where Keystore survives the wipe.
  ///
  /// Strategy: SharedPreferences is ALWAYS cleared by "Clear Data" / uninstall,
  /// whereas Android Keystore entries can persist on TECNO, Xiaomi, and other
  /// Chinese OEMs.  If the guard key is absent in SharedPreferences but tokens
  /// are still readable from FlutterSecureStorage, the storage is stale and must
  /// be purged so the app shows the login screen instead of a dead session.
  Future<void> ensureStorageIntegrity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_storageGuardKey)) return; // normal launch — nothing to do

      // Guard absent: SharedPreferences was wiped (Clear Data or fresh install).
      // Purge Keystore remnants so stale tokens cannot bypass the login screen.
      try {
        await _storage.deleteAll();
      } catch (_) {}
      try {
        await prefs.remove(_bgTokenKey);
      } catch (_) {}
    } catch (_) {}
  }

  /// Sets the storage guard in SharedPreferences after a successful login.
  Future<void> _setStorageGuard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageGuardKey, true);
    } catch (_) {}
  }

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
        // Mark storage as initialised so ensureStorageIntegrity() won't clear
        // Keystore entries on next launch (guard survives across app restarts).
        await _setStorageGuard();
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
    try {
      await _storage.deleteAll();
    } catch (_) {
      // Proceed even if secure storage fails (e.g. Keystore issues on some real devices)
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bgTokenKey);
    } catch (_) {}
    
    // Stop background location service
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke("stopService");
      }
    } catch (_) {
      // Proceed even if service check/invoke fails on some devices
    }
    // Cancel scheduled duty reminders
    try {
      await DutyReminderService().cancelAll();
    } catch (_) {}
    // Cancel FCM listeners so subscriptions are not leaked across sessions
    try {
      PushNotificationService.cancelListeners();
    } catch (_) {}
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

  /// Get stored refresh token.
  /// Returns null when FlutterSecureStorage is unavailable (e.g. background
  /// isolate Keystore conflict); callers should treat null as a transient error,
  /// NOT as "token does not exist", to avoid a false TOKEN_REFRESH_FAILED logout.
  Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: AppConfig.refreshTokenKey);
    } catch (_) {
      return null;
    }
  }

  /// Refresh access token using refresh token.
  /// Returns [RefreshResult.success] on 200 with access token;
  /// [RefreshResult.invalidToken] on 401/4xx (refresh token expired or invalid);
  /// [RefreshResult.networkOrTransientError] on timeout, connection error, or 5xx.
  ///
  /// Uses a plain Dio instance (no auth interceptor) so that the expired access
  /// token is never sent in the Authorization header of the refresh request.
  /// Sending an expired token on the refresh endpoint causes the backend's
  /// EmployeeJWTAuthentication to reject the request with 401 before the refresh
  /// body is processed, resulting in a spurious TOKEN_REFRESH_FAILED auto-logout.
  Future<RefreshResult> refreshToken() async {
    try {
      final refreshToken = await getRefreshToken();
      // null  → FlutterSecureStorage threw (background isolate Keystore conflict) →
      //         treat as transient so the interceptor retries with backoff instead of
      //         triggering a spurious TOKEN_REFRESH_FAILED auto-logout.
      // empty → token was stored as an empty string (should not happen) → invalid.
      if (refreshToken == null) return RefreshResult.networkOrTransientError;
      if (refreshToken.isEmpty) return RefreshResult.invalidToken;

      ApiService().initialize();
      // Use a dedicated plain Dio instance with no interceptors so the expired
      // access token is not attached to the Authorization header of this request.
      final dio = Dio(BaseOptions(
        baseUrl: ApiService().client.options.baseUrl,
        connectTimeout: ApiService().client.options.connectTimeout,
        receiveTimeout: ApiService().client.options.receiveTimeout,
        contentType: 'application/json',
      ));
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

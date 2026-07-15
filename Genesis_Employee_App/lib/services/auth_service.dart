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

  /// SharedPreferences keys for background-isolate-readable token backups.
  /// Background Flutter engines cannot reliably access FlutterSecureStorage
  /// (plugin channel conflict in multi-engine setup), so we keep plain-prefs
  /// copies that both the main and background isolates can read.
  static const String _bgTokenKey = 'bg_auth_token';
  static const String _bgRefreshTokenKey = 'bg_refresh_token';

  /// Guard key stored in SharedPreferences (always wiped by "Clear Data" in
  /// App Info, unlike Android Keystore entries which survive on many OEMs).
  /// Used to detect stale Keystore tokens after Clear Data or reinstall.
  static const String _storageGuardKey = 'storage_guard_v1';

  /// Verified session keys written via AuthService `_storage.write`.
  /// Does NOT include offline_queue_encryption_key or remembered_password.
  static const List<String> _sessionSecureKeys = [
    AppConfig.tokenKey,
    AppConfig.refreshTokenKey,
    AppConfig.employeeIdKey,
    AppConfig.employeeEmailKey,
    AppConfig.employeeDataKey,
  ];

  /// Serializes concurrent clearSessionStorage callers. Cleared only in finally.
  Future<void>? _clearSessionInFlight;

  /// Detects and purges stale Keystore tokens left over from a previous install
  /// or after "Clear Data" in App Info on OEMs where Keystore survives the wipe.
  ///
  /// Two-layer detection:
  /// 1. Guard key absent in SharedPreferences → definitely wiped (Clear Data /
  ///    fresh install without auto-backup) → purge everything.
  /// 2. Guard key present BUT SharedPreferences token backups are missing →
  ///    guard was restored by Android Auto Backup but real tokens are gone →
  ///    purge Keystore remnants and reset the guard so login screen is shown.
  Future<void> ensureStorageIntegrity() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.containsKey(_storageGuardKey)) {
        // Guard present — could be normal launch OR Android Auto Backup restored
        // the guard after uninstall/reinstall.  Check if our token backups
        // (which we write on every login/refresh) also survived.  If the guard
        // exists but the token backups do NOT, the guard was restored from
        // cloud backup after a reinstall and the session is stale.
        final hasAccessBackup = prefs.containsKey(_bgTokenKey);
        final hasRefreshBackup = prefs.containsKey(_bgRefreshTokenKey);
        if (hasAccessBackup || hasRefreshBackup) {
          // Genuine session — migrate refresh backup if missing (one-time,
          // covers upgrades from versions that only backed up the access token).
          if (!hasRefreshBackup) {
            try {
              final rt = await _storage.read(key: AppConfig.refreshTokenKey);
              if (rt != null && rt.isNotEmpty) {
                await prefs.setString(_bgRefreshTokenKey, rt);
              }
            } catch (_) {}
          }
          return;
        }
        // Guard restored from backup but token backups absent → stale session.
        // Fall through to purge.
      }

      // Guard absent OR stale backup-restored guard: purge session remnants.
      await clearSessionStorage(purgeIntegrity: true);
    } catch (_) {}
  }

  /// Clears JWT / employee session keys. Preserves Remember Me and offline
  /// queue encryption key. Concurrent callers share one in-flight Future;
  /// [_clearSessionInFlight] is always cleared in `finally`.
  Future<void> clearSessionStorage({required bool purgeIntegrity}) {
    final existing = _clearSessionInFlight;
    if (existing != null) {
      if (!purgeIntegrity) return existing;
      // First run may have been a normal logout; finish integrity extras after.
      return existing.then((_) => _finishIntegrityExtrasIfNeeded());
    }

    late final Future<void> run;
    run = () async {
      try {
        await _clearSessionStorageBody(purgeIntegrity: purgeIntegrity);
      } finally {
        // Must always clear even if body throws — otherwise lock is stuck permanently.
        if (identical(_clearSessionInFlight, run)) {
          _clearSessionInFlight = null;
        }
      }
    }();

    _clearSessionInFlight = run;
    return run;
  }

  Future<void> _clearSessionStorageBody({required bool purgeIntegrity}) async {
    for (final key in _sessionSecureKeys) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bgTokenKey);
      await prefs.remove(_bgRefreshTokenKey);
      if (purgeIntegrity) {
        await prefs.remove(_storageGuardKey);
        final remember = prefs.getBool(AppConfig.rememberMeKey) == true;
        if (!remember) {
          try {
            await _storage.delete(key: AppConfig.rememberedPasswordKey);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Idempotent extras when a concurrent non-purge clear finished first.
  Future<void> _finishIntegrityExtrasIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_storageGuardKey)) {
        await prefs.remove(_storageGuardKey);
      }
      final remember = prefs.getBool(AppConfig.rememberMeKey) == true;
      if (!remember) {
        try {
          await _storage.delete(key: AppConfig.rememberedPasswordKey);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Loads Remember Me credentials. Null-safe: missing values become empty strings.
  /// Password is Keystore-backed; client asked to persist it (device compromise risk).
  Future<({bool rememberMe, String email, String password})> loadRememberedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(AppConfig.rememberMeKey) == true;
      final email = prefs.getString(AppConfig.rememberedEmailKey) ?? '';
      String password = '';
      if (remember) {
        try {
          password = await _storage.read(key: AppConfig.rememberedPasswordKey) ?? '';
        } catch (_) {}
      }
      return (
        rememberMe: remember && email.isNotEmpty,
        email: email,
        password: password,
      );
    } catch (_) {
      return (rememberMe: false, email: '', password: '');
    }
  }

  Future<void> saveRememberedCredentials({
    required String email,
    required String password,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConfig.rememberMeKey, true);
      await prefs.setString(AppConfig.rememberedEmailKey, email.trim());
      await _storage.write(key: AppConfig.rememberedPasswordKey, value: password);
    } catch (_) {}
  }

  Future<void> clearRememberedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConfig.rememberMeKey);
      await prefs.remove(AppConfig.rememberedEmailKey);
    } catch (_) {}
    try {
      await _storage.delete(key: AppConfig.rememberedPasswordKey);
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
        // Also persist tokens in SharedPreferences so the background isolate and
        // OEM-Keystore-failure fallback can read them.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_bgTokenKey, access as String);
          if (refresh != null) {
            await prefs.setString(_bgRefreshTokenKey, refresh as String);
          }
        } catch (_) {}
        if (employee != null) {
          await _storage.write(key: AppConfig.employeeDataKey, value: jsonEncode(employee));
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
    // Clear session keys only (preserves Remember Me + offline queue crypto key)
    try {
      await clearSessionStorage(purgeIntegrity: false);
    } catch (_) {
      // Proceed even if secure storage fails (e.g. Keystore issues on some real devices)
    }

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
      key: AppConfig.employeeDataKey,
      value: jsonEncode(data),
    );
  }

  /// Get stored employee data
  Future<Map<String, dynamic>?> getEmployeeData() async {
    final data = await _storage.read(key: AppConfig.employeeDataKey);
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
  /// Tries FlutterSecureStorage with retry (handles Keystore sluggishness after
  /// process restart on some OEMs), then falls back to SharedPreferences backup.
  /// Returns null only when both storage layers have no token.
  Future<String?> getRefreshToken() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final token = await _storage.read(key: AppConfig.refreshTokenKey);
        if (token != null && token.isNotEmpty) return token;
        break; // null = key genuinely absent, retrying won't help
      } catch (_) {
        if (attempt < 2) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    // Fallback: SharedPreferences backup (reliable across all OEMs and isolates)
    try {
      final prefs = await SharedPreferences.getInstance();
      final bg = prefs.getString(_bgRefreshTokenKey);
      if (bg != null && bg.isNotEmpty) return bg;
    } catch (_) {}
    return null;
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
          // Keep SharedPreferences copies in sync (access + refresh backups)
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_bgTokenKey, access.toString());
            if (data['refresh'] != null) {
              await prefs.setString(_bgRefreshTokenKey, data['refresh'].toString());
            }
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

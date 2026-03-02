import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../config/app_config.dart';
import 'app_log_service.dart';
import 'auth_service.dart';

/// Route API response: locations list and optional distance in km from backend.
class RouteResponse {
  final List<dynamic> locations;
  final double? distanceKm;

  const RouteResponse({required this.locations, this.distanceKm});
}

class ApiService {
  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  
  factory ApiService() {
    return _instance;
  }
  
  ApiService._internal();

  /// Called when session expires (401 and refresh failed). Set by app to navigate to LoginScreen.
  static void Function()? onSessionExpired;

  static void _navigateToLoginOnSessionExpired() {
    final cb = onSessionExpired;
    if (cb != null) {
      // Defer so we don't navigate during interceptor execution.
      WidgetsBinding.instance.addPostFrameCallback((_) => cb());
    }
  }

  /// Test-only: when set, getMyProfile() returns this instead of calling the API.
  static Future<Map<String, dynamic>?> Function()? mockGetMyProfile;

  /// Test-only: when set, getMyAttendance() returns this instead of calling the API.
  static Future<Map<String, dynamic>> Function({String? startDate, String? endDate})? mockGetMyAttendance;

  /// Phase 7: When tracking/heartbeat gets 429, set so UI can show "Too many requests; will retry later."
  static String? lastTrackingThrottleMessage;

  /// Phase 7: User-friendly message for 429 responses (login or tracking).
  static String _messageFor429(DioException e) {
    final detail = e.response?.data;
    if (detail is Map && detail['detail'] != null) {
      final s = detail['detail'].toString();
      if (s.isNotEmpty) return s;
    }
    return 'Too many requests. Please try again later.';
  }

  final Dio _dio = Dio();

  /// Single refresh lock: only one token refresh runs on 401; others wait on this completer then retry.
  bool _isRefreshing = false;
  Completer<void>? _refreshCompleter;

  void initialize() {
    _dio.interceptors.clear();
    _dio.options.baseUrl = AppConfig.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);

    // Add interceptors
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Skip auth header for public/auth endpoints
        final path = options.path;
        final isAuthPath = path.contains('/auth/token/') || path.contains('/employees/auth/login/');

        if (!isAuthPath) {
          // Add Auth Token
          final token = await AuthService().getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        
        // Logging in debug mode
        if (kDebugMode) {
          print('API Request: [${options.method}] ${options.path}');
          print('Headers: ${options.headers}');
          print('Data: ${options.data}');
        }
        
        return handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          print('API Response: [${response.statusCode}] ${response.requestOptions.path}');
          print('Data: ${response.data}');
        }
        return handler.next(response);
      },
      onError: (DioException e, handler) async {
        if (kDebugMode) {
          print('API Error: [${e.response?.statusCode}] ${e.message}');
          print('Response: ${e.response?.data}');
        }

        final path = e.requestOptions.path;
        final isAuthPath = path.contains('/auth/token/') ||
            path.contains('/employees/auth/login/') ||
            path.contains('/employees/auth/logout/');

        // Only handle 401 for non-auth endpoints to avoid infinite loops.
        // Single refresh lock: first 401 triggers refresh; concurrent 401s wait on same refresh then retry.
        if (e.response?.statusCode == 401 && !isAuthPath) {
          final authService = AuthService();

          Future<void> doRetryWithNewToken() async {
            final newToken = await authService.getToken();
            if (newToken == null) return;
            e.requestOptions.headers['Authorization'] = 'Bearer $newToken';
            final opts = Options(
              method: e.requestOptions.method,
              headers: e.requestOptions.headers,
              contentType: e.requestOptions.contentType,
              responseType: e.requestOptions.responseType,
            );
            try {
              final cloneReq = await _dio.request(
                e.requestOptions.path,
                options: opts,
                data: e.requestOptions.data,
                queryParameters: e.requestOptions.queryParameters,
              );
              handler.resolve(cloneReq);
            } catch (_) {
              handler.next(e);
            }
          }

          if (_isRefreshing && _refreshCompleter != null) {
            try {
              await _refreshCompleter!.future;
              await doRetryWithNewToken();
            } catch (_) {
              handler.next(e);
            }
            return;
          }

          _isRefreshing = true;
          _refreshCompleter = Completer<void>();
          try {
            final refreshed = await authService.refreshToken();
            if (refreshed) {
              _refreshCompleter!.complete();
              await doRetryWithNewToken();
            } else {
              _refreshCompleter!.completeError(Exception('Token refresh failed'));
              try {
                await AppLogService().error('AUTH', 'Token refresh failed', extra: {'path': path});
              } catch (_) {}
              await authService.logout(reason: 'TOKEN_REFRESH_FAILED');
              _navigateToLoginOnSessionExpired();
              handler.next(e);
            }
          } catch (refreshError) {
            _refreshCompleter!.completeError(refreshError);
            if (kDebugMode) print('Token refresh failed: $refreshError');
            try {
              await AppLogService().error('AUTH', 'Token refresh failed', extra: {'path': path}, stackTrace: refreshError.toString());
            } catch (_) {}
            await authService.logout(reason: 'TOKEN_REFRESH_FAILED');
            _navigateToLoginOnSessionExpired();
            handler.next(e);
          } finally {
            _isRefreshing = false;
            _refreshCompleter = null;
          }
          return;
        }
        return handler.next(e);
      },
    ));
  }
  
  // Public accessor for raw client if needed
  Dio get client => _dio;

  // ---------------------------------------------------------------------------
  // API METHODS
  // ---------------------------------------------------------------------------

  /// Login Method
  /// POST /employees/auth/logout/ - notify backend for audit log (Phase 1: reason + optional device).
  Future<void> logout({String? reason, String? deviceBrand, String? deviceModel, String? androidVersion}) async {
    try {
      ApiService().initialize();
      final body = <String, dynamic>{};
      if (reason != null && reason.isNotEmpty) body['reason'] = reason;
      if (deviceBrand != null && deviceBrand.isNotEmpty) body['device_brand'] = deviceBrand;
      if (deviceModel != null && deviceModel.isNotEmpty) body['device_model'] = deviceModel;
      if (androidVersion != null && androidVersion.isNotEmpty) body['android_version'] = androidVersion;
      await _dio.post(AppConfig.logoutEndpoint, data: body.isNotEmpty ? body : null);
    } on Exception catch (_) {
      // Best effort; do not block logout if offline or token expired
    }
  }

  /// POST /employees/auth/login/
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _dio.post(
        AppConfig.loginEndpoint,
        data: {
          'email': email,
          'password': password,
        },
      );
      
      if (response.statusCode == 200) {
        return response.data;
      } else {
        return {
          'success': false,
          'message': 'Login failed: ${response.statusCode}'
        };
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        final msg = e.response?.data is Map && e.response?.data['detail'] != null
            ? e.response!.data['detail'].toString()
            : 'Too many attempts. Please try again in a minute.';
        return {'success': false, 'message': msg.isNotEmpty ? msg : 'Too many attempts. Please try again in a minute.'};
      }
      return {
        'success': false,
        'message': e.response?.data['message'] ?? 'Connection error',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unexpected error: $e',
      };
    }
  }

  /// Get current employee profile (GET /employees/me/).
  /// Returns profile data including profile_picture_url for read-only display.
  Future<Map<String, dynamic>?> getMyProfile() async {
    if (mockGetMyProfile != null) return mockGetMyProfile!();
    try {
      ApiService().initialize();
      final response = await _dio.get(AppConfig.employeeProfileEndpoint);
      if (response.statusCode == 200 &&
          response.data != null &&
          response.data['success'] == true) {
        final data = response.data['data'];
        if (data is Map<String, dynamic>) return data;
      }
      return null;
    } on DioException catch (e) {
      if (kDebugMode) print('API: getMyProfile error: ${e.message}');
      return null;
    } catch (e) {
      if (kDebugMode) print('API: getMyProfile error: $e');
      return null;
    }
  }

  /// Log Location
  /// POST /tracking/log-location/
  /// Sends employee UUID when available so backend can associate the location.
  /// [timestamp] optional ISO8601 string; when syncing offline points pass original capture time.
  Future<bool> logLocation({
    required double latitude,
    required double longitude,
    required double accuracy,
    required int batteryLevel,
    double? speed,
    String? timestamp,
  }) async {
    try {
      final employeeData = await AuthService().getEmployeeData();
      final employeeId = employeeData?['id']?.toString();

      final payload = <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'battery_level': batteryLevel,
        'speed': speed,
        'timestamp': timestamp ?? DateTime.now().toIso8601String(),
      };
      if (employeeId != null && employeeId.isNotEmpty) {
        payload['employee'] = employeeId;
      }

      print('API: logLocation POST ${AppConfig.baseUrl}${AppConfig.locationLogEndpoint} '
          'employeeId=${employeeId ?? "null"}');
      if (kDebugMode) {
        print('API: logLocation payload: $payload');
      }

      final response = await _dio.post(
        AppConfig.locationLogEndpoint,
        data: payload,
      );

      final ok = response.statusCode == 200 || response.statusCode == 201;
      if (ok) lastTrackingThrottleMessage = null;
      print('API: logLocation response status=${response.statusCode} success=$ok');
      if (kDebugMode && response.data != null) {
        print('API: logLocation response data: ${response.data}');
      }
      return ok;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        lastTrackingThrottleMessage = _messageFor429(e);
        if (kDebugMode) print('API: logLocation 429: $lastTrackingThrottleMessage');
      }
      print('API: logLocation DioException: ${e.type} ${e.message}');
      print('API: logLocation response status: ${e.response?.statusCode}');
      print('API: logLocation response data: ${e.response?.data}');
      return false;
    } catch (e, stackTrace) {
      print('API: logLocation error: $e');
      print('API: logLocation stackTrace: $stackTrace');
      return false;
    }
  }

  /// Bulk log locations (offline sync). POST /tracking/log-location/bulk/
  /// [locations] list of maps with latitude, longitude, timestamp, accuracy, battery_level, optional speed.
  /// Returns { 'created': int, 'errorIndices': List<int> } on success, null on failure (Phase 3).
  Future<Map<String, dynamic>?> logLocationBulk(List<Map<String, dynamic>> locations) async {
    if (locations.isEmpty) return {'created': 0, 'errorIndices': <int>[]};
    try {
      ApiService().initialize();
      final employeeData = await AuthService().getEmployeeData();
      final employeeId = employeeData?['id']?.toString();
      final List<Map<String, dynamic>> payloads = [];
      for (final loc in locations) {
        final m = Map<String, dynamic>.from(loc);
        if (employeeId != null && !m.containsKey('employee')) m['employee'] = employeeId;
        if (!m.containsKey('timestamp')) m['timestamp'] = DateTime.now().toIso8601String();
        payloads.add(m);
      }
      final response = await _dio.post(
        AppConfig.locationLogBulkEndpoint,
        data: {'locations': payloads},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        if (data is Map && data['success'] == true) {
          lastTrackingThrottleMessage = null;
          final created = data['created'] is int ? data['created'] as int : 0;
          final errors = data['errors'] as List<dynamic>?;
          final errorIndices = errors
                  ?.map((e) => e is Map && e['index'] != null ? (e['index'] is int ? e['index'] as int : (e['index'] as num).toInt()) : -1)
                  .where((i) => i >= 0)
                  .toList() ??
              <int>[];
          return {'created': created, 'errorIndices': errorIndices};
        }
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        lastTrackingThrottleMessage = _messageFor429(e);
        if (kDebugMode) print('API: logLocationBulk 429: $lastTrackingThrottleMessage');
      }
      if (kDebugMode) print('API: logLocationBulk error: ${e.message}');
      return null;
    } catch (e) {
      if (kDebugMode) print('API: logLocationBulk error: $e');
      return null;
    }
  }

  /// Heartbeat for last_seen / offline detection. POST /tracking/heartbeat/
  Future<bool> sendHeartbeat({
    String? deviceId,
    String? appVersion,
    int? batteryLevel,
    bool? isTrackingEnabled,
    String? latestLocationTimestamp,
    String? deviceOs,
  }) async {
    try {
      ApiService().initialize();
      final payload = <String, dynamic>{};
      if (deviceId != null) payload['device_id'] = deviceId;
      if (appVersion != null) payload['app_version'] = appVersion;
      if (batteryLevel != null) payload['battery_level'] = batteryLevel;
      if (isTrackingEnabled != null) payload['is_tracking_enabled'] = isTrackingEnabled;
      if (latestLocationTimestamp != null) payload['latest_location_timestamp'] = latestLocationTimestamp;
      if (deviceOs != null) payload['device_os'] = deviceOs;
      final response = await _dio.post(AppConfig.heartbeatEndpoint, data: payload);
      final ok = response.statusCode == 200;
      if (ok) lastTrackingThrottleMessage = null;
      return ok;
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        lastTrackingThrottleMessage = _messageFor429(e);
        if (kDebugMode) print('API: sendHeartbeat 429: $lastTrackingThrottleMessage');
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get My Route Today
  /// GET /tracking/my-route-today/
  /// Backend returns { "data": { "locations": [...] } } (plain list) or GeoJSON FeatureCollection
  Future<List<dynamic>> getMyRouteToday() async {
    try {
      final response = await _dio.get('/tracking/my-route-today/');
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        if (data == null) return [];
        final locations = data['locations'];
        if (locations == null) return [];
        // Plain list from backend
        if (locations is List) return List<dynamic>.from(locations);
        // GeoJSON FeatureCollection: use features array
        if (locations is Map && locations['features'] is List) {
          return List<dynamic>.from(locations['features'] as List);
        }
        return [];
      }
      return [];
    } catch (e) {
      print('API: getMyRouteToday error: $e');
      return [];
    }
  }

  /// Response from route API: locations and optional distance when backend provides it.
  static RouteResponse emptyRoute() =>
      const RouteResponse(locations: <dynamic>[], distanceKm: null);

  /// Get my route for a given date (and optional time range).
  /// GET /tracking/employee-route/?employee_id=uuid&date=YYYY-MM-DD&start_time=&end_time=
  /// Backend returns { "data": { "locations": [...], "distance": number? } }; use distance when available.
  Future<RouteResponse> getMyRouteWithMeta({
    required String employeeId,
    String? date,
    String? startTime,
    String? endTime,
  }) async {
    try {
      final queryParams = <String, dynamic>{'employee_id': employeeId};
      if (date != null && date.isNotEmpty) queryParams['date'] = date;
      if (startTime != null && startTime.isNotEmpty) queryParams['start_time'] = startTime;
      if (endTime != null && endTime.isNotEmpty) queryParams['end_time'] = endTime;
      final response = await _dio.get(
        '/tracking/employee-route/',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        if (data == null) return ApiService.emptyRoute();
        final locs = data['locations'];
        List<dynamic> locations = [];
        if (locs is List) {
          locations = List<dynamic>.from(locs);
        } else if (locs is Map && locs['features'] is List) {
          locations = List<dynamic>.from(locs['features'] as List);
        }
        double? distanceKm;
        final dist = data['distance'] ?? data['distance_km'];
        if (dist != null && dist is num) distanceKm = dist.toDouble();
        return RouteResponse(locations: locations, distanceKm: distanceKm);
      }
      return ApiService.emptyRoute();
    } catch (e) {
      print('API: getMyRouteWithMeta error: $e');
      rethrow;
    }
  }

  /// Get my route (locations only). Prefer [getMyRouteWithMeta] when distance from backend is needed.
  Future<List<dynamic>> getMyRoute({
    required String employeeId,
    String? date,
    String? startTime,
    String? endTime,
  }) async {
    final res = await getMyRouteWithMeta(
      employeeId: employeeId,
      date: date,
      startTime: startTime,
      endTime: endTime,
    );
    return res.locations;
  }

  /// Resolve lat/lon to the same display address as the dashboard marker popup.
  /// GET /tracking/resolve-address/?lat=&lon=
  Future<String?> resolveAddress(double latitude, double longitude) async {
    try {
      final response = await _dio.get(
        '/tracking/resolve-address/',
        queryParameters: {'lat': latitude, 'lon': longitude},
      );
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['address'] != null) {
          final addr = data['address'].toString().trim();
          return addr.isEmpty ? null : addr;
        }
      }
      return null;
    } on DioException catch (_) {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Start Duty - record start time and location.
  /// Returns response data (start_time, session_id, date) on success, null on failure.
  /// POST /attendance/start-duty/
  Future<Map<String, dynamic>?> startDuty({
    required double latitude,
    required double longitude,
    String? address,
    String? date,
  }) async {
    try {
      final payload = <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
      };
      if (address != null && address.isNotEmpty) payload['address'] = address;
      if (date != null && date.isNotEmpty) payload['date'] = date;
      final response = await _dio.post(
        AppConfig.startDutyEndpoint,
        data: payload,
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['data'] is Map<String, dynamic>) {
          return data['data'] as Map<String, dynamic>;
        }
        return null;
      }
      return null;
    } on DioException catch (e) {
      print('API: startDuty error: ${e.message}');
      return null;
    } catch (e) {
      print('API: startDuty error: $e');
      return null;
    }
  }

  /// End Duty - record end time and location
  /// POST /attendance/end-duty/
  Future<bool> endDuty({
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      final payload = <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
      };
      if (address != null && address.isNotEmpty) payload['address'] = address;
      final response = await _dio.post(
        AppConfig.endDutyEndpoint,
        data: payload,
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      print('API: endDuty error: ${e.message}');
      return false;
    } catch (e) {
      print('API: endDuty error: $e');
      return false;
    }
  }

  /// Get My Attendance
  /// GET /attendance/my-attendance/?start_date=X&end_date=Y
  /// Retries up to 2 times with 2s delay on failure before returning error.
  Future<Map<String, dynamic>> getMyAttendance({
    String? startDate,
    String? endDate,
  }) async {
    if (mockGetMyAttendance != null) {
      return mockGetMyAttendance!(startDate: startDate, endDate: endDate);
    }
    const maxAttempts = 3;
    const retryDelay = Duration(seconds: 2);
    final queryParams = <String, dynamic>{};
    if (startDate != null) queryParams['start_date'] = startDate;
    if (endDate != null) queryParams['end_date'] = endDate;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _dio.get(
          AppConfig.myAttendanceEndpoint,
          queryParameters: queryParams,
        );
        if (response.statusCode == 200 && response.data['success'] == true) {
          return response.data['data'] as Map<String, dynamic>;
        }
        return {'by_date': []};
      } catch (e) {
        print('API: getMyAttendance error (attempt $attempt/$maxAttempts): $e');
        if (attempt == maxAttempts) {
          return {
            'by_date': [],
            'error': "Couldn't load attendance. Check connection.",
          };
        }
        await Future.delayed(retryDelay);
      }
    }
    return {
      'by_date': [],
      'error': "Couldn't load attendance. Check connection.",
    };
  }
}

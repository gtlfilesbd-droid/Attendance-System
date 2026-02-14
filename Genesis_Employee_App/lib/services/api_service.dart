import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'auth_service.dart';

class ApiService {
  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  
  factory ApiService() {
    return _instance;
  }
  
  ApiService._internal();

  /// Test-only: when set, getMyProfile() returns this instead of calling the API.
  static Future<Map<String, dynamic>?> Function()? mockGetMyProfile;

  final Dio _dio = Dio();
  
  void initialize() {
    _dio.options.baseUrl = AppConfig.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
    
    // Add interceptors
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Add Auth Token
        final token = await AuthService().getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
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
        
        // Handle 401 Unauthorized (Token expired)
        if (e.response?.statusCode == 401) {
          try {
            // Attempt to refresh the token
            final authService = AuthService();
            final refreshed = await authService.refreshToken();
            
            if (refreshed) {
              // Retry the original request with new token
              final newToken = await authService.getToken();
              if (newToken != null) {
                // Update the request options with new token
                e.requestOptions.headers['Authorization'] = 'Bearer $newToken';
                
                // Retry the request
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
                  return handler.resolve(cloneReq);
                } catch (retryError) {
                  // If retry also fails, proceed with error
                  return handler.next(e);
                }
              }
            }
            
            // If refresh failed, logout
            await authService.logout();
          } catch (refreshError) {
            print('Token refresh failed: $refreshError');
            await AuthService().logout();
          }
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
      return {
        'success': false,
        'message': e.response?.data['message'] ?? 'Connection error'
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unexpected error: $e'
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
  Future<bool> logLocation({
    required double latitude,
    required double longitude,
    required double accuracy,
    required int batteryLevel,
    double? speed,
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
        'timestamp': DateTime.now().toIso8601String(),
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
      print('API: logLocation response status=${response.statusCode} success=$ok');
      if (kDebugMode && response.data != null) {
        print('API: logLocation response data: ${response.data}');
      }
      return ok;
    } on DioException catch (e) {
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

  /// Start Duty - record start time and location.
  /// Returns response data (start_time, session_id, date) on success, null on failure.
  /// POST /attendance/start-duty/
  Future<Map<String, dynamic>?> startDuty({
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
  Future<Map<String, dynamic>> getMyAttendance({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (startDate != null) queryParams['start_date'] = startDate;
      if (endDate != null) queryParams['end_date'] = endDate;

      final response = await _dio.get(
        AppConfig.myAttendanceEndpoint,
        queryParameters: queryParams,
      );
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      print('API: getMyAttendance error: $e');
      return {};
    }
  }
}

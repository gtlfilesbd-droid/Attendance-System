import 'dart:io';
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
          // TODO: Implement token refresh logic here
          // For now, we logout
          await AuthService().logout();
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

  /// Log Location
  /// POST /tracking/log-location/
  Future<bool> logLocation({
    required double latitude,
    required double longitude,
    required double accuracy,
    required int batteryLevel,
    double? speed,
  }) async {
    try {
      final response = await _dio.post(
        AppConfig.locationLogEndpoint,
        data: {
          'latitude': latitude,
          'longitude': longitude,
          'accuracy': accuracy,
          'battery_level': batteryLevel,
          'speed': speed,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print('API: logLocation error: $e');
      return false;
    }
  }

  /// Get My Route Today
  /// GET /tracking/my-route-today/
  Future<List<dynamic>> getMyRouteToday() async {
    try {
      final response = await _dio.get('/tracking/my-route-today/');
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        // The backend returns { "data": { "locations": [...] } }
        return response.data['data']['locations'] ?? [];
      }
      return [];
    } catch (e) {
      print('API: getMyRouteToday error: $e');
      return [];
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

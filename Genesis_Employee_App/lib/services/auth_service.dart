import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../config/app_config.dart';
import 'api_service.dart';

class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  
  factory AuthService() {
    return _instance;
  }
  
  AuthService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Login with email and password
  /// Uses ApiService to perform the network request
  Future<bool> login(String email, String password) async {
    try {
      // Initialize ApiService if not already
      ApiService().initialize();
      
      final response = await ApiService().login(email, password);

      if (response['success'] == true) {
        final data = response['data'];
        final access = data['access'];
        final refresh = data['refresh'];
        final employee = data['employee'];

        // Save tokens
        await _storage.write(key: AppConfig.tokenKey, value: access);
        await _storage.write(key: AppConfig.refreshTokenKey, value: refresh);
        
        // Save employee data
        if (employee != null) {
          await _storage.write(
            key: 'employee_data', 
            value: jsonEncode(employee)
          );
          
          // Also save specific fields if needed by AppConfig keys
          if (employee['employee_id'] != null) {
            await _storage.write(key: AppConfig.employeeIdKey, value: employee['employee_id']);
          }
          if (employee['email'] != null) {
            await _storage.write(key: AppConfig.employeeEmailKey, value: employee['email']);
          }
        }
        
        return true;
      }
      return false;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  /// Logout
  /// Clears all stored data and stops location tracking
  Future<void> logout() async {
    // Clear secure storage
    await _storage.deleteAll();
    
    // Stop background location service
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke("stopService");
    }
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: AppConfig.tokenKey);
    return token != null;
  }

  /// Get stored JWT token
  Future<String?> getToken() async {
    return await _storage.read(key: AppConfig.tokenKey);
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
}

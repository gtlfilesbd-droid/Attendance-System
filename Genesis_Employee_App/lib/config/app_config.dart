class AppConfig {
  // API Configuration
  // Detected LAN IP: 192.168.68.50
  // Use 10.0.2.2 for Android Emulator, localhost for iOS Simulator
  static const String baseUrl = 'http://192.168.68.50:8000/api';
  
  // API Endpoints
  static const String loginEndpoint = '/employees/auth/login/';
  static const String locationLogEndpoint = '/tracking/log-location/';
  static const String myAttendanceEndpoint = '/attendance/my-attendance/';
  static const String employeeProfileEndpoint = '/employees/me/';
  
  // Location Tracking Configuration
  static const int locationUpdateInterval = 300; // 5 minutes in seconds
  static const double locationAccuracy = 10.0; // meters
  
  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String employeeIdKey = 'employee_id';
  static const String employeeEmailKey = 'employee_email';
  
  // App Configuration
  static const String appName = 'Genesis Employee';
  static const String appVersion = '1.0.0';
}

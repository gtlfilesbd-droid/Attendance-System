class AppConfig {
  // API Configuration - PC IP: 103.29.60.233 (Web PC where Django/Docker runs)
  // Use 10.0.2.2 for Android Emulator, localhost for iOS Simulator
  static const String baseUrl = 'http://103.29.60.233:8000/api';
  
  // API Endpoints
  static const String loginEndpoint = '/employees/auth/login/';
  static const String tokenRefreshEndpoint = '/auth/token/refresh/';
  static const String locationLogEndpoint = '/tracking/log-location/';
  static const String myAttendanceEndpoint = '/attendance/my-attendance/';
  static const String startDutyEndpoint = '/attendance/start-duty/';
  static const String endDutyEndpoint = '/attendance/end-duty/';
  static const String employeeProfileEndpoint = '/employees/me/';
  
  // Location Tracking Configuration
  static const int locationUpdateInterval = 300; // 5 minutes in seconds (e.g. for docs)
  /// Interval in seconds when duty is active (Start Duty). Location sent every N seconds.
  static const int locationUpdateIntervalSecondsWhenDuty = 5;
  /// Interval in minutes to auto-refresh current location name on home screen.
  static const int placeNameRefreshMinutes = 15;
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

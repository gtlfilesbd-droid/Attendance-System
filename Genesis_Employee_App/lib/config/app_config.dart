class AppConfig {
  // API Configuration - PC IP: 103.29.60.233 (Web PC where Django/Docker runs)
  // Use 10.0.2.2 for Android Emulator, localhost for iOS Simulator
  static const String baseUrl = 'http://103.29.60.233:8000/api';
  
  // API Endpoints
  static const String loginEndpoint = '/employees/auth/login/';
  static const String logoutEndpoint = '/employees/auth/logout/';
  static const String tokenRefreshEndpoint = '/auth/token/refresh/';
  static const String locationLogEndpoint = '/tracking/log-location/';
  static const String myAttendanceEndpoint = '/attendance/my-attendance/';
  static const String startDutyEndpoint = '/attendance/start-duty/';
  static const String endDutyEndpoint = '/attendance/end-duty/';
  static const String employeeProfileEndpoint = '/employees/me/';
  static const String registerDeviceEndpoint = '/employees/auth/register-device/';
  
  // Location Tracking Configuration
  static const int locationUpdateInterval = 300; // 5 minutes in seconds (e.g. for docs)
  /// Interval in seconds when duty is active (Start Duty). Location sent every N seconds.
  /// Use 60–120 for better battery; lower values increase drain and heat.
  static const int locationUpdateIntervalSecondsWhenDuty = 60;
  /// Interval in minutes to auto-refresh current location name on home screen.
  static const int placeNameRefreshMinutes = 15;
  static const double locationAccuracy = 10.0; // meters

  /// Send-side filter: do not send location if accuracy is worse than this (meters).
  static const double maxAccuracyToSendMeters = 100.0;
  /// Send-side filter: do not send if moved less than this since last send (meters).
  static const double minMovementToSendMeters = 10.0;
  /// Send-side filter: when standing still, still send at least every N seconds.
  static const int maxIntervalWhenStillSeconds = 300;

  // Storage Keys
  static const String tokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String employeeIdKey = 'employee_id';
  static const String employeeEmailKey = 'employee_email';
  
  // App Configuration
  static const String appName = 'Genesis Employee';
  static const String appVersion = '1.0.0';
}

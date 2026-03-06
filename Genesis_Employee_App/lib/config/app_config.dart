class AppConfig {
  /// Phase 6: API base URL is configurable at build time. Use HTTPS in production.
  /// Default: current dev server. To use production HTTPS, build with:
  ///   flutter build apk --dart-define=BASE_URL=https://your-domain.com/api
  /// (No trailing slash after /api; endpoints are e.g. /employees/auth/login/.)
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://103.29.60.233:8000/api',
  );
  /// True when base URL uses HTTPS (production-safe).
  static bool get isSecureBaseUrl => baseUrl.startsWith('https://');
  
  // API Endpoints
  static const String loginEndpoint = '/employees/auth/login/';
  static const String logoutEndpoint = '/employees/auth/logout/';
  static const String tokenRefreshEndpoint = '/auth/token/refresh/';
  static const String locationLogEndpoint = '/tracking/log-location/';
  static const String locationLogBulkEndpoint = '/tracking/log-location/bulk/';
  static const String heartbeatEndpoint = '/tracking/heartbeat/';
  static const String myAttendanceEndpoint = '/attendance/my-attendance/';
  static const String startDutyEndpoint = '/attendance/start-duty/';
  static const String endDutyEndpoint = '/attendance/end-duty/';
  static const String activeSessionEndpoint = '/attendance/active-session/';
  static const String employeeProfileEndpoint = '/employees/me/';
  static const String registerDeviceEndpoint = '/employees/auth/register-device/';
  /// Phase 2: Mobile log bulk upload
  static const String mobileLogsBulkEndpoint = '/audit/mobile-logs/bulk/';

  // Location Tracking Configuration
  static const int locationUpdateInterval = 300; // 5 minutes in seconds (e.g. for docs)
  /// Interval in seconds when duty is active (Start Duty). Used when moving slowly / standing.
  /// Use 60–120 for better battery when walking or still.
  static const int locationUpdateIntervalSecondsWhenDuty = 60;
  /// When moving fast (e.g. vehicle), send location more often for smoother route.
  /// Speed threshold: if Position.speed >= [speedThresholdMovingMps] m/s, use this interval.
  static const int locationUpdateIntervalSecondsWhenMoving = 15;
  /// Speed above this (m/s) is treated as "moving" for adaptive interval. ~2 m/s ≈ 7.2 km/h.
  static const double speedThresholdMovingMps = 2.0;

  /// Phase 5: Battery-aware interval tuning. When battery % <= this, use power-save intervals.
  static const int batteryLowThresholdPercent = 20;
  /// Interval (seconds) when duty + standing still and battery is low. Longer = less wake, better battery.
  static const int locationUpdateIntervalSecondsWhenDutyPowerSave = 120;
  /// Interval (seconds) when moving and battery is low.
  static const int locationUpdateIntervalSecondsWhenMovingPowerSave = 30;

  /// Send immediately when displacement from last sent position exceeds this (meters).
  /// Reduces zigzag on map when driving; 30–50 m is a good range for vehicle.
  static const double minDisplacementToSendMeters = 30.0;
  /// Interval in minutes to auto-refresh current location name on home screen.
  static const int placeNameRefreshMinutes = 15;
  static const double locationAccuracy = 10.0; // meters

  /// Send-side filter: do not send location if accuracy is worse than this (meters).
  /// Relaxed to 200m for moving scenarios (vehicle/fast walking) where GPS accuracy often degrades.
  static const double maxAccuracyToSendMeters = 200.0;
  /// Send-side filter: do not send if moved less than this since last send (meters).
  /// Enterprise tuning: use 10–20 for walking, ~25 for running, 30–50 for driving.
  /// Optional: detect movement type from [Position.speed] and adapt this threshold per profile.
  static const double minMovementToSendMeters = 10.0;
  /// Send-side filter: when standing still, still send at least every N seconds (e.g. 300 = 5 min).
  /// Ensures last known position is sent after a timeout even if the user has not moved.
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

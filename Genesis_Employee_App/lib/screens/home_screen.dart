import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../utils/android_sdk.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../services/foreground_refresh_service.dart';
import '../services/push_notification_service.dart';
import 'attendance_screen.dart';
import 'profile_screen.dart';
import 'todo_list_screen.dart';

/// Nominatim reverse geocode: returns short address string or null on failure.
/// Prefers more specific OSM keys (quarter, residential, suburb) over broader (neighbourhood).
Future<String?> _nominatimReverseGeocode(double latitude, double longitude) async {
  try {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?lat=$latitude&lon=$longitude&format=json&addressdetails=1&zoom=18&layer=address',
    );
    final response = await http.get(
      uri,
      headers: {'User-Agent': 'GenesisEmployeeApp/1.0'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>?;
    if (data == null) return null;
    final address = data['address'] as Map<String, dynamic>?;
    final displayName = data['display_name'] as String?;
    if (address != null && address.isNotEmpty) {
      String? str(dynamic v) => (v is String) ? v.trim() : null;
      final road = str(address['road']);
      final quarter = str(address['quarter']);
      final residential = str(address['residential']);
      final cityDistrict = str(address['city_district']);
      final suburb = str(address['suburb']);
      final neighbourhood = str(address['neighbourhood']);
      final district = str(address['district']);
      final borough = str(address['borough']);
      final village = str(address['village']);
      final city = str(address['city']);
      final county = str(address['county']);
      // Area: first non-empty from most-specific to broader (prefer D.O.H.S.-style over cantonment)
      final areaCandidates = [
        quarter,
        residential,
        cityDistrict,
        suburb,
        neighbourhood,
        district,
        borough,
        village,
      ];
      String? area;
      for (final c in areaCandidates) {
        if (c != null && c.isNotEmpty) {
          area = c;
          break;
        }
      }
      final cityOrCounty = (city != null && city.isNotEmpty) ? city : county;
      final parts = <String>[];
      if (road != null && road.isNotEmpty) parts.add(road);
      if (area != null && area.isNotEmpty) parts.add(area);
      if (cityOrCounty != null && cityOrCounty.isNotEmpty) parts.add(cityOrCounty);
      if (parts.isNotEmpty) {
        final fromAddress = parts.take(3).join(', ');
        // Prefer display_name when it has more detail than our address-built string
        if (displayName != null && displayName.isNotEmpty) {
          final dnParts = displayName.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          if (dnParts.length >= 4 && parts.length <= 2) {
            return dnParts.take(4).join(', ');
          }
        }
        return fromAddress;
      }
    }
    if (displayName != null && displayName.isNotEmpty) {
      final parts = displayName.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.take(3).join(', ');
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// True if [s] looks like "23.83780, 90.37219" (coordinates only, not a real address).
bool _isCoordinatesOnly(String? s) {
  if (s == null || s.isEmpty) return false;
  final parts = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (parts.length != 2) return false;
  try {
    final a = double.tryParse(parts[0]);
    final b = double.tryParse(parts[1]);
    return a != null && b != null;
  } catch (_) {
    return false;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();

  bool _isTracking = false;
  String _currentPlaceName = '—';
  String _employeeName = '';
  String? _profilePictureUrl;
  DateTime? _dutyStartTime;
  int _todayBaseSeconds = 0;
  DateTime _todayDate = DateTime(1970, 1, 1);
  Timer? _placeRefreshTimer;
  int _loadTodayDutyTimeGeneration = 0;
  /// Set when getMyAttendance fails so duty time card can show error + retry.
  String? _dutyTimeLoadError;
  /// Set when background service status check fails (e.g. exception).
  bool _statusCheckError = false;
  /// Network connectivity (connectivity_plus; does not guarantee internet reachability).
  bool _hasNetwork = true;
  bool _isRefreshingLocation = false;
  /// Prevents double-tap / overlapping Start or End duty operations (re-entry guard).
  bool _isDutyOperationInProgress = false;

  @override
  void initState() {
    super.initState();
    ForegroundRefreshService().addListener(_onForegroundRefresh);
    _loadData();
    PushNotificationService().registerFCMToken();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PushNotificationService.flushPendingDeepLink();
      if (mounted) {
        // Load duty state first; then start or stop tracking based on open session (enterprise: single source of truth from backend)
        await _loadTodayDutyTime();
        if (!mounted) return;
        if (_dutyStartTime != null) {
          await _locationService.startTracking();
          // Wait for Android to start the foreground service isolate before
          // calling isRunning(); without this delay the first status check
          // always returns false even when the service started successfully.
          await Future.delayed(const Duration(seconds: 1));
          await _checkServiceStatus();
        } else {
          await _locationService.stopTracking();
          await _checkServiceStatus();
        }
        if (mounted) await _checkConnectivity();
      }
    });
    _fetchCurrentPlaceName().then((_) {
      // If the first geocoding attempt failed (network not ready on start),
      // schedule a quick retry after 5 s and again after 15 s before handing
      // off to the regular periodic timer.
      if (mounted && (_currentPlaceName.isEmpty || _currentPlaceName == '—')) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) _fetchCurrentPlaceName();
        });
        Future.delayed(const Duration(seconds: 15), () {
          if (mounted && (_currentPlaceName.isEmpty || _currentPlaceName == '—')) {
            _fetchCurrentPlaceName();
          }
        });
      }
      if (mounted) {
        _placeRefreshTimer = Timer.periodic(
          const Duration(minutes: AppConfig.placeNameRefreshMinutes),
          (_) => _fetchCurrentPlaceName(),
        );
      }
    });
    // Schedule periodic check (only stops service when outside working hours; never auto-starts)
    _locationService.scheduleTracking();
    // No auto-start: tracking starts only when user presses Start duty
  }
  
  @override
  void dispose() {
    ForegroundRefreshService().removeListener(_onForegroundRefresh);
    _placeRefreshTimer?.cancel();
    super.dispose();
  }

  void _onForegroundRefresh() {
    if (!mounted) return;
    _loadData().then((_) async {
      if (!mounted) return;
      await _loadTodayDutyTime();
      if (!mounted) return;
      await _checkServiceStatus();
      if (!mounted) return;
      // If we have open session but service was killed (e.g. by Android Doze),
      // restart it. Wait 1 s before checking isRunning() because startService()
      // is asynchronous – the platform channel returns before the isolate is live.
      if (!_isTracking && _dutyStartTime != null) {
        await _locationService.startTracking();
        await Future.delayed(const Duration(seconds: 1));
        await _checkServiceStatus();
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tracking resumed')),
          );
        }
      }
    });
    // Refresh location name on every foreground resume so that the displayed
    // name is up-to-date even if the periodic timer hasn't fired yet.
    _fetchCurrentPlaceName();
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _loadData() async {
    var data = await _authService.getEmployeeData();
    if (data == null || data['profile_picture_url'] == null) {
      final fresh = await ApiService().getMyProfile();
      if (fresh != null) data = fresh;
    }
    final d = data;
    if (d != null && mounted) {
      setState(() {
        _employeeName = d['name'] ?? 'Employee';
        _profilePictureUrl = d['profile_picture_url'] as String?;
      });
    }
  }

  /// Session duration in seconds. Prefers duration_seconds (exact); else from timestamps (rounded); else total_hours.
  static int _sessionDurationSeconds(Map<String, dynamic> sess) {
    final dur = sess['duration_seconds'];
    if (dur is int) return dur;
    if (dur is num) return dur.round();

    final startStr = sess['start_time'] as String?;
    final endStr = sess['end_time'] as String?;
    if (startStr != null &&
        startStr.isNotEmpty &&
        endStr != null &&
        endStr.isNotEmpty) {
      try {
        final start = DateTime.parse(startStr);
        final end = DateTime.parse(endStr);
        final startLocal = start.isUtc ? start.toLocal() : start;
        final endLocal = end.isUtc ? end.toLocal() : end;
        return ((endLocal.millisecondsSinceEpoch - startLocal.millisecondsSinceEpoch) / 1000).round();
      } catch (_) {}
    }
    final hours = (sess['total_hours'] is num)
        ? (sess['total_hours'] as num).toDouble()
        : 0.0;
    return (hours * 3600).round();
  }

  /// Fetch today's attendance and set _todayBaseSeconds, _todayDate, and open session if any.
  /// Uses start_time/end_time for duration (same as My Attendance) so Home and My Attendance match.
  /// Requests a 3-day window (yesterday–tomorrow) so sessions stored under server date are included (timezone-safe).
  /// Ignores stale completions when multiple calls overlap (e.g. date change at midnight).
  Future<void> _loadTodayDutyTime() async {
    final gen = ++_loadTodayDutyTimeGeneration;
    final sw = Stopwatch()..start();
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
    final tomorrowStr = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));
    final result = await ApiService().getMyAttendance(
      startDate: yesterdayStr,
      endDate: tomorrowStr,
    );
    if (!mounted || gen != _loadTodayDutyTimeGeneration) return;
    final loadError = result['error'] as String?;
    final byDate = result['by_date'] as List<dynamic>?;
    int baseSeconds = 0;
    DateTime? openSessionStart;
    if (byDate != null && byDate.isNotEmpty) {
      for (final entry in byDate) {
        final map = entry as Map<String, dynamic>?;
        if (map == null) continue;
        final dateStr = map['date'] as String?;
        if (dateStr != todayStr) continue;
        final sessions = map['sessions'] as List<dynamic>?;
        if (sessions == null) continue;
        for (final s in sessions) {
          final sess = s as Map<String, dynamic>?;
          if (sess == null) continue;
          final endTime = sess['end_time'];
          if (endTime == null || endTime.toString().isEmpty) {
            final startStr = sess['start_time'] as String?;
            if (startStr != null && startStr.isNotEmpty) {
              try {
                final dt = DateTime.parse(startStr);
                openSessionStart = dt.isUtc ? dt.toLocal() : dt;
              } catch (_) {}
            }
          } else {
            baseSeconds += _sessionDurationSeconds(sess);
          }
        }
        break;
      }
    }
    if (gen != _loadTodayDutyTimeGeneration) return;
    sw.stop();
    if (kDebugMode) {
      // Debug-only perf log
      // ignore: avoid_print
      print('HOME: _loadTodayDutyTime completed in ${sw.elapsedMilliseconds}ms');
    }
    setState(() {
      _dutyTimeLoadError = loadError;
      if (loadError != null) {
        // Preserve last known state for same day so we don't show wrong Offline/Start duty on network failure.
        final today = DateTime(now.year, now.month, now.day);
        if (_dutyStartTime != null &&
            _dutyStartTime!.year == today.year &&
            _dutyStartTime!.month == today.month &&
            _dutyStartTime!.day == today.day) {
          // Keep _dutyStartTime, _todayBaseSeconds, _todayDate unchanged
          return;
        }
      }
      _todayBaseSeconds = baseSeconds;
      _todayDate = DateTime(now.year, now.month, now.day);
      if (openSessionStart != null) {
        _dutyStartTime = openSessionStart;
      } else {
        _dutyStartTime = null;
      }
    });
    await _checkServiceStatus();
    // If server says no active session (e.g. auto-end at midnight or 9h) but tracking is still running, stop it.
    if (mounted && _dutyStartTime == null && _isTracking) {
      await _locationService.stopTracking();
      await LocationService.clearLastSentLocation();
      if (mounted) await _checkServiceStatus();
    }
  }

  static const Duration _serviceStatusCheckTimeout = Duration(seconds: 5);

  Future<void> _checkServiceStatus() async {
    try {
      final isRunning = await FlutterBackgroundService()
          .isRunning()
          .timeout(_serviceStatusCheckTimeout);
      if (mounted) {
        setState(() {
          _isTracking = isRunning;
          _statusCheckError = false;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _statusCheckError = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _statusCheckError = true);
      }
    }
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final hasNetwork = result.isNotEmpty &&
          result.any((r) => r != ConnectivityResult.none);
      if (mounted) {
        setState(() => _hasNetwork = hasNetwork);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hasNetwork = false);
      }
    }
  }

  Future<void> _onRefresh() async {
    // Phase 7: Show throttle message from previous sync if any
    final throttleMsg = ApiService.lastTrackingThrottleMessage;
    if (throttleMsg != null && throttleMsg.isNotEmpty && mounted && context.mounted) {
      ApiService.lastTrackingThrottleMessage = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(throttleMsg)),
      );
    }
    // Run sync in background so refresh does not block UI (up to 90s); do not await
    unawaited((() async {
      final hasOffline = await LocationService.hasPendingOfflineData();
      if (hasOffline && mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline data syncing in background')),
        );
      }
      await LocationService.syncOfflineData();
    })());
    await _checkConnectivity();
    await _loadData();
    await _loadTodayDutyTime();
    await _checkServiceStatus();
    // If background service was killed (Android Doze / battery optimisation) but
    // there is still an open duty session, restart it now so the user does not have
    // to force-kill and reopen the app to recover the "Inactive" indicator.
    if (!mounted) return;
    if (!_isTracking && _dutyStartTime != null) {
      await _locationService.startTracking();
      await Future.delayed(const Duration(seconds: 1));
      await _checkServiceStatus();
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tracking resumed')),
        );
      }
    }
  }

  Future<void> _fetchCurrentPlaceName() async {
    if (_isRefreshingLocation) return;
    if (mounted) setState(() => _isRefreshingLocation = true);

    // Prefer the last known OS-cached position (no GPS hardware activation needed).
    // Discard cached position if older than 30 minutes — use a fresh fix instead.
    // Fall back to fresh fix if no cached position is available at all.
    Position? position;
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inMinutes <= AppConfig.lastKnownPositionMaxAgeMinutes) {
          position = lastKnown;
        }
      }
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      if (mounted) setState(() => _isRefreshingLocation = false);
      // GPS fail — keep previous name unchanged
      return;
    }

    // Step 1: Backend (preferred – same as dashboard marker popup)
    try {
      final resolved = await ApiService().resolveAddress(
        position.latitude,
        position.longitude,
      );
      if (resolved != null &&
          resolved.isNotEmpty &&
          !_isCoordinatesOnly(resolved) &&
          mounted) {
        setState(() {
          _currentPlaceName = resolved;
          _isRefreshingLocation = false;
        });
        return;
      }
    } catch (_) {}

    // Step 2: Nominatim direct (off main isolate)
    try {
      final lat = position.latitude;
      final lng = position.longitude;
      final nominatimName =
          await Isolate.run(() => _nominatimReverseGeocode(lat, lng));
      if (nominatimName != null &&
          nominatimName.isNotEmpty &&
          mounted) {
        setState(() {
          _currentPlaceName = nominatimName;
          _isRefreshingLocation = false;
        });
        return;
      }
    } catch (_) {}

    // Step 3: Android/iOS platform geocoder (10 s timeout — can hang without network)
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 10));
      String placeName = _currentPlaceName.isEmpty ? '—' : _currentPlaceName;
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final subLocality = p.subLocality?.trim() ?? '';
        final locality = p.locality?.trim() ?? '';
        final name = p.name?.trim() ?? '';
        final thoroughfare = p.thoroughfare?.trim() ?? '';
        final subAdmin = p.subAdministrativeArea?.trim() ?? '';
        final admin = p.administrativeArea?.trim() ?? '';

        if (subLocality.isNotEmpty) {
          placeName = locality.isNotEmpty &&
                  locality != subLocality &&
                  !locality
                      .toLowerCase()
                      .contains(subLocality.toLowerCase())
              ? '$subLocality, $locality'
              : subLocality;
        } else if (name.isNotEmpty && name != locality && name != admin) {
          placeName = locality.isNotEmpty ? '$name, $locality' : name;
        } else if (thoroughfare.isNotEmpty) {
          placeName =
              locality.isNotEmpty ? '$thoroughfare, $locality' : thoroughfare;
        } else if (locality.isNotEmpty) {
          placeName =
              admin.isNotEmpty && admin != locality ? '$locality, $admin' : locality;
        } else if (subAdmin.isNotEmpty) {
          placeName = subAdmin;
        } else if (admin.isNotEmpty) {
          placeName = admin;
        }
      }
      if (mounted) {
        setState(() {
          _currentPlaceName = placeName;
          _isRefreshingLocation = false;
        });
      }
      return;
    } catch (_) {}

    // All failed but GPS worked — keep previous name (or '—')
    if (mounted) {
      setState(() {
        _isRefreshingLocation = false;
      });
    }
  }

  static const Duration _dutyDialogTimeout = Duration(seconds: 25);

  void _showDutyLoadingDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, style: Theme.of(ctx).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleTracking() async {
    if (_isDutyOperationInProgress) return;
    _isDutyOperationInProgress = true;
    if (mounted) setState(() {});

    final service = FlutterBackgroundService();
    final onDuty = _dutyStartTime != null;

    bool dialogShown = false;
    try {
      if (onDuty) {
        if (mounted && context.mounted) {
          _showDutyLoadingDialog(context, 'Ending duty...');
          dialogShown = true;
        }
        bool success = false;
        bool hadException = false;
        try {
          await (() async {
            final position = await _getPositionForDuty();
            if (position == null) return;
            final address = _currentPlaceName.isEmpty || _currentPlaceName == '—' ? null : _currentPlaceName;
            success = await ApiService().endDuty(
              latitude: position.latitude,
              longitude: position.longitude,
              address: address,
            );
          }()).timeout(_dutyDialogTimeout);
        } on TimeoutException {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Took too long. Check connection and try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (e) {
          success = false;
          hadException = true;
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not end duty. Check connection and try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        if (success) {
          await _locationService.stopTracking();
          await LocationService.clearLastSentLocation();
          if (mounted) {
            setState(() {
              _isTracking = false;
              _dutyStartTime = null;
            });
            await _loadTodayDutyTime();
          }
        } else if (!hadException && mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to end duty. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        final hasLocation = await _locationService.requestLocationPermissionIfNeeded();
        if (!hasLocation && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required to start duty. Enable it in Settings.'),
            ),
          );
          return;
        }
        if (await AndroidSdk.isAtLeast33 && await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
        if (mounted && context.mounted) {
          _showDutyLoadingDialog(context, 'Starting duty...');
          dialogShown = true;
        }
        try {
          await (() async {
            Map<String, dynamic>? startData;
            final position = await _getPositionForDuty();
            if (position == null) {
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location unavailable. Try again.')),
                );
              }
              return;
            }
            try {
              final address = _currentPlaceName.isEmpty || _currentPlaceName == '—' ? null : _currentPlaceName;
              final localDateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
              startData = await ApiService().startDuty(
                latitude: position.latitude,
                longitude: position.longitude,
                address: address,
                date: localDateStr,
              );
            } catch (_) {}
            await _locationService.startTracking();
            await Future.delayed(const Duration(seconds: 1));
            final started = await service.isRunning();
            if (mounted) {
              DateTime? dutyStart;
              if (started && startData != null) {
                final startTimeStr = startData['start_time'] as String?;
                if (startTimeStr != null && startTimeStr.isNotEmpty) {
                  try {
                    final dt = DateTime.parse(startTimeStr);
                    dutyStart = dt.isUtc ? dt.toLocal() : dt;
                  } catch (_) {}
                }
              }
              if (dutyStart != null && dutyStart.isAfter(DateTime.now())) {
                dutyStart = DateTime.now();
              }
              setState(() {
                _isTracking = started;
                _dutyStartTime = dutyStart;
              });
            }
            if (!started && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not start tracking. Check permissions.')),
              );
            } else if (started && mounted) {
              if (startData == null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Duty started locally. Will sync when connected.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
              final hasBackground = await _locationService.hasBackgroundLocationPermission();
              if (!hasBackground &&
                  await AndroidSdk.isAtLeast29 &&
                  mounted &&
                  context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('For full duty tracking when app is in background, allow location "All the time" in Settings.'),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _fetchCurrentPlaceName();
              });
            }
          }()).timeout(_dutyDialogTimeout);
        } on TimeoutException {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Took too long. Check connection and try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } finally {
      if (dialogShown && mounted && context.mounted) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        setState(() => _isDutyOperationInProgress = false);
      }
    }
  }

  /// Gets current position with 15s timeout; retries once with lower accuracy. Returns null on failure.
  static const Duration _positionTimeout = Duration(seconds: 15);

  Future<Position?> _getPositionForDuty() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(_positionTimeout);
    } on TimeoutException {
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(_positionTimeout);
      } on TimeoutException {
        return null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, colorScheme),
                const SizedBox(height: 24),
                _buildTimeAndStatusCard(context, theme, colorScheme),
                const SizedBox(height: 24),
                _buildQuickActionCards(context, theme, colorScheme),
                const SizedBox(height: 24),
                _buildDutyTimeCard(context, theme, colorScheme),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.12),
            colorScheme.primary.withValues(alpha: 0.04),
            colorScheme.surfaceContainerLowest,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Image.asset(
                  'assets/icon/genesis_icon_foreground.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Genesis Employee',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_greeting()}, $_employeeName',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  backgroundImage: (_profilePictureUrl != null && _profilePictureUrl!.isNotEmpty)
                      ? NetworkImage(_profilePictureUrl!)
                      : null,
                  child: (_profilePictureUrl == null || _profilePictureUrl!.isEmpty)
                      ? Icon(Icons.person, color: colorScheme.onSurfaceVariant, size: 26)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeAndStatusCard(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const _ClockText(),
            const SizedBox(height: 10),
            Text(
              DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _statusCheckError
                    ? colorScheme.outlineVariant.withValues(alpha: 0.2)
                    : (_isTracking ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12)),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _statusCheckError
                      ? colorScheme.outlineVariant.withValues(alpha: 0.5)
                      : (_isTracking
                          ? Colors.green.withValues(alpha: 0.35)
                          : Colors.red.withValues(alpha: 0.35)),
                ),
                boxShadow: _isTracking && !_statusCheckError
                    ? [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.25),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _statusCheckError ? Icons.help_outline : (_isTracking ? Icons.circle : Icons.circle_outlined),
                    color: _statusCheckError ? colorScheme.onSurfaceVariant : (_isTracking ? Colors.green : Colors.red),
                    size: 12,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusCheckError ? 'Status unavailable' : (_isTracking ? 'Tracking: Active' : 'Tracking: Inactive'),
                    style: TextStyle(
                      color: _statusCheckError ? colorScheme.onSurfaceVariant : (_isTracking ? Colors.green : Colors.red),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (!_hasNetwork) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off, size: 14, color: colorScheme.error),
                  const SizedBox(width: 6),
                  Text(
                    'No internet',
                    style: TextStyle(fontSize: 12, color: colorScheme.error, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Divider(height: 20, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current location',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: colorScheme.onSurfaceVariant,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _currentPlaceName.isEmpty ? '—' : _currentPlaceName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Refresh location',
                        child: IconButton(
                          icon: _isRefreshingLocation
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                                )
                              : Icon(Icons.refresh, size: 22, color: colorScheme.primary),
                          onPressed: _isRefreshingLocation
                              ? null
                              : () async {
                                  await _fetchCurrentPlaceName();
                                  if (mounted && context.mounted && !_isRefreshingLocation) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Location refreshed')),
                                    );
                                  }
                                },
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            minimumSize: const Size(44, 44),
                            padding: const EdgeInsets.all(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isDutyOperationInProgress ? null : _toggleTracking,
                icon: Icon(_dutyStartTime != null ? Icons.stop_circle : Icons.play_circle_filled, size: 22),
                label: Text(
                  _dutyStartTime != null ? 'END DUTY' : 'START DUTY',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _dutyStartTime != null ? colorScheme.error : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCards(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildActionButton(
              context,
              title: 'View My\nAttendance',
              subtitle: 'View sessions',
              icon: Icons.calendar_today_outlined,
              color: colorScheme.primary,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AttendanceScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _buildActionButton(
              context,
              title: 'TO-DO\nTask',
              subtitle: 'Tasks & checklist',
              icon: Icons.checklist_outlined,
              color: colorScheme.secondary,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TodoListScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDutyTimeCard(BuildContext context, ThemeData theme, ColorScheme colorScheme) {
    final todayLabel = DateFormat('EEEE, d MMM yyyy').format(DateTime.now());
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.10),
            colorScheme.primary.withValues(alpha: 0.04),
            colorScheme.surface,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Today's Duty Time",
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              todayLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 12),
            _LiveDutyDuration(
              dutyStartTime: _dutyStartTime,
              todayBaseSeconds: _todayBaseSeconds,
              todayDate: _todayDate,
              onDateChange: _loadTodayDutyTime,
            ),
            if (_dutyTimeLoadError != null) ...[
              const SizedBox(height: 12),
              Text(
                _dutyTimeLoadError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  setState(() => _dutyTimeLoadError = null);
                  _loadTodayDutyTime();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the current time, updating only itself every second.
/// Isolating this widget prevents the entire HomeScreen from rebuilding
/// on every tick.
class _ClockText extends StatefulWidget {
  const _ClockText();

  @override
  State<_ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<_ClockText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
    final now = DateTime.now();
    final time = use24
        ? DateFormat('HH:mm:ss').format(now)
        : DateFormat('hh:mm:ss a').format(now);
    final theme = Theme.of(context);
    return Text(
      time,
      style: theme.textTheme.headlineMedium?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Displays the live duty duration, updating only itself every second.
/// Calls [onDateChange] when the calendar date rolls over midnight so the
/// parent can reload today's duty data.
class _LiveDutyDuration extends StatefulWidget {
  final DateTime? dutyStartTime;
  final int todayBaseSeconds;
  final DateTime todayDate;
  final VoidCallback onDateChange;

  const _LiveDutyDuration({
    required this.dutyStartTime,
    required this.todayBaseSeconds,
    required this.todayDate,
    required this.onDateChange,
  });

  @override
  State<_LiveDutyDuration> createState() => _LiveDutyDurationState();
}

class _LiveDutyDurationState extends State<_LiveDutyDuration> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.day != widget.todayDate.day ||
          now.month != widget.todayDate.month ||
          now.year != widget.todayDate.year) {
        widget.onDateChange();
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int totalSeconds = widget.todayBaseSeconds;
    if (widget.dutyStartTime != null) {
      final live = DateTime.now().difference(widget.dutyStartTime!).inSeconds;
      if (live > 0) totalSeconds += live;
      if (totalSeconds < 0) totalSeconds = 0;
    }
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    final theme = Theme.of(context);
    return Text(
      '${h}h ${m}m ${s}s',
      style: theme.textTheme.headlineMedium?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

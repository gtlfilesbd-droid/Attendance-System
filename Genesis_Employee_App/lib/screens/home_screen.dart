import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../services/foreground_refresh_service.dart';
import '../services/push_notification_service.dart';
import 'attendance_screen.dart';
import 'route_map_screen.dart';
import 'profile_screen.dart';

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();

  bool _isTracking = false;
  String _currentTime = '';
  String _currentPlaceName = '—';
  String _employeeName = '';
  String? _profilePictureUrl;
  DateTime? _dutyStartTime;
  String _liveDutyDuration = '0h 0m 0s';
  int _todayBaseSeconds = 0;
  DateTime _todayDate = DateTime(1970, 1, 1);
  Timer? _timer;
  Timer? _placeRefreshTimer;
  int _loadTodayDutyTimeGeneration = 0;
  /// Set when getMyAttendance fails so duty time card can show error + retry.
  String? _dutyTimeLoadError;
  /// Set when background service status check fails (e.g. exception).
  bool _statusCheckError = false;
  /// Network connectivity (connectivity_plus; does not guarantee internet reachability).
  bool _hasNetwork = true;
  bool _isRefreshingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ForegroundRefreshService().addListener(_onForegroundRefresh);
    _loadData();
    PushNotificationService().registerFCMToken();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        _startTimer();
        // Load duty state first; then start or stop tracking based on open session (enterprise: single source of truth from backend)
        await _loadTodayDutyTime();
        if (!mounted) return;
        if (_dutyStartTime != null) {
          await _locationService.startTracking();
          await _checkServiceStatus();
        } else {
          await _locationService.stopTracking();
          await _checkServiceStatus();
        }
        if (mounted) await _checkConnectivity();
      }
    });
    _fetchCurrentPlaceName().then((_) {
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
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _placeRefreshTimer?.cancel();
    super.dispose();
  }

  void _onForegroundRefresh() {
    if (!mounted) return;
    _loadData().then((_) {
      if (!mounted) return;
      _loadTodayDutyTime();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    await _checkServiceStatus();
    if (!mounted) return;
    // If we have open session but service was killed (e.g. by Android), restart tracking
    if (!_isTracking && _dutyStartTime != null) {
      await _locationService.startTracking();
      await _checkServiceStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tracking resumed')),
        );
      }
    }
  }

  void _startTimer() {
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
    });
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _formatDurationHMS(int totalSeconds) {
    if (totalSeconds < 0) return '0h 0m 0s';
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  void _updateTime() {
    if (!mounted || !context.mounted) return;
    final now = DateTime.now();
    final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
    // Date change: refetch today's duty for new date
    if (now.year != _todayDate.year ||
        now.month != _todayDate.month ||
        now.day != _todayDate.day) {
      _loadTodayDutyTime();
      return;
    }
    int totalSeconds = _todayBaseSeconds;
    if (_dutyStartTime != null) {
      final liveSeconds = now.difference(_dutyStartTime!).inSeconds;
      if (liveSeconds > 0) totalSeconds += liveSeconds;
      if (totalSeconds < 0) totalSeconds = 0;
    }
    final liveDuration = _formatDurationHMS(totalSeconds);
    setState(() {
      _currentTime = use24
          ? DateFormat('HH:mm:ss').format(now)
          : DateFormat('hh:mm:ss a').format(now);
      _liveDutyDuration = liveDuration;
    });
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
      }
    });
    await _checkServiceStatus();
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
    ApiService().initialize();
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
  }

  Future<void> _fetchCurrentPlaceName() async {
    if (_isRefreshingLocation) return;
    if (mounted) {
      setState(() => _isRefreshingLocation = true);
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      // Prefer backend resolve-address (same format as dashboard marker popup)
      final resolved = await ApiService().resolveAddress(
        position.latitude,
        position.longitude,
      );
      if (resolved != null && resolved.isNotEmpty && mounted) {
        setState(() {
          _currentPlaceName = resolved;
          _isRefreshingLocation = false;
        });
        return;
      }
      // Run Nominatim HTTP + parse off main isolate to avoid UI jank
      final lat = position.latitude;
      final lng = position.longitude;
      final nominatimName = await Isolate.run(() => _nominatimReverseGeocode(lat, lng));
      if (nominatimName != null && nominatimName.isNotEmpty && mounted) {
        setState(() {
          _currentPlaceName = nominatimName;
          _isRefreshingLocation = false;
        });
        return;
      }
      // Fall back to platform geocoding (runs on main isolate)
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      String placeName = '—';
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final subLocality = p.subLocality?.trim() ?? '';
        final locality = p.locality?.trim() ?? '';
        final name = p.name?.trim() ?? '';
        final thoroughfare = p.thoroughfare?.trim() ?? '';
        final subAdmin = p.subAdministrativeArea?.trim() ?? '';
        final admin = p.administrativeArea?.trim() ?? '';

        if (subLocality.isNotEmpty) {
          placeName = locality.isNotEmpty && locality != subLocality && !locality.toLowerCase().contains(subLocality.toLowerCase())
              ? '$subLocality, $locality'
              : subLocality;
        } else if (name.isNotEmpty && name != locality && name != admin) {
          placeName = locality.isNotEmpty ? '$name, $locality' : name;
        } else if (thoroughfare.isNotEmpty) {
          placeName = locality.isNotEmpty ? '$thoroughfare, $locality' : thoroughfare;
        } else if (locality.isNotEmpty) {
          placeName = admin.isNotEmpty && admin != locality ? '$locality, $admin' : locality;
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentPlaceName = 'Location unavailable';
          _isRefreshingLocation = false;
        });
      }
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
    final service = FlutterBackgroundService();
    // Use duty state (open session) as source of truth for action, not just service.isRunning()
    final onDuty = _dutyStartTime != null;
    final isRunning = await service.isRunning();

    if (onDuty) {
      // End duty: show loading, get position, send to backend; only stop tracking if backend confirms success
      if (mounted && context.mounted) {
        _showDutyLoadingDialog(context, 'Ending duty...');
      }
      bool success = false;
      bool hadException = false;
      try {
        await (() async {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
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
          if (mounted) {
            setState(() {
              _liveDutyDuration = _formatDurationHMS(_todayBaseSeconds);
            });
          }
        }
      } else if (!hadException && mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to end duty. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (mounted && context.mounted) {
        Navigator.of(context).pop();
      }
    } else {
      // Start duty: ensure location permission first
      final hasLocation = await _locationService.requestLocationPermissionIfNeeded();
      if (!hasLocation && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to start duty. Enable it in Settings.'),
          ),
        );
        return;
      }
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      if (mounted && context.mounted) {
        _showDutyLoadingDialog(context, 'Starting duty...');
      }
      try {
        await (() async {
          Map<String, dynamic>? startData;
          try {
            final position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
            );
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
            if (!hasBackground && mounted && context.mounted) {
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
      } finally {
        if (mounted && context.mounted) {
          Navigator.of(context).pop();
        }
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              Icons.business_center,
              size: 26,
              color: colorScheme.primary,
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
                      fontWeight: FontWeight.w600,
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
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              _currentTime,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
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
                borderRadius: BorderRadius.circular(12),
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
                onPressed: _toggleTracking,
                icon: Icon(_dutyStartTime != null ? Icons.stop_circle : Icons.play_circle_filled, size: 22),
                label: Text(
                  _dutyStartTime != null ? 'END DUTY' : 'START DUTY',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _dutyStartTime != null ? colorScheme.error : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 3,
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
              title: "View Route",
              subtitle: "Select date to view",
              icon: Icons.route_outlined,
              color: Colors.orange.shade700,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RouteMapScreen()),
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
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
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
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.primary.withValues(alpha: 0.04),
          ],
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
                fontWeight: FontWeight.w500,
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
            Text(
              _liveDutyDuration.isEmpty ? '0h 0m 0s' : _liveDutyDuration,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
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

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final LocationService _locationService = LocationService();

  bool _isTracking = false;
  String _currentTime = '';
  String _currentPlaceName = '—';
  String _employeeName = '';
  String? _profilePictureUrl;
  Timer? _timer;
  Timer? _placeRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startTimer();
    });
    // Stop any leftover tracking from a previous session so tracking is off until user presses Start Duty
    _locationService.stopTracking().then((_) {
      if (mounted) _checkServiceStatus();
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
    _timer?.cancel();
    _placeRefreshTimer?.cancel();
    super.dispose();
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

  void _updateTime() {
    if (mounted && context.mounted) {
      final now = DateTime.now();
      final use24 = MediaQuery.of(context).alwaysUse24HourFormat;
      setState(() {
        _currentTime = use24
            ? DateFormat('HH:mm:ss').format(now)
            : DateFormat('hh:mm:ss a').format(now);
      });
    }
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

  Future<void> _checkServiceStatus() async {
    final isRunning = await FlutterBackgroundService().isRunning();
    if (mounted) {
      setState(() {
        _isTracking = isRunning;
      });
    }
  }

  Future<void> _fetchCurrentPlaceName() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final nominatimName = await _nominatimReverseGeocode(
        position.latitude,
        position.longitude,
      );
      if (nominatimName != null && nominatimName.isNotEmpty && mounted) {
        setState(() {
          _currentPlaceName = nominatimName;
        });
        return;
      }
      // Fall back to platform geocoding
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
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentPlaceName = 'Location unavailable';
        });
      }
    }
  }

  Future<void> _toggleTracking() async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();

    if (isRunning) {
      // End duty: get current position and send to backend, then stop tracking
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        final address = _currentPlaceName.isEmpty || _currentPlaceName == '—' ? null : _currentPlaceName;
        await ApiService().endDuty(
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
        );
      } catch (_) {}
      await _locationService.stopTracking();
      if (mounted) setState(() => _isTracking = false);
    } else {
      // Start duty: ensure location permission first (required for foreground service on Android 14+)
      final hasLocation = await _locationService.requestLocationPermissionIfNeeded();
      if (!hasLocation && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to start duty. Enable it in Settings.'),
          ),
        );
        return;
      }
      // Optional: ensure notification permission for foreground notification (Android 13+)
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
      // Start duty: get current position, send to backend, then start tracking
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        final address = _currentPlaceName.isEmpty || _currentPlaceName == '—' ? null : _currentPlaceName;
        await ApiService().startDuty(
          latitude: position.latitude,
          longitude: position.longitude,
          address: address,
        );
      } catch (_) {}
      await _locationService.startTracking();
      await Future.delayed(const Duration(seconds: 1));
      final started = await service.isRunning();
      if (mounted) setState(() => _isTracking = started);
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start tracking. Check permissions.')),
        );
      } else if (started && mounted) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, colorScheme),
              const SizedBox(height: 28),
              _buildTimeAndStatusCard(context, theme, colorScheme),
              const SizedBox(height: 28),
              _buildQuickActionCards(context, theme, colorScheme),
              const SizedBox(height: 24),
            ],
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
              size: 28,
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
                  radius: 24,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  backgroundImage: (_profilePictureUrl != null && _profilePictureUrl!.isNotEmpty)
                      ? NetworkImage(_profilePictureUrl!)
                      : null,
                  child: (_profilePictureUrl == null || _profilePictureUrl!.isEmpty)
                      ? Icon(Icons.person, color: colorScheme.onSurfaceVariant, size: 28)
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
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              _currentTime,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              DateFormat('EEEE, MMMM d, y').format(DateTime.now()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _isTracking ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
                boxShadow: _isTracking
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
                    _isTracking ? Icons.circle : Icons.circle_outlined,
                    color: _isTracking ? Colors.green : Colors.red,
                    size: 12,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isTracking ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: _isTracking ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Divider(height: 24, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
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
                          icon: Icon(Icons.refresh, size: 22, color: colorScheme.primary),
                          onPressed: () async {
                            await _fetchCurrentPlaceName();
                            if (mounted && context.mounted) {
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
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toggleTracking,
                icon: Icon(_isTracking ? Icons.stop_circle : Icons.play_circle_filled, size: 22),
                label: Text(
                  _isTracking ? 'END DUTY' : 'START DUTY',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTracking ? colorScheme.error : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
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
              title: "View Today's\nRoute",
              subtitle: "See today's path",
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
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

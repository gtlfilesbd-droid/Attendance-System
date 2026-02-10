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
import 'login_screen.dart';
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
  Timer? _timer;
  Timer? _placeRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startTimer();
    // Stop any leftover tracking from a previous session so tracking is off until user presses Start Duty
    _locationService.stopTracking().then((_) {
      if (mounted) _checkServiceStatus();
    });
    _fetchCurrentPlaceName().then((_) {
      if (mounted) {
        _placeRefreshTimer = Timer.periodic(
          Duration(minutes: AppConfig.placeNameRefreshMinutes),
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
    final data = await _authService.getEmployeeData();
    if (data != null && mounted) {
      setState(() {
        _employeeName = data['name'] ?? 'Employee';
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
        if (!hasBackground) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Genesis Employee'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hello, $_employeeName',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            
            // Tracking Status Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      _currentTime,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      DateFormat('EEEE, MMMM d, y').format(DateTime.now()),
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isTracking ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isTracking ? Colors.green : Colors.red,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isTracking ? Icons.check_circle : Icons.stop_circle,
                            color: _isTracking ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isTracking ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: _isTracking ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.blue, size: 20),
                          onPressed: () async {
                            await _fetchCurrentPlaceName();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Location refreshed')),
                              );
                            }
                          },
                          tooltip: 'Refresh location',
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.location_on, color: Colors.grey[600], size: 20),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _currentPlaceName.isEmpty ? '—' : _currentPlaceName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Current location',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _toggleTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isTracking ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isTracking ? 'END DUTY' : 'START DUTY',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    context,
                    'View My\nAttendance',
                    Icons.calendar_today,
                    Colors.blue,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AttendanceScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionButton(
                    context,
                    "View Today's\nRoute",
                    Icons.map,
                    Colors.orange,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RouteMapScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 40),
            
            // Bottom Info
            const Center(
              child: Text(
                "Your location is tracked while duty is active",
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

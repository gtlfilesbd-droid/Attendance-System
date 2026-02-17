import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/route_processing.dart';

class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({super.key});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<LatLng> _routePoints = [];
  List<Marker> _markers = [];
  double _totalDistanceKm = 0.0;
  /// Raw count from API for "Points Logged" label.
  int _rawPointsCount = 0;
  final MapController _mapController = MapController();
  static const double _minZoom = 2.0;
  static const double _maxZoom = 19.0;
  /// Zoom level for button state; avoid reading MapController.camera before it is initialized.
  double _currentZoom = 13.0;
  /// Selected date for route; default today.
  DateTime _selectedDate = DateTime.now();
  /// Start time for route filter (HH:mm:ss); default 00:00:00.
  TimeOfDay _startTime = const TimeOfDay(hour: 0, minute: 0);
  /// End time for route filter (HH:mm:ss); default 23:59:00.
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 59);
  String? _loadError;

  void _zoomIn() {
    final camera = _mapController.camera;
    final newZoom = (camera.zoom + 1).clamp(_minZoom, _maxZoom);
    _mapController.move(camera.center, newZoom);
  }

  void _zoomOut() {
    final camera = _mapController.camera;
    final newZoom = (camera.zoom - 1).clamp(_minZoom, _maxZoom);
    _mapController.move(camera.center, newZoom);
  }

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final employeeData = await AuthService().getEmployeeData();
    final employeeId = employeeData?['id']?.toString() ?? employeeData?['employee_id']?.toString();
    if (employeeId == null || employeeId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Unable to load route';
          _routePoints = [];
          _markers = [];
          _totalDistanceKm = 0;
          _rawPointsCount = 0;
        });
      }
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final startTimeStr = _timeOfDayToHhMmSs(_startTime);
    final endTimeStr = _timeOfDayToHhMmSs(_endTime);
    final locations = await _apiService.getMyRoute(
      employeeId: employeeId,
      date: dateStr,
      startTime: startTimeStr,
      endTime: endTimeStr,
    );
    if (!mounted) return;

    // Process route: filter, dedupe, smooth; get points and distance for display
    final processed = processRouteForDisplay(locations);
    final points = processed.points;
    double distance = processed.distanceKm;
    if (points.length >= 2 && distance == 0) {
      const distanceCalculator = Distance();
      distance = 0.0;
      for (int i = 0; i < points.length - 1; i++) {
        distance += distanceCalculator.as(LengthUnit.Kilometer, points[i], points[i + 1]);
      }
    }

    // Build markers: only start and end
    List<Marker> markers = [];
    if (points.length >= 2) {
      final firstTimestamp = locations.isNotEmpty ? locations.first['timestamp']?.toString() : null;
      final lastTimestamp = locations.isNotEmpty ? locations.last['timestamp']?.toString() : null;
      markers.add(
        Marker(
          point: points.first,
          width: 40,
          height: 40,
          child: Tooltip(
            message: firstTimestamp != null ? 'Start ${_formatTimeIso(firstTimestamp)}' : 'Start',
            child: const Icon(Icons.trip_origin, color: Colors.green, size: 32),
          ),
        ),
      );
      markers.add(
        Marker(
          point: points.last,
          width: 40,
          height: 40,
          child: Tooltip(
            message: lastTimestamp != null ? 'End ${_formatTimeIso(lastTimestamp)}' : 'End',
            child: const Icon(Icons.location_on, color: Colors.red, size: 32),
          ),
        ),
      );
    } else if (points.length == 1) {
      markers.add(
        Marker(
          point: points.first,
          width: 40,
          height: 40,
          child: const Tooltip(
            message: 'Start / End',
            child: Icon(Icons.location_on, color: Colors.blue, size: 32),
          ),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _routePoints = points;
        _markers = markers;
        _totalDistanceKm = distance;
        _rawPointsCount = locations.length;
        _isLoading = false;
        if (points.isNotEmpty) {
          _currentZoom = 14.0;
        }
      });

      if (points.isNotEmpty) {
        _mapController.move(points.last, 14.0);
      }
    }
  }
  
  /// Format TimeOfDay as HH:mm:ss for API.
  String _timeOfDayToHhMmSs(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null && mounted) {
      setState(() => _startTime = picked);
      _fetchRoute();
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null && mounted) {
      setState(() => _endTime = picked);
      _fetchRoute();
    }
  }

  /// Format ISO timestamp to time string (no BuildContext, safe after async).
  String _formatTimeIso(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final local = dt.isUtc ? dt.toLocal() : dt;
      return DateFormat.Hm().format(local);
    } catch (e) {
      return '';
    }
  }

  Widget _buildZoomControls(BuildContext context) {
    final zoom = _currentZoom.clamp(_minZoom, _maxZoom);
    final canZoomIn = zoom < _maxZoom;
    final canZoomOut = zoom > _minZoom;
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: canZoomIn ? _zoomIn : null,
            tooltip: canZoomIn ? 'Zoom in' : 'Maximum zoom level reached',
          ),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: canZoomOut ? _zoomOut : null,
            tooltip: canZoomOut ? 'Zoom out' : 'Minimum zoom level reached',
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchRoute();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route'),
      ),
      body: Column(
        children: [
          Material(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Date:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: _isLoading ? null : _pickDate,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 20, color: colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('EEEE, d MMM yyyy').format(_selectedDate),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, color: colorScheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'From:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _isLoading ? null : _pickStartTime,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        'To:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: _isLoading ? null : _pickEndTime,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: colorScheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time, size: 18, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                  ? Center(child: Text(_loadError!, style: TextStyle(color: colorScheme.error)))
                  : _routePoints.isEmpty
                  ? Center(
                      child: Text(
                        "No route data for ${DateFormat('EEEE, d MMM yyyy').format(_selectedDate)}",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _routePoints.isNotEmpty 
                                ? _routePoints.last 
                                : const LatLng(23.8103, 90.4125),
                            initialZoom: 13.0,
                            onPositionChanged: (camera, hasGesture) {
                              if (mounted) {
                                setState(() {
                                  _currentZoom = camera.zoom ?? _currentZoom;
                                });
                              }
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.genesis.employee_app',
                            ),
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _routePoints,
                                  color: Colors.blue,
                                  strokeWidth: 4.0,
                                ),
                              ],
                            ),
                            MarkerLayer(markers: _markers),
                          ],
                        ),
                        Positioned(
                          right: 16,
                          top: 16,
                          child: _buildZoomControls(context),
                        ),
                      ],
                    ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Distance Traveled',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${_totalDistanceKm.toStringAsFixed(2)} km',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Points Logged',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '$_rawPointsCount',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Route screen: orchestration only — state, fetch, filters, and child widgets
// (filters bar, map area, stats bar, playback bar, error/empty views). See plan §9.
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'route/route_animation_controller.dart';
import 'route/route_playback_controller.dart';
import 'route/widgets/route_animated_marker.dart';
import 'route/widgets/route_empty_view.dart';
import 'route/widgets/route_error_view.dart';
import 'route/widgets/route_map_area.dart';
import 'route/widgets/route_playback_bar.dart';
import 'route/widgets/route_stats_bar.dart';
import 'route/widgets/route_timeline_list.dart';
import '../models/route_point.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/foreground_refresh_service.dart';
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
  bool _isRefreshing = false;
  int _fetchRouteRequestId = 0;
  /// When play was started; used to show SnackBar if playback ends immediately (no time data).
  DateTime? _playStartedAt;

  late final RouteAnimationController _animationController;
  late final RoutePlaybackController _playbackController;

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
    _animationController = RouteAnimationController();
    _playbackController = RoutePlaybackController(_animationController);
    _playbackController.addListener(_onPlaybackChanged);
    ForegroundRefreshService().addListener(_onForegroundRefresh);
    _fetchRoute();
  }

  @override
  void dispose() {
    _playbackController.removeListener(_onPlaybackChanged);
    _playbackController.pause();
    ForegroundRefreshService().removeListener(_onForegroundRefresh);
    super.dispose();
  }

  void _onPlaybackChanged() {
    if (!_playbackController.isPlaying && _playStartedAt != null) {
      final elapsed = DateTime.now().difference(_playStartedAt!);
      final atEnd = _playbackController.currentPointIndex >= _playbackController.totalPoints - 1;
      if (atEnd && _playbackController.totalPoints >= 2 && elapsed.inMilliseconds < 400 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route has no time data; playback skipped.')),
        );
      }
      _playStartedAt = null;
    }
  }

  void _onForegroundRefresh() {
    if (!mounted) return;
    _playbackController.pause();
    _playbackController.reset();
    _fetchRoute();
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      _playbackController.pause();
      _playbackController.reset();
      ApiService().initialize();
      await _fetchRoute();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _fetchRoute() async {
    final requestId = ++_fetchRouteRequestId;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final employeeData = await AuthService().getEmployeeData();
    if (requestId != _fetchRouteRequestId) return;
    final employeeId = employeeData?['id']?.toString() ?? employeeData?['employee_id']?.toString();
    if (employeeId == null || employeeId.isEmpty) {
      if (mounted && requestId == _fetchRouteRequestId) {
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
    late final List<dynamic> locations;
    late final double distanceFromApi;
    try {
      final response = await _apiService.getMyRouteWithMeta(
        employeeId: employeeId,
        date: dateStr,
        startTime: startTimeStr,
        endTime: endTimeStr,
      );
      locations = response.locations;
      distanceFromApi = response.distanceKm ?? -1.0; // Use backend distance when available
    } catch (e) {
      if (mounted && requestId == _fetchRouteRequestId) {
        setState(() {
          _isLoading = false;
          _loadError = "Couldn't load route. Check connection.";
          _routePoints = [];
          _markers = [];
          _totalDistanceKm = 0;
          _rawPointsCount = 0;
        });
      }
      return;
    }
    if (!mounted || requestId != _fetchRouteRequestId) return;

    // Process route with time for playback and stats
    final processed = processRouteForDisplayWithTime(locations);
    final points = processed.points;
    final pointsWithTime = processed.pointsWithTime;
    double distance = processed.distanceKm;
    if (distanceFromApi >= 0) {
      distance = distanceFromApi; // Prefer backend distance when available
    } else if (points.length >= 2 && distance == 0) {
      const distanceCalculator = Distance();
      distance = 0.0;
      for (int i = 0; i < points.length - 1; i++) {
        distance += distanceCalculator.as(LengthUnit.Kilometer, points[i], points[i + 1]);
      }
    }

    // Build markers: start and end with timestamps from pointsWithTime
    List<Marker> markers = _buildStartEndMarkers(points, pointsWithTime);

    if (mounted && requestId == _fetchRouteRequestId) {
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
      _playbackController.setRoute(pointsWithTime);
      if (points.isNotEmpty) {
        _mapController.move(points.last, 14.0);
      }
    }
  }

  List<Marker> _buildStartEndMarkers(List<LatLng> points, List<RoutePointWithTime> pointsWithTime) {
    List<Marker> markers = [];
    if (points.length >= 2) {
      final startTime = pointsWithTime.isNotEmpty ? pointsWithTime.first.timestamp : null;
      final endTime = pointsWithTime.length > 1 ? pointsWithTime.last.timestamp : null;
      final startLabel = startTime != null ? 'Start ${DateFormat.Hm().format(startTime)}' : 'Start';
      final endLabel = endTime != null ? 'End ${DateFormat.Hm().format(endTime)}' : 'End';
      markers.add(
        Marker(
          point: points.first,
          width: 40,
          height: 40,
          child: Tooltip(
            message: startLabel,
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
            message: endLabel,
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
    return markers;
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
        actions: [
          IconButton(
            icon: _isRefreshing
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.iconTheme.color ?? colorScheme.onSurface,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _onRefresh,
            tooltip: 'Refresh route',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters bar (plan §9: date, from/to time)
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
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _loadError != null
                            ? RouteErrorView(
                                message: _loadError!,
                                onRetry: _fetchRoute,
                                isLoading: _isLoading,
                              )
                            : _routePoints.isEmpty
                              ? RouteEmptyView(
                                  dateLabel: DateFormat('EEEE, d MMM yyyy').format(_selectedDate),
                                )
                              : ListenableBuilder(
                                  listenable: _animationController,
                                  builder: (context, _) {
                                    // Plan §5: optionally center map on current point when following playback
                                    if (_playbackController.followPlayback && _playbackController.isPlaying) {
                                      final pos = _animationController.currentPosition;
                                      if (pos != null) {
                                        SchedulerBinding.instance.addPostFrameCallback((_) {
                                          if (mounted) _mapController.move(pos, _mapController.camera.zoom);
                                        });
                                      }
                                    }
                                    return RouteMapArea(
                                      polylinePoints: _routePoints,
                                      staticMarkers: _markers,
                                      animatedMarker: buildRouteAnimatedMarker(_animationController),
                                      mapController: _mapController,
                                      initialCenter: _routePoints.isNotEmpty
                                          ? _routePoints.last
                                          : const LatLng(23.8103, 90.4125),
                                      initialZoom: 13.0,
                                      minZoom: _minZoom,
                                      maxZoom: _maxZoom,
                                      onPositionChanged: (camera, hasGesture) {
                                        if (mounted) {
                                          setState(() {
                                            _currentZoom = camera.zoom;
                                          });
                                        }
                                      },
                                      zoomOverlay: _buildZoomControls(context),
                                    );
                                  },
                                ),
                    ),
                  );
                },
              ),
            ),
          ),
          RoutePlaybackBar(
            playbackController: _playbackController,
            onPlayPressed: () => setState(() => _playStartedAt = DateTime.now()),
          ),
          if (_routePoints.isNotEmpty)
            ExpansionTile(
              title: Text(
                'Route timeline',
                style: theme.textTheme.titleSmall,
              ),
              children: [
                RouteTimelineList(
                  playbackController: _playbackController,
                  onSeekToPoint: (index) {
                    if (index >= 0 && index < _routePoints.length) {
                      final zoom = _mapController.camera.zoom;
                      _mapController.move(_routePoints[index], zoom);
                    }
                  },
                ),
              ],
            ),
          ListenableBuilder(
            listenable: _playbackController,
            builder: (context, _) {
              return RouteStatsBar(
                distanceKm: _totalDistanceKm,
                pointsLogged: _rawPointsCount,
                speedKmh: _playbackController.currentSpeedKmh,
                maxSpeedKmh: _playbackController.maxSpeedKmh,
                avgSpeedKmh: _playbackController.averageSpeedKmh,
              );
            },
          ),
        ],
      ),
    );
  }
}

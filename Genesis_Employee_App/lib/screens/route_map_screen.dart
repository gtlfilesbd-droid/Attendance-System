import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';

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
  final MapController _mapController = MapController();
  static const double _minZoom = 2.0;
  static const double _maxZoom = 19.0;
  /// Zoom level for button state; avoid reading MapController.camera before it is initialized.
  double _currentZoom = 13.0;

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
    });

    final locations = await _apiService.getMyRouteToday();
    if (!mounted) return;

    // Parse locations
    List<LatLng> points = [];
    List<Marker> markers = [];

    // Check if locations is valid list
    if (locations.isNotEmpty) {
      for (var loc in locations) {
        // Backend returns top-level latitude/longitude (tracking/serializers.py get_route_history).
        // Fallback to nested location.lat/lng for compatibility.
        final latVal = loc['latitude'] ?? loc['location']?['lat'];
        final lngVal = loc['longitude'] ?? loc['location']?['lng'];
        final double? lat = latVal is num ? latVal.toDouble() : null;
        final double? lng = lngVal is num ? lngVal.toDouble() : null;
        final timestamp = loc['timestamp']?.toString();

        if (lat != null && lng != null) {
          final point = LatLng(lat, lng);
          points.add(point);
          final tooltipMessage = timestamp != null ? _formatTimeIso(timestamp) : '';
          markers.add(
            Marker(
              point: point,
              width: 40,
              height: 40,
              child: Tooltip(
                message: tooltipMessage,
                child: const Icon(Icons.location_on, color: Colors.red, size: 30),
              ),
            ),
          );
        }
      }
    }

    // Calculate distance (rough estimate using LatLng.distance)
    double distance = 0;
    const Distance distanceCalculator = Distance();
    for (int i = 0; i < points.length - 1; i++) {
      distance += distanceCalculator.as(LengthUnit.Kilometer, points[i], points[i+1]);
    }

    if (mounted) {
      setState(() {
        _routePoints = points;
        _markers = markers;
        _totalDistanceKm = distance;
        _isLoading = false;
        if (points.isNotEmpty) {
          _currentZoom = 14.0;
        }
      });

      // Zoom to fit if points exist (after setState so map is built)
      if (points.isNotEmpty) {
        _mapController.move(points.last, 14.0);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Route"),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _routePoints.isEmpty 
                  ? const Center(child: Text("No route data for today"))
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
                      '${_routePoints.length}',
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

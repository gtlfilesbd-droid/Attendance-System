import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
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
    
    // Parse locations
    List<LatLng> points = [];
    List<Marker> markers = [];
    
    // Check if locations is valid list
    if (locations.isNotEmpty) {
      for (var loc in locations) {
        // Backend returns locations in a specific format, check serializer in tracking/views.py
        // serialized_locations -> formatted_locations list
        // Each item has 'location': {'lat': ..., 'lng': ...}, 'timestamp', etc.
        
        double? lat;
        double? lng;
        String? timestamp;
        
        if (loc['location'] != null) {
           lat = loc['location']['lat'];
           lng = loc['location']['lng'];
        }
        timestamp = loc['timestamp'];
        
        if (lat != null && lng != null) {
          final point = LatLng(lat, lng);
          points.add(point);
          
          markers.add(
            Marker(
              point: point,
              width: 40,
              height: 40,
              child: Tooltip(
                message: timestamp != null ? _formatTime(timestamp) : '',
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
      });
      
      // Zoom to fit if points exist
      if (points.isNotEmpty) {
        // Simple bounds calculation
        double minLat = points.first.latitude;
        double maxLat = points.first.latitude;
        double minLng = points.first.longitude;
        double maxLng = points.first.longitude;
        
        for (var p in points) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }
        
        // Fit bounds logic would go here or use camera fitBounds
        // For simplicity, just center on the last point
        _mapController.move(points.last, 14.0);
      }
    }
  }
  
  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('HH:mm').format(dt);
    } catch (e) {
      return '';
    }
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
                  : FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _routePoints.isNotEmpty 
                            ? _routePoints.last 
                            : const LatLng(23.8103, 90.4125),
                        initialZoom: 13.0,
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

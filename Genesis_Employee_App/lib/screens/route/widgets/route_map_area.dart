import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Map area widget: OSM tile layer, polyline, static markers, optional animated marker.
/// Polyline shows the full route (Option A); animated marker moves along it.
/// Zoom limits [minZoom]–[maxZoom] (plan: 2–19) enforced on map and gestures.
/// [zoomOverlay] is typically the +/- zoom controls.
class RouteMapArea extends StatelessWidget {
  final List<LatLng> polylinePoints;
  final List<Marker> staticMarkers;
  final Marker? animatedMarker;
  final MapController mapController;
  final LatLng initialCenter;
  final double initialZoom;
  /// Min zoom level (e.g. 2). Gesture zoom is clamped to this.
  final double minZoom;
  /// Max zoom level (e.g. 19). Gesture zoom is clamped to this.
  final double maxZoom;
  final void Function(dynamic camera, bool hasGesture)? onPositionChanged;
  final Widget? zoomOverlay;

  const RouteMapArea({
    super.key,
    required this.polylinePoints,
    required this.staticMarkers,
    this.animatedMarker,
    required this.mapController,
    required this.initialCenter,
    this.initialZoom = 13.0,
    this.minZoom = 2.0,
    this.maxZoom = 19.0,
    this.onPositionChanged,
    this.zoomOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final allMarkers = List<Marker>.from(staticMarkers);
    if (animatedMarker != null) {
      allMarkers.add(animatedMarker!);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            minZoom: minZoom,
            maxZoom: maxZoom,
            onPositionChanged: onPositionChanged,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.genesis.employee_app',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: polylinePoints,
                  color: Colors.blue,
                  strokeWidth: 4.0,
                ),
              ],
            ),
            MarkerLayer(markers: allMarkers),
          ],
        ),
        if (zoomOverlay != null)
          Positioned(
            right: 16,
            top: 16,
            child: zoomOverlay!,
          ),
      ],
    );
  }
}

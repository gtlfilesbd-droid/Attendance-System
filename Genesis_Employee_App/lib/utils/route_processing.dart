import 'package:latlong2/latlong.dart';

/// Default max accuracy in meters; points with worse accuracy are dropped for display.
const double defaultMaxAccuracyMeters = 100.0;

/// Default minimum distance in meters between kept points (removes standing-still clusters).
const double defaultMinDistanceBetweenPointsMeters = 15.0;

/// Default smoothing window size (moving average over lat/lng).
const int defaultSmoothingWindowSize = 3;

/// Result of processing a route for display: smoothed points and total distance.
class ProcessedRoute {
  final List<LatLng> points;
  final double distanceKm;

  const ProcessedRoute({required this.points, required this.distanceKm});
}

/// Raw point parsed from API location map.
class _RoutePoint {
  final double lat;
  final double lng;
  final double? accuracy;
  final String? timestamp;

  _RoutePoint({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.timestamp,
  });

  LatLng toLatLng() => LatLng(lat, lng);
}

/// Filter, dedupe, and smooth route locations for display.
/// Returns points for polyline and distance in km.
ProcessedRoute processRouteForDisplay(
  List<dynamic> locations, {
  double maxAccuracyMeters = defaultMaxAccuracyMeters,
  double minDistanceBetweenPointsMeters = defaultMinDistanceBetweenPointsMeters,
  int smoothingWindowSize = defaultSmoothingWindowSize,
}) {
  if (locations.isEmpty) {
    return const ProcessedRoute(points: [], distanceKm: 0.0);
  }

  // Parse into _RoutePoint list
  List<_RoutePoint> raw = [];
  for (var loc in locations) {
    final latVal = loc['latitude'] ?? loc['location']?['lat'];
    final lngVal = loc['longitude'] ?? loc['location']?['lng'];
    final double? lat = latVal is num ? latVal.toDouble() : null;
    final double? lng = lngVal is num ? lngVal.toDouble() : null;
    if (lat == null || lng == null) continue;
    double? acc;
    if (loc['accuracy'] != null && loc['accuracy'] is num) {
      acc = (loc['accuracy'] as num).toDouble();
    }
    final timestamp = loc['timestamp']?.toString();
    raw.add(_RoutePoint(lat: lat, lng: lng, accuracy: acc, timestamp: timestamp));
  }

  if (raw.isEmpty) return const ProcessedRoute(points: [], distanceKm: 0.0);

  // 1. Filter by accuracy
  List<_RoutePoint> filtered = [];
  for (var p in raw) {
    if (p.accuracy != null && p.accuracy! > maxAccuracyMeters) continue;
    filtered.add(p);
  }
  if (filtered.isEmpty) return const ProcessedRoute(points: [], distanceKm: 0.0);

  // 2. Remove standing-still clusters: keep first, last, and points >= minDistance from last kept
  const distanceCalculator = Distance();
  List<_RoutePoint> deduped = [filtered.first];
  for (int i = 1; i < filtered.length - 1; i++) {
    final lastKept = deduped.last;
    final distM = distanceCalculator.as(LengthUnit.Meter, lastKept.toLatLng(), filtered[i].toLatLng());
    if (distM >= minDistanceBetweenPointsMeters) {
      deduped.add(filtered[i]);
    }
  }
  if (filtered.length > 1) {
    deduped.add(filtered.last);
  }

  if (deduped.isEmpty) return const ProcessedRoute(points: [], distanceKm: 0.0);
  if (deduped.length == 1) {
    return ProcessedRoute(points: [deduped[0].toLatLng()], distanceKm: 0.0);
  }

  // 3. Smooth with moving average (first/last unchanged; middle points averaged)
  int window = smoothingWindowSize.clamp(1, 15);
  if (window.isEven) window--;
  final half = window ~/ 2;
  List<LatLng> smoothed = [];
  for (int i = 0; i < deduped.length; i++) {
    if (i < half || i >= deduped.length - half) {
      smoothed.add(deduped[i].toLatLng());
    } else {
      double sumLat = 0, sumLng = 0;
      int count = 0;
      for (int j = i - half; j <= i + half && j < deduped.length; j++) {
        sumLat += deduped[j].lat;
        sumLng += deduped[j].lng;
        count++;
      }
      smoothed.add(LatLng(sumLat / count, sumLng / count));
    }
  }

  // 4. Distance over smoothed points
  double distanceKm = 0.0;
  for (int i = 0; i < smoothed.length - 1; i++) {
    distanceKm += distanceCalculator.as(LengthUnit.Kilometer, smoothed[i], smoothed[i + 1]);
  }

  return ProcessedRoute(points: smoothed, distanceKm: distanceKm);
}

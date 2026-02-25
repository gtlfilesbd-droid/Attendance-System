import 'package:latlong2/latlong.dart';

import '../models/route_point.dart';

// ---------------------------------------------------------------------------
// Config constants for route display (filter, dedupe, smooth).
// ---------------------------------------------------------------------------

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

/// Result with per-point timestamp and optional speed for playback and stats.
class ProcessedRouteWithTime {
  final List<LatLng> points;
  final double distanceKm;
  final List<RoutePointWithTime> pointsWithTime;

  const ProcessedRouteWithTime({
    required this.points,
    required this.distanceKm,
    required this.pointsWithTime,
  });

  /// Backward compatibility: same as [points].
  List<LatLng> get polylinePoints => points;
}

/// Raw point parsed from API location map.
class _RoutePoint {
  final double lat;
  final double lng;
  final double? accuracy;
  final String? timestamp;
  /// Speed in m/s (normalized from API if needed).
  final double? speedMps;

  _RoutePoint({
    required this.lat,
    required this.lng,
    this.accuracy,
    this.timestamp,
    this.speedMps,
  });

  LatLng toLatLng() => LatLng(lat, lng);
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Filter, dedupe, and smooth route locations for display.
/// Returns points for polyline and distance in km. Keep this behavior for backward
/// compatibility; use [processRouteForDisplayWithTime] when playback or stats need timestamps.
ProcessedRoute processRouteForDisplay(
  List<dynamic> locations, {
  double maxAccuracyMeters = defaultMaxAccuracyMeters,
  double minDistanceBetweenPointsMeters = defaultMinDistanceBetweenPointsMeters,
  int smoothingWindowSize = defaultSmoothingWindowSize,
}) {
  if (locations.isEmpty) {
    return const ProcessedRoute(points: [], distanceKm: 0.0);
  }

  // Parse into _RoutePoint list (top-level latitude/longitude or location.lat/lng; handle num or String)
  List<_RoutePoint> raw = [];
  for (var loc in locations) {
    final latVal = loc['latitude'] ?? (loc['location'] is Map ? (loc['location'] as Map)['lat'] : null);
    final lngVal = loc['longitude'] ?? (loc['location'] is Map ? (loc['location'] as Map)['lng'] : null);
    final double? lat = _toDouble(latVal);
    final double? lng = _toDouble(lngVal);
    if (lat == null || lng == null) continue;
    double? acc;
    if (loc['accuracy'] != null && loc['accuracy'] is num) {
      acc = (loc['accuracy'] as num).toDouble();
    }
    final timestamp = loc['timestamp']?.toString();
    // Normalize speed to m/s: API may send speed in m/s or km/h
    double? speedMps;
    final speedVal = loc['speed'];
    if (speedVal != null && speedVal is num) {
      final v = speedVal.toDouble();
      speedMps = v < 50 ? v : (v / 3.6);
    }
    raw.add(_RoutePoint(lat: lat, lng: lng, accuracy: acc, timestamp: timestamp, speedMps: speedMps));
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

/// Parses ISO8601 [timestamp] to [DateTime]; returns null on failure.
DateTime? _parseTimestamp(String? timestamp) {
  if (timestamp == null || timestamp.isEmpty) return null;
  try {
    final dt = DateTime.parse(timestamp);
    return dt.isUtc ? dt.toLocal() : dt;
  } catch (_) {
    return null;
  }
}

/// Filter, dedupe, and smooth route locations; returns points with time and speed.
/// Timestamps and speed from raw API are applied to the same filtered/deduped/smoothed
/// indices so segment times and speeds can be derived for animation and stats.
ProcessedRouteWithTime processRouteForDisplayWithTime(
  List<dynamic> locations, {
  double maxAccuracyMeters = defaultMaxAccuracyMeters,
  double minDistanceBetweenPointsMeters = defaultMinDistanceBetweenPointsMeters,
  int smoothingWindowSize = defaultSmoothingWindowSize,
}) {
  if (locations.isEmpty) {
    return const ProcessedRouteWithTime(points: [], distanceKm: 0.0, pointsWithTime: []);
  }

  List<_RoutePoint> raw = [];
  for (var loc in locations) {
    final latVal = loc['latitude'] ?? (loc['location'] is Map ? (loc['location'] as Map)['lat'] : null);
    final lngVal = loc['longitude'] ?? (loc['location'] is Map ? (loc['location'] as Map)['lng'] : null);
    final double? lat = _toDouble(latVal);
    final double? lng = _toDouble(lngVal);
    if (lat == null || lng == null) continue;
    double? acc;
    if (loc['accuracy'] != null && loc['accuracy'] is num) {
      acc = (loc['accuracy'] as num).toDouble();
    }
    final timestamp = loc['timestamp']?.toString();
    double? speedMps;
    final speedVal = loc['speed'];
    if (speedVal != null && speedVal is num) {
      final v = speedVal.toDouble();
      speedMps = v < 50 ? v : (v / 3.6);
    }
    raw.add(_RoutePoint(lat: lat, lng: lng, accuracy: acc, timestamp: timestamp, speedMps: speedMps));
  }

  if (raw.isEmpty) {
    return const ProcessedRouteWithTime(points: [], distanceKm: 0.0, pointsWithTime: []);
  }

  List<_RoutePoint> filtered = [];
  for (var p in raw) {
    if (p.accuracy != null && p.accuracy! > maxAccuracyMeters) continue;
    filtered.add(p);
  }
  if (filtered.isEmpty) {
    return const ProcessedRouteWithTime(points: [], distanceKm: 0.0, pointsWithTime: []);
  }

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

  if (deduped.isEmpty) {
    return const ProcessedRouteWithTime(points: [], distanceKm: 0.0, pointsWithTime: []);
  }
  if (deduped.length == 1) {
    final p = deduped[0];
    final pt = RoutePointWithTime(
      point: p.toLatLng(),
      timestamp: _parseTimestamp(p.timestamp),
      speedMps: p.speedMps,
    );
    return ProcessedRouteWithTime(
      points: [p.toLatLng()],
      distanceKm: 0.0,
      pointsWithTime: [pt],
    );
  }

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

  double distanceKm = 0.0;
  for (int i = 0; i < smoothed.length - 1; i++) {
    distanceKm += distanceCalculator.as(LengthUnit.Kilometer, smoothed[i], smoothed[i + 1]);
  }

  List<RoutePointWithTime> pointsWithTime = [];
  for (int i = 0; i < deduped.length; i++) {
    pointsWithTime.add(RoutePointWithTime(
      point: smoothed[i],
      timestamp: _parseTimestamp(deduped[i].timestamp),
      speedMps: deduped[i].speedMps,
    ));
  }

  return ProcessedRouteWithTime(
    points: smoothed,
    distanceKm: distanceKm,
    pointsWithTime: pointsWithTime,
  );
}

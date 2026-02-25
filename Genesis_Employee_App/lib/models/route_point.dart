import 'package:latlong2/latlong.dart';

/// A route point with optional timestamp and speed for playback and stats.
/// [point]: map position.
/// [timestamp]: when the point was recorded (ISO8601 or parsed); null if backend did not provide.
/// [speedMps]: speed in meters per second at this point; null if unknown.
class RoutePointWithTime {
  final LatLng point;
  final DateTime? timestamp;
  final double? speedMps;

  const RoutePointWithTime({
    required this.point,
    this.timestamp,
    this.speedMps,
  });

  /// Speed in km/h for display (null if [speedMps] is null).
  double? get speedKmh =>
      speedMps != null ? (speedMps! * 3.6) : null;
}

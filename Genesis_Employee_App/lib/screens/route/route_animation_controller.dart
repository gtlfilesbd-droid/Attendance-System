import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../models/route_point.dart';

/// Interpolates marker position and bearing between route points for smooth animation.
///
/// Public API: [setPoints], [setSegment], [seekToPointIndex], [reset]; getters
/// [currentPosition], [currentBearingDegrees], [isMoving]. Segment duration for
/// playback is (t2−t1)/speedMultiplier; this class only handles position/bearing
/// from (segmentIndex, progress 0..1). Driven by playback timer; for 60fps use
/// TickerProvider (e.g. SingleTickerProviderStateMixin) where used (plan §4).
class RouteAnimationController extends ChangeNotifier {
  List<RoutePointWithTime> _points = [];
  int _segmentIndex = 0;
  double _segmentProgress = 0.0;
  /// When stationary, use this bearing (plan §4: keep previous bearing or default 0).
  double _lastBearingDegrees = 0.0;

  static const Distance _distance = Distance();

  List<RoutePointWithTime> get points => List.unmodifiable(_points);

  /// Current segment (index into points; we interpolate from points[i] to points[i+1]).
  int get segmentIndex => _segmentIndex;

  /// Progress within current segment, 0.0 to 1.0.
  double get segmentProgress => _segmentProgress;

  /// Interpolated position; null if no points.
  LatLng? get currentPosition {
    if (_points.isEmpty) return null;
    if (_points.length == 1) return _points.first.point;
    final i = _segmentIndex.clamp(0, _points.length - 2);
    final from = _points[i].point;
    final to = _points[i + 1].point;
    final p = _segmentProgress.clamp(0.0, 1.0);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * p,
      from.longitude + (to.longitude - from.longitude) * p,
    );
  }

  /// Bearing in degrees from current segment start to end (for marker rotation).
  /// When stationary (single point or no movement), keeps previous bearing or 0 (plan §4).
  /// Flutter Transform.rotate uses radians: use bearingDegrees * pi/180.
  double get currentBearingDegrees {
    if (_points.length < 2) return _lastBearingDegrees;
    final i = _segmentIndex.clamp(0, _points.length - 2);
    final from = _points[i].point;
    final to = _points[i + 1].point;
    final bearing = _distance.bearing(from, to);
    _lastBearingDegrees = bearing;
    return bearing;
  }

  /// True when we have a next point and progress < 1 (marker is moving).
  bool get isMoving {
    if (_points.length < 2) return false;
    if (_segmentIndex >= _points.length - 1) return false;
    return _segmentProgress < 1.0;
  }

  /// Sets the route points and resets to start.
  void setPoints(List<RoutePointWithTime> points) {
    _points = List.from(points);
    _segmentIndex = 0;
    _segmentProgress = 0.0;
    if (_points.length < 2) _lastBearingDegrees = 0.0;
    notifyListeners();
  }

  /// Updates current segment and progress. [index] is the segment (from point index);
  /// [progress] 0.0 = at points[index], 1.0 = at points[index+1].
  void setSegment(int index, double progress) {
    final maxIndex = _points.isEmpty ? 0 : _points.length - 1;
    final newIndex = index.clamp(0, maxIndex);
    final newProgress = progress.clamp(0.0, 1.0);
    if (_segmentIndex != newIndex || (_segmentProgress - newProgress).abs() > 0.001) {
      _segmentIndex = newIndex;
      _segmentProgress = newProgress;
      notifyListeners();
    }
  }

  /// Jumps to a specific point index (marker shows position at points[pointIndex]).
  void seekToPointIndex(int pointIndex) {
    if (_points.isEmpty) return;
    final i = pointIndex.clamp(0, _points.length - 1);
    if (_points.length == 1) {
      _segmentIndex = 0;
      _segmentProgress = 0.0;
    } else if (i == 0) {
      _segmentIndex = 0;
      _segmentProgress = 0.0;
    } else if (i >= _points.length - 1) {
      _segmentIndex = _points.length - 2;
      _segmentProgress = 1.0;
    } else {
      _segmentIndex = i;
      _segmentProgress = 0.0;
    }
    notifyListeners();
  }

  /// Resets to start of route. Keeps [currentBearingDegrees] at last segment until next move.
  void reset() {
    _segmentIndex = 0;
    _segmentProgress = 0.0;
    notifyListeners();
  }
}

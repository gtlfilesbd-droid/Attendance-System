import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/route_point.dart';
import 'route_animation_controller.dart';

/// Playback state and speed; drives [RouteAnimationController] with segment index and progress.
///
/// Public API: [setRoute], [play], [pause], [reset], [setSpeed], [seekToPointIndex],
/// [setFollowPlayback]. Segment duration = (t2−t1) in ms; progress step scales by [speedMultiplier].
/// When stationary (same point or zero time delta), segment is skipped without animating.
/// Missing timestamps: fall back to equal spacing ([_defaultSegmentDurationMs]) for index-based playback.
/// For 60fps animation, consider AnimationController + TickerProvider (plan §4) instead of timer.
class RoutePlaybackController extends ChangeNotifier {
  RoutePlaybackController(this._animationController);

  final RouteAnimationController _animationController;

  final List<double> _speedOptions = [0.5, 1.0, 2.0, 5.0];
  List<double> get speedOptions => List.unmodifiable(_speedOptions);

  List<RoutePointWithTime> _points = [];
  bool _isPlaying = false;
  int _currentPointIndex = 0;
  double _speedMultiplier = 1.0;
  /// When true, map can center on current point during play (plan §5 optional).
  bool _followPlayback = false;
  Timer? _timer;

  List<RoutePointWithTime> get points => List.unmodifiable(_points);
  bool get isPlaying => _isPlaying;
  int get currentPointIndex => _currentPointIndex;
  double get speedMultiplier => _speedMultiplier;
  bool get followPlayback => _followPlayback;

  /// Total number of points (for progress text).
  int get totalPoints => _points.length;

  /// True when playback can run (at least 2 points).
  bool get canPlay => _points.length >= 2;

  /// Segment duration in ms from timestamps; fallback when missing.
  static const int _defaultSegmentDurationMs = 1000;

  /// Sets route data and resets playback.
  void setRoute(List<RoutePointWithTime> points) {
    _stopTimer();
    _points = List.from(points);
    _animationController.setPoints(points);
    _currentPointIndex = 0;
    _isPlaying = false;
    notifyListeners();
  }

  void play() {
    if (_points.length < 2) {
      notifyListeners();
      return;
    }
    if (_currentPointIndex >= _points.length - 1) {
      reset();
    }
    _isPlaying = true;
    _tick();
    notifyListeners();
  }

  void pause() {
    _isPlaying = false;
    _stopTimer();
    notifyListeners();
  }

  void reset() {
    _stopTimer();
    _currentPointIndex = 0;
    _isPlaying = false;
    _animationController.reset();
    notifyListeners();
  }

  void setSpeed(double multiplier) {
    if (_speedOptions.contains(multiplier)) {
      _speedMultiplier = multiplier;
      notifyListeners();
    }
  }

  /// Seek to a specific point index; stops playback.
  void seekToPointIndex(int index) {
    _stopTimer();
    _isPlaying = false;
    _currentPointIndex = index.clamp(0, _points.length - 1);
    _animationController.seekToPointIndex(index);
    notifyListeners();
  }

  /// Toggle follow mode: when true and playing, map can center on current position (plan §5).
  void setFollowPlayback(bool value) {
    if (_followPlayback == value) return;
    _followPlayback = value;
    notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    if (!_isPlaying || _points.length < 2) return;
    final segmentIndex = _currentPointIndex.clamp(0, _points.length - 2);
    final from = _points[segmentIndex];
    final to = _points[segmentIndex + 1];
    // Skip interpolation when stationary: same point or zero time delta.
    final durationMs = _segmentDurationMs(from, to);
    final isStationary = _isSamePoint(from, to) || durationMs <= 0;
    if (isStationary) {
      _animationController.setSegment(segmentIndex, 1.0);
      _currentPointIndex = segmentIndex + 1;
      if (_currentPointIndex >= _points.length - 1) {
        pause();
        notifyListeners();
        return;
      }
      _animationController.setSegment(_currentPointIndex, 0.0);
      _tick();
      return;
    }
    const stepMs = 50;
    // Segment duration = (t2−t1) / speedMultiplier applied via progressStep.
    final progressStep = (stepMs / durationMs) * _speedMultiplier;
    double progress = _animationController.segmentProgress;
    progress += progressStep;
    if (progress >= 1.0) {
      _animationController.setSegment(segmentIndex, 1.0);
      _currentPointIndex = segmentIndex + 1;
      if (_currentPointIndex >= _points.length - 1) {
        pause();
        notifyListeners();
        return;
      }
      _animationController.setSegment(_currentPointIndex, 0.0);
      _tick();
      return;
    }
    _animationController.setSegment(segmentIndex, progress);
    _timer = Timer(const Duration(milliseconds: 50), _tick);
    notifyListeners();
  }

  static const double _samePointEpsilon = 1e-9;

  bool _isSamePoint(RoutePointWithTime a, RoutePointWithTime b) {
    final pa = a.point;
    final pb = b.point;
    return (pa.latitude - pb.latitude).abs() < _samePointEpsilon &&
        (pa.longitude - pb.longitude).abs() < _samePointEpsilon;
  }

  int _segmentDurationMs(RoutePointWithTime from, RoutePointWithTime to) {
    final t1 = from.timestamp;
    final t2 = to.timestamp;
    if (t1 != null && t2 != null) {
      final ms = t2.difference(t1).inMilliseconds;
      if (ms > 0) return ms;
      return 0; // Same or reversed time: skip interpolation (stationary).
    }
    return _defaultSegmentDurationMs;
  }

  /// Current speed at current point for stats (km/h); null if unknown.
  double? get currentSpeedKmh {
    if (_currentPointIndex < 0 || _currentPointIndex >= _points.length) return null;
    return _points[_currentPointIndex].speedKmh;
  }

  /// Average speed over all points that have speed (km/h); null if none (plan §6).
  double? get averageSpeedKmh {
    if (_points.isEmpty) return null;
    double sum = 0;
    int count = 0;
    for (final p in _points) {
      final s = p.speedKmh;
      if (s != null) {
        sum += s;
        count++;
      }
    }
    if (count == 0) return null;
    return sum / count;
  }

  /// Max speed over all points that have speed (km/h); null if none (plan §6 current/max/avg).
  double? get maxSpeedKmh {
    if (_points.isEmpty) return null;
    double? max;
    for (final p in _points) {
      final s = p.speedKmh;
      if (s != null && (max == null || s > max)) max = s;
    }
    return max;
  }
}

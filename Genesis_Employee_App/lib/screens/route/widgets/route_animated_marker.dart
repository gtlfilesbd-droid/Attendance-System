import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../route_animation_controller.dart';

/// Builds a single marker for the current playback position with rotation by bearing.
/// Returns null when there is no position to show.
Marker? buildRouteAnimatedMarker(RouteAnimationController controller) {
  final position = controller.currentPosition;
  if (position == null) return null;
  final bearingDegrees = controller.currentBearingDegrees;
  final bearingRadians = bearingDegrees * math.pi / 180;
  return Marker(
    point: position,
    width: 40,
    height: 40,
    child: Transform.rotate(
      angle: bearingRadians,
      child: const Icon(Icons.navigation, color: Colors.blue, size: 32),
    ),
  );
}

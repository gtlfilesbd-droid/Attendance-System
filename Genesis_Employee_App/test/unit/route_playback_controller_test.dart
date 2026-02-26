import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/models/route_point.dart';
import 'package:genesis_employee_app/screens/route/route_animation_controller.dart';
import 'package:genesis_employee_app/screens/route/route_playback_controller.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('RoutePlaybackController', () {
    late RouteAnimationController animationController;
    late RoutePlaybackController playbackController;

    setUp(() {
      animationController = RouteAnimationController();
      playbackController = RoutePlaybackController(animationController);
    });

    test('canPlay is false when no points', () {
      playbackController.setRoute([]);
      expect(playbackController.canPlay, isFalse);
    });

    test('canPlay is false when one point', () {
      playbackController.setRoute([
        RoutePointWithTime(point: LatLng(0, 0)),
      ]);
      expect(playbackController.canPlay, isFalse);
    });

    test('canPlay is true when two or more points', () {
      playbackController.setRoute([
        RoutePointWithTime(point: LatLng(0, 0)),
        RoutePointWithTime(point: LatLng(1, 1)),
      ]);
      expect(playbackController.canPlay, isTrue);
    });

    test('play() does not throw when points length < 2 and notifies listeners', () {
      playbackController.setRoute([
        RoutePointWithTime(point: LatLng(0, 0)),
      ]);
      var notified = false;
      playbackController.addListener(() => notified = true);
      playbackController.play();
      expect(playbackController.isPlaying, isFalse);
      expect(notified, isTrue);
    });
  });
}

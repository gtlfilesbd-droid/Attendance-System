import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/services/location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocationService', () {
    test('startTracking does not throw', () async {
      final service = LocationService();
      await expectLater(service.startTracking(), completes);
    });

    test('stopTracking does not throw', () async {
      final service = LocationService();
      await expectLater(service.stopTracking(), completes);
    });

    test('scheduleTracking does not throw', () {
      final service = LocationService();
      expect(() => service.scheduleTracking(), returnsNormally);
    });

    test('isWorkingHours returns bool', () {
      final service = LocationService();
      expect(service.isWorkingHours(), isA<bool>());
    });
  });
}

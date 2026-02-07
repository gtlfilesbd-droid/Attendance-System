import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/services/api_service.dart';
import 'package:genesis_employee_app/services/auth_service.dart';

void main() {
  group('Location sending to backend', () {
    setUp(() async {
      await AuthService().logout();
    });

    test('logLocation returns false when not authenticated', () async {
      final api = ApiService();
      api.initialize();

      final result = await api.logLocation(
        latitude: 23.8103,
        longitude: 90.4125,
        accuracy: 10.0,
        batteryLevel: 85,
      );

      expect(result, isFalse);
    });

    test('logLocation accepts required parameters', () async {
      final api = ApiService();
      api.initialize();

      final result = await api.logLocation(
        latitude: 23.8103,
        longitude: 90.4125,
        accuracy: 10.0,
        batteryLevel: 85,
        speed: 0.5,
      );

      expect(result, isA<bool>());
    });
  });
}

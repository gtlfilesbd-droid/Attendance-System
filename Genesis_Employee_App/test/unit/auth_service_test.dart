import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/services/auth_service.dart';

void main() {
  late AuthService authService;

  setUp(() {
    authService = AuthService();
  });

  tearDown(() async {
    await authService.logout();
  });

  group('AuthService', () {
    test('isLoggedIn returns false after logout', () async {
      await authService.logout();
      final isLoggedIn = await authService.isLoggedIn();
      expect(isLoggedIn, isFalse);
    });

    test('getToken returns null when not logged in', () async {
      await authService.logout();
      final token = await authService.getToken();
      expect(token, isNull);
    });

    test('getEmployeeData returns null when not logged in', () async {
      await authService.logout();
      final data = await authService.getEmployeeData();
      expect(data, isNull);
    });

    test('getRefreshToken returns null when not logged in', () async {
      await authService.logout();
      final refresh = await authService.getRefreshToken();
      expect(refresh, isNull);
    });

    test('logout completes without error', () async {
      await expectLater(authService.logout(), completes);
    });

    test('login with invalid credentials returns false', () async {
      // No mock server; real request will fail in test env
      final result = await authService.login('invalid@test.com', 'wrong');
      expect(result, isFalse);
    });
  });
}

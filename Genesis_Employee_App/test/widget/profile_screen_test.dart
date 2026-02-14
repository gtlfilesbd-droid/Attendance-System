import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/screens/profile_screen.dart';
import 'package:genesis_employee_app/services/api_service.dart';

void main() {
  final fakeProfile = <String, dynamic>{
    'name': 'Test User',
    'email': 'test@example.com',
    'employee_id': 'EMP001',
    'department': 'Dept',
    'designation': 'Designation',
  };

  setUpAll(() {
    ApiService.mockGetMyProfile = () async => fakeProfile;
  });

  tearDownAll(() {
    ApiService.mockGetMyProfile = null;
  });

  group('ProfileScreen widget tests', () {
    testWidgets('shows loading initially then profile or empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('after load displays app bar and logout', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.text('My Profile'), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsWidgets);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('displays profile avatar (read-only; icon when no profile picture)', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });
}

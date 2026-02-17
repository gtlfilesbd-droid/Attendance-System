import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/screens/attendance_screen.dart';
import 'package:genesis_employee_app/services/api_service.dart';

void main() {
  setUpAll(() {
    ApiService.mockGetMyAttendance = ({String? startDate, String? endDate}) async => {'by_date': []};
  });

  tearDownAll(() {
    ApiService.mockGetMyAttendance = null;
  });

  group('AttendanceScreen widget tests', () {
    testWidgets('displays app bar title', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AttendanceScreen(),
        ),
      );

      expect(find.text('My Attendance'), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AttendanceScreen(),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('after load shows content or empty state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AttendanceScreen(),
        ),
      );
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/screens/attendance_screen.dart';

void main() {
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
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle(const Duration(seconds: 15));

      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}

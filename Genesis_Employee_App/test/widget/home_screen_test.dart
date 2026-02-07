import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/screens/home_screen.dart';

void main() {
  group('HomeScreen widget tests', () {
    testWidgets('displays app bar title', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );

      expect(find.text('Genesis Employee'), findsWidgets);
    });

    testWidgets('displays tracking status or stopped initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              (w.data == 'Tracking Active' || w.data == 'Tracking Stopped'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays START DUTY or STOP TRACKING button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      final startOrStop = find.byWidgetPredicate(
        (Widget w) =>
            w is Text &&
            (w.data == 'START DUTY' || w.data == 'STOP TRACKING'),
      );
      expect(startOrStop, findsOneWidget);
    });

    testWidgets('displays action buttons for Attendance and Route', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('View My\nAttendance'), findsOneWidget);
      expect(find.text("View Today's\nRoute"), findsOneWidget);
    });

    testWidgets('displays working hours info', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );

      expect(
        find.text("Your location is tracked while duty is active"),
        findsOneWidget,
      );
    });

    testWidgets('profile icon button is present', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeScreen(),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });
}

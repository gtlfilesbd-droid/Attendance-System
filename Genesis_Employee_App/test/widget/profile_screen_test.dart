import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/screens/profile_screen.dart';

void main() {
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
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(find.text('My Profile'), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsWidgets);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('displays profile avatar icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });
}

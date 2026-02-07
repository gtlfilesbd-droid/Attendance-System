import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/screens/login_screen.dart';

void main() {
  group('LoginScreen widget tests', () {
    testWidgets('displays title and sign in text', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      expect(find.text('Genesis Employee'), findsOneWidget);
      expect(find.text('Sign in to start tracking'), findsOneWidget);
    });

    testWidgets('displays email and password fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('shows validation error when email is empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      await tester.tap(find.text('LOGIN'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter email'), findsOneWidget);
    });

    testWidgets('shows validation error when email is invalid', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, 'notanemail');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.tap(find.text('LOGIN'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('shows validation error when password is empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      await tester.enterText(find.byType(TextFormField).first, 'user@example.com');
      await tester.tap(find.text('LOGIN'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter password'), findsOneWidget);
    });

    testWidgets('login button is present and tappable', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      final loginButton = find.text('LOGIN');
      expect(loginButton, findsOneWidget);
      await tester.tap(loginButton);
      await tester.pump();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('displays location icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );

      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });
  });
}

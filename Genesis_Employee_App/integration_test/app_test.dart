import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:genesis_employee_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App flow integration tests', () {
    testWidgets('app launches and shows splash then login or home', (WidgetTester tester) async {
      app.main();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Genesis Employee'), findsWidgets);

      await tester.pumpAndSettle(const Duration(seconds: 10));

      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              (w.data == 'Sign in to start tracking' ||
                  w.data == 'Genesis Employee' ||
                  w.data == 'Tracking Stopped' ||
                  w.data == 'Tracking Active' ||
                  w.data == 'Hello, '),
        ),
        findsAtLeastNWidgets(1),
      );
    });
  });
}

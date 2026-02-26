import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/screens/route_map_screen.dart';

void main() {
  group('RouteMapScreen widget tests', () {
    testWidgets('displays app bar title', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RouteMapScreen(),
        ),
      );

      expect(find.text('Route'), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RouteMapScreen(),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays Distance Traveled and Points Logged labels when route loaded', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RouteMapScreen(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      // Labels appear in RouteStatsBar (shown even with empty/loading state after first frame)
      expect(find.text('Distance Traveled'), findsOneWidget);
      expect(find.text('Points Logged'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_employee_app/screens/route/widgets/route_stats_bar.dart';

void main() {
  group('RouteStatsBar', () {
    testWidgets('shows all stat labels including Current speed, Max, Avg', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteStatsBar(
              distanceKm: 1.5,
              pointsLogged: 10,
              speedKmh: null,
              maxSpeedKmh: null,
              avgSpeedKmh: null,
            ),
          ),
        ),
      );
      expect(find.text('Distance Traveled'), findsOneWidget);
      expect(find.text('Current speed'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('Avg'), findsOneWidget);
      expect(find.text('Points Logged'), findsOneWidget);
    });

    testWidgets('shows placeholder for null speeds', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteStatsBar(
              distanceKm: 0,
              pointsLogged: 0,
              speedKmh: null,
              maxSpeedKmh: null,
              avgSpeedKmh: null,
            ),
          ),
        ),
      );
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('lays out without overflow at narrow width', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: RouteStatsBar(
                distanceKm: 12.34,
                pointsLogged: 100,
                speedKmh: 25.5,
                maxSpeedKmh: 40.0,
                avgSpeedKmh: 18.2,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RouteStatsBar), findsOneWidget);
    });
  });
}

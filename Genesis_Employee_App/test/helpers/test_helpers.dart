import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump and settle with a custom timeout (useful for widgets with timers).
Future<void> pumpAndSettleWithTimeout(
  WidgetTester tester, {
  Duration duration = const Duration(seconds: 10),
  Duration timeout = const Duration(seconds: 30),
}) async {
  await tester.pumpAndSettle(duration, timeout: timeout);
}

/// Find text that contains [text] (case-insensitive by default).
Finder findTextContaining(String text, {bool findRich = false}) {
  return find.byWidgetPredicate(
    (Widget w) {
      if (w is Text) return w.data?.toLowerCase().contains(text.toLowerCase()) ?? false;
      if (findRich && w is RichText) {
        return w.text.toPlainText().toLowerCase().contains(text.toLowerCase());
      }
      return false;
    },
  );
}

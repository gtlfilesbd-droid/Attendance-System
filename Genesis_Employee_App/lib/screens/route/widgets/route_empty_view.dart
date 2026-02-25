import 'package:flutter/material.dart';

/// Empty state when no route data exists for the selected date.
class RouteEmptyView extends StatelessWidget {
  final String dateLabel;

  const RouteEmptyView({
    super.key,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(
          'No route data for $dateLabel',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

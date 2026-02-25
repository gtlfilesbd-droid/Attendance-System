import 'package:flutter/material.dart';

/// Error state for route screen: message and retry button.
class RouteErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool isLoading;

  const RouteErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: isLoading ? null : onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

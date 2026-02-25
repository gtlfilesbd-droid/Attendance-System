import 'package:flutter/material.dart';

/// Bottom stats bar: distance, points logged, optional current/max/avg speed (plan §6).
/// Uses theme colors for maintainability.
class RouteStatsBar extends StatelessWidget {
  final double distanceKm;
  final int pointsLogged;
  /// Current speed at playback position (km/h); shown during playback when available.
  final double? speedKmh;
  /// Max speed over route points (km/h); shown when available (plan §6).
  final double? maxSpeedKmh;
  /// Average speed over route points (km/h); shown when available (plan §6).
  final double? avgSpeedKmh;

  const RouteStatsBar({
    super.key,
    required this.distanceKm,
    required this.pointsLogged,
    this.speedKmh,
    this.maxSpeedKmh,
    this.avgSpeedKmh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final surface = colorScheme.surface;
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(16.0),
      color: surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Distance Traveled',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: onSurfaceVariant,
                ),
              ),
              Text(
                '${distanceKm.toStringAsFixed(2)} km',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
            ],
          ),
          if (speedKmh != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Current speed',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: onSurfaceVariant,
                  ),
                ),
                Text(
                  '${speedKmh!.toStringAsFixed(1)} km/h',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
              ],
            ),
          if (maxSpeedKmh != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Max',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: onSurfaceVariant,
                  ),
                ),
                Text(
                  '${maxSpeedKmh!.toStringAsFixed(1)} km/h',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
              ],
            ),
          if (avgSpeedKmh != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Avg',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: onSurfaceVariant,
                  ),
                ),
                Text(
                  '${avgSpeedKmh!.toStringAsFixed(1)} km/h',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
              ],
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Points Logged',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: onSurfaceVariant,
                ),
              ),
              Text(
                '$pointsLogged',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Bottom stats bar: distance, points logged, current/max/avg speed (plan §6).
/// Uses theme colors for maintainability. Flexible layout to avoid overflow.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          color: surface,
          child: isNarrow ? _buildTwoRowLayout(theme, onSurface, onSurfaceVariant) : _buildSingleRowLayout(theme, onSurface, onSurfaceVariant),
        );
      },
    );
  }

  Widget _buildSingleRowLayout(ThemeData theme, Color onSurface, Color onSurfaceVariant) {
    return Row(
      children: [
        Expanded(child: _StatTile(theme: theme, label: 'Distance Traveled', value: '${distanceKm.toStringAsFixed(2)} km', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
        Expanded(child: _StatTile(theme: theme, label: 'Current speed', value: speedKmh != null ? '${speedKmh!.toStringAsFixed(1)} km/h' : '—', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
        Expanded(child: _StatTile(theme: theme, label: 'Max', value: maxSpeedKmh != null ? '${maxSpeedKmh!.toStringAsFixed(1)} km/h' : '—', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
        Expanded(child: _StatTile(theme: theme, label: 'Avg', value: avgSpeedKmh != null ? '${avgSpeedKmh!.toStringAsFixed(1)} km/h' : '—', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
        Expanded(child: _StatTile(theme: theme, label: 'Points Logged', value: '$pointsLogged', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
      ],
    );
  }

  Widget _buildTwoRowLayout(ThemeData theme, Color onSurface, Color onSurfaceVariant) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: _StatTile(theme: theme, label: 'Distance Traveled', value: '${distanceKm.toStringAsFixed(2)} km', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
            Expanded(child: _StatTile(theme: theme, label: 'Points Logged', value: '$pointsLogged', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _StatTile(theme: theme, label: 'Current speed', value: speedKmh != null ? '${speedKmh!.toStringAsFixed(1)} km/h' : '—', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
            Expanded(child: _StatTile(theme: theme, label: 'Max', value: maxSpeedKmh != null ? '${maxSpeedKmh!.toStringAsFixed(1)} km/h' : '—', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
            Expanded(child: _StatTile(theme: theme, label: 'Avg', value: avgSpeedKmh != null ? '${avgSpeedKmh!.toStringAsFixed(1)} km/h' : '—', onSurface: onSurface, onSurfaceVariant: onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final ThemeData theme;
  final String label;
  final String value;
  final Color onSurface;
  final Color onSurfaceVariant;

  const _StatTile({
    required this.theme,
    required this.label,
    required this.value,
    required this.onSurface,
    required this.onSurfaceVariant,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

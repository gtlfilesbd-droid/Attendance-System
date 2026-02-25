import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../route_playback_controller.dart';

/// Timeline list of route points: point number, time, truncated label (50 chars), speed.
/// Tap jumps to map point; current point is highlighted and scrolled into view during playback.
/// Uses [ListView.builder] for lazy loading; suitable for large point counts (e.g. > 500).
class RouteTimelineList extends StatefulWidget {
  final RoutePlaybackController playbackController;
  final void Function(int pointIndex)? onSeekToPoint;

  const RouteTimelineList({
    super.key,
    required this.playbackController,
    this.onSeekToPoint,
  });

  @override
  State<RouteTimelineList> createState() => _RouteTimelineListState();
}

class _RouteTimelineListState extends State<RouteTimelineList> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 56.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent(int index) {
    if (!_scrollController.hasClients) return;
    final targetOffset = (index * _itemHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: widget.playbackController,
      builder: (context, _) {
        final points = widget.playbackController.points;
        final currentIndex = widget.playbackController.currentPointIndex;
        if (widget.playbackController.isPlaying) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToCurrent(currentIndex);
          });
        }
        if (points.isEmpty) {
          return const SizedBox(
            height: 120,
            child: Center(child: Text('No points')),
          );
        }
        return SizedBox(
          height: 200,
          child: ListView.builder(
            controller: _scrollController,
            itemCount: points.length,
            itemExtent: _itemHeight,
            itemBuilder: (context, index) {
              final pt = points[index];
              final isCurrent = index == currentIndex;
              final timeStr = pt.timestamp != null
                  ? DateFormat.Hm().format(pt.timestamp!)
                  : '—';
              final speedStr = pt.speedKmh != null
                  ? '${pt.speedKmh!.toStringAsFixed(1)} km/h'
                  : '—';
              final addressLabel = _addressLabel(pt.point);
              return Material(
                color: isCurrent
                    ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : colorScheme.surface,
                child: InkWell(
                  onTap: () {
                    widget.playbackController.seekToPointIndex(index);
                    widget.onSeekToPoint?.call(index);
                    _scrollToCurrent(index);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          '${index + 1}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: isCurrent ? FontWeight.bold : null,
                            color: isCurrent
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                timeStr,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                addressLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          speedStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Placeholder for address (50 chars); can be replaced with geocoding later.
  String _addressLabel(point) {
    final lat = point.latitude.toStringAsFixed(5);
    final lng = point.longitude.toStringAsFixed(5);
    final s = '$lat, $lng';
    return s.length > 50 ? '${s.substring(0, 47)}...' : s;
  }
}

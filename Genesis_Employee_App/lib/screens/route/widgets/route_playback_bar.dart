import 'package:flutter/material.dart';

import '../route_playback_controller.dart';

/// Playback controls: Play/Pause, Reset, Speed selector, progress text, optional progress slider.
class RoutePlaybackBar extends StatelessWidget {
  final RoutePlaybackController playbackController;
  /// Called when the user taps play (before starting playback). Used e.g. to show SnackBar if playback ends immediately.
  final VoidCallback? onPlayPressed;

  const RoutePlaybackBar({
    super.key,
    required this.playbackController,
    this.onPlayPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: playbackController,
      builder: (context, _) {
        final total = playbackController.totalPoints;
        final currentIndex = playbackController.currentPointIndex;
        final current = currentIndex + 1;
        final canPlay = playbackController.canPlay;
        final maxIndex = total > 1 ? total - 1 : 0;
        return Material(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        playbackController.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: colorScheme.primary,
                      ),
                      onPressed: canPlay ? () {
                        if (playbackController.isPlaying) {
                          playbackController.pause();
                        } else {
                          onPlayPressed?.call();
                          playbackController.play();
                        }
                      } : null,
                      tooltip: playbackController.isPlaying
                          ? 'Pause'
                          : (canPlay ? 'Play' : 'Need at least 2 points to play'),
                    ),
                    IconButton(
                      icon: Icon(Icons.replay, color: colorScheme.primary),
                      onPressed: canPlay ? () => playbackController.reset() : null,
                      tooltip: 'Reset',
                    ),
                    IconButton(
                      icon: Icon(
                        playbackController.followPlayback ? Icons.my_location : Icons.location_searching,
                        color: playbackController.followPlayback ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      onPressed: canPlay ? () => playbackController.setFollowPlayback(!playbackController.followPlayback) : null,
                      tooltip: playbackController.followPlayback ? 'Following playback' : 'Follow playback',
                    ),
                    const SizedBox(width: 8),
                    ...playbackController.speedOptions.map((speed) {
                      final isSelected = playbackController.speedMultiplier == speed;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ChoiceChip(
                          label: Text('${speed}x'),
                          selected: isSelected,
                          onSelected: canPlay
                              ? (_) => playbackController.setSpeed(speed)
                              : null,
                        ),
                      );
                    }),
                    const SizedBox(width: 12),
                    Text(
                      total > 0 ? 'Point $current / $total' : '—',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                if (canPlay && maxIndex > 0)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: currentIndex.toDouble().clamp(0.0, maxIndex.toDouble()),
                      min: 0,
                      max: maxIndex.toDouble(),
                      divisions: maxIndex,
                      onChanged: (value) {
                        final index = value.round().clamp(0, maxIndex);
                        playbackController.seekToPointIndex(index);
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

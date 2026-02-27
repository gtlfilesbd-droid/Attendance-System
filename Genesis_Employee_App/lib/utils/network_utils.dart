import 'dart:math';

/// Exponential backoff with jitter for idempotent network operations.
/// Use for log-location, heartbeat, sync; do not use for auth (401 → refresh flow).
Future<T> withBackoff<T>(
  Future<T> Function() task, {
  int maxAttempts = 4,
  Duration initialDelay = const Duration(seconds: 1),
}) async {
  var attempt = 0;
  var delay = initialDelay;
  while (true) {
    attempt++;
    try {
      return await task();
    } catch (_) {
      if (attempt >= maxAttempts) rethrow;
      final jitterMs = (delay.inMilliseconds * 0.2).toInt().clamp(1, 2000);
      final rnd = Random().nextInt(jitterMs * 2) - jitterMs;
      await Future.delayed(Duration(milliseconds: delay.inMilliseconds + rnd));
      delay = Duration(
        milliseconds: (delay.inMilliseconds * 2).clamp(0, 8000),
      );
    }
  }
}

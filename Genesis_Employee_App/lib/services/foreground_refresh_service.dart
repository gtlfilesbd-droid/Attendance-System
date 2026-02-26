import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'location_service.dart';

/// Result of a foreground refresh attempt.
enum ForegroundRefreshResult {
  refreshed,
  skippedDebounce,
  skippedOffline,
}

/// Service that runs when the app returns to foreground: re-inits API, syncs
/// offline data, and notifies registered screens to refresh. Uses debounce and
/// connectivity check to avoid unnecessary API calls and handle offline.
class ForegroundRefreshService {
  static final ForegroundRefreshService _instance =
      ForegroundRefreshService._internal();

  factory ForegroundRefreshService() => _instance;

  ForegroundRefreshService._internal();

  DateTime? _lastRefreshAt;
  static const Duration debounceDuration = Duration(seconds: 30);
  final List<VoidCallback> _listeners = [];
  bool _refreshing = false;

  /// Registers a callback to run when a foreground refresh completes.
  /// Call from screen initState; callback should check [mounted] before setState.
  void addListener(VoidCallback listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// Unregisters a callback. Call from screen dispose.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Returns true if the device appears to have a usable connection.
  /// Uses connectivity_plus; does not guarantee actual internet reachability.
  Future<bool> _hasConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.isNotEmpty &&
          result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// Called when app lifecycle becomes [AppLifecycleState.resumed].
  /// Only run when user is logged in. Returns result so UI can show SnackBar for offline.
  Future<ForegroundRefreshResult> onAppResumed() async {
    if (_refreshing) {
      return ForegroundRefreshResult.skippedDebounce;
    }
    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < debounceDuration) {
      return ForegroundRefreshResult.skippedDebounce;
    }

    if (!await _hasConnectivity()) {
      return ForegroundRefreshResult.skippedOffline;
    }

    _refreshing = true;
    try {
      ApiService().initialize();
      // Do not await: sync can take up to 90s; run in background so UI and listeners are not blocked.
      unawaited(LocationService.syncOfflineData());
      _lastRefreshAt = now;

      for (final listener in List<VoidCallback>.from(_listeners)) {
        try {
          listener();
        } catch (_) {
          // Ignore listener errors so one screen does not break others
        }
      }

      return ForegroundRefreshResult.refreshed;
    } finally {
      _refreshing = false;
    }
  }
}

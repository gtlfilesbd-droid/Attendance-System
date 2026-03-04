import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'app_log_upload_service.dart';
import 'auth_service.dart';
import 'location_service.dart';

/// Result of a foreground refresh attempt.
enum ForegroundRefreshResult {
  refreshed,
  skippedDebounce,
  /// No connectivity (show "No internet").
  skippedOffline,
  /// Connectivity OK but token refresh failed (transient/API); do not show "No internet".
  skippedTransient,
}

/// Service that runs when the app returns to foreground: re-inits API, syncs
/// offline data, and notifies registered screens to refresh. Uses debounce and
/// connectivity check to avoid unnecessary API calls and handle offline.
///
/// Location sync, log upload, and attendance API are three separate flows; no shared queue.
class ForegroundRefreshService {
  static final ForegroundRefreshService _instance =
      ForegroundRefreshService._internal();

  factory ForegroundRefreshService() => _instance;

  ForegroundRefreshService._internal();

  DateTime? _lastRefreshAt;
  /// When app last went to background (paused/inactive); used to detect long background.
  DateTime? _lastPausedAt;
  static const Duration debounceDuration = Duration(seconds: 30);
  static const Duration _listenerDelay = Duration(milliseconds: 500);
  static const Duration _listenerDelayLongBackground = Duration(milliseconds: 800);
  static const Duration longBackgroundThreshold = Duration(minutes: 5);
  /// Delay before starting sync when long background + pending offline data (so first paint/tap are not blocked).
  static const Duration deferredSyncDelay = Duration(seconds: 3);
  /// Delay before retrying connectivity check on resume (avoids fake offline right after returning from background).
  static const Duration _resumeConnectivityRetryDelay = Duration(milliseconds: 500);
  final List<VoidCallback> _listeners = [];
  bool _refreshing = false;

  /// Call when app goes to background (paused or inactive). Used to detect long background on resume.
  void notifyAppPaused() {
    _lastPausedAt = DateTime.now();
  }

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

    // Retry once after delay to avoid fake offline when OS reports stale state right after resume.
    if (!await _hasConnectivity()) {
      await Future.delayed(_resumeConnectivityRetryDelay);
      if (!await _hasConnectivity()) {
        return ForegroundRefreshResult.skippedOffline;
      }
    }

    // Proactive token refresh so sync/upload and listener-triggered requests rarely hit 401.
    var refreshResult = await AuthService().refreshToken();
    if (refreshResult == RefreshResult.networkOrTransientError) {
      await Future.delayed(_resumeConnectivityRetryDelay);
      refreshResult = await AuthService().refreshToken();
    }
    if (refreshResult != RefreshResult.success) {
      // Do not show "No internet" – may be transient or invalid token; interceptor handles 401.
      return ForegroundRefreshResult.skippedTransient;
    }

    _refreshing = true;
    try {
      ApiService().initialize();

      final backgroundDuration = _lastPausedAt != null
          ? now.difference(_lastPausedAt!)
          : Duration.zero;
      final isLongBackground = backgroundDuration > longBackgroundThreshold;
      final listenerDelay = isLongBackground
          ? _listenerDelayLongBackground
          : _listenerDelay;

      // Long background: skip immediate sync to avoid overloading UI; if pending offline data (e.g. from duty), sync after delay.
      // Run location sync and log upload in parallel (no cross-blocking).
      if (!isLongBackground) {
        unawaited(LocationService.syncOfflineData());
        unawaited(AppLogUploadService().uploadBatch());
      } else {
        unawaited(AppLogUploadService().uploadBatch());
        unawaited((() async {
          if (await LocationService.hasPendingOfflineData()) {
            await Future.delayed(deferredSyncDelay);
            await LocationService.syncOfflineData();
          }
        })());
      }
      _lastRefreshAt = now;

      // Defer listener notification so first tap/scroll after resume is processed (Uber/Grab-style).
      unawaited(Future.delayed(listenerDelay, () {
        for (final listener in List<VoidCallback>.from(_listeners)) {
          try {
            listener();
          } catch (_) {
            // Ignore listener errors so one screen does not break others
          }
        }
      }));

      return ForegroundRefreshResult.refreshed;
    } finally {
      _refreshing = false;
    }
  }
}

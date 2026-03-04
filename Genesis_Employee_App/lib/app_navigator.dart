import 'package:flutter/material.dart';

/// Root navigator key for app-wide navigation (e.g. post-logout to Login screen).
/// Set by [main.dart]; use from ProfileScreen or anywhere that needs to navigate
/// after async work that may unmount the current widget.
GlobalKey<NavigatorState>? rootNavigatorKey;

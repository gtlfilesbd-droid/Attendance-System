import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

/// Cached Android SDK level for version-specific permission and UI behavior.
class AndroidSdk {
  AndroidSdk._();

  static int? _sdkInt;

  static Future<int?> get sdkInt async {
    if (!Platform.isAndroid) return null;
    if (_sdkInt != null) return _sdkInt;
    final info = await DeviceInfoPlugin().androidInfo;
    _sdkInt = info.version.sdkInt;
    return _sdkInt;
  }

  static Future<bool> get isAtLeast29 async {
    final sdk = await sdkInt;
    return sdk != null && sdk >= 29;
  }

  static Future<bool> get isAtLeast33 async {
    final sdk = await sdkInt;
    return sdk != null && sdk >= 33;
  }

  /// Reset cache (for tests).
  static void resetForTest() {
    _sdkInt = null;
  }
}

import 'package:flutter/services.dart';

/// Toggles Android FLAG_SECURE to block screenshots/screen recording.
class ScreenSecurity {
  const ScreenSecurity();

  static const MethodChannel _channel = MethodChannel(
    'androidircx/screen_security',
  );

  Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } catch (_) {
      // No-op on platforms without the native handler.
    }
  }
}

import 'dart:async';

import 'package:local_auth/local_auth.dart';

typedef DeviceUnlockPrompt = Future<bool> Function(String reason);

/// Coalesces biometric/PIN prompts and allows a short reuse window after a
/// successful device unlock.
class DeviceUnlockSession {
  DeviceUnlockSession({
    DeviceUnlockPrompt? prompt,
    Duration reuseWindow = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _prompt = prompt ?? _defaultPrompt,
       _reuseWindow = reuseWindow,
       _now = now ?? DateTime.now;

  static final DeviceUnlockSession instance = DeviceUnlockSession();

  final DeviceUnlockPrompt _prompt;
  final Duration _reuseWindow;
  final DateTime Function() _now;
  DateTime? _lastSuccessAt;
  Future<bool>? _inFlight;

  Future<bool> authenticate({required String reason}) {
    final lastSuccessAt = _lastSuccessAt;
    final now = _now();
    if (lastSuccessAt != null &&
        now.difference(lastSuccessAt).abs() <= _reuseWindow) {
      return Future<bool>.value(true);
    }

    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    final next = _prompt(reason).then((unlocked) {
      if (unlocked) {
        _lastSuccessAt = _now();
      }
      return unlocked;
    });
    _inFlight = next;
    return next.whenComplete(() {
      if (identical(_inFlight, next)) {
        _inFlight = null;
      }
    });
  }

  void invalidate() {
    _lastSuccessAt = null;
  }

  static Future<bool> _defaultPrompt(String reason) async {
    try {
      final auth = LocalAuthentication();
      final supported =
          await auth.isDeviceSupported() || await auth.canCheckBiometrics;
      if (!supported) {
        return false;
      }
      return await auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

import 'package:androidircx/core/security/history_encryption_key_manager.dart';
import 'package:androidircx/core/security/device_unlock_session.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric (+ device PIN/passphrase fallback) gate for the encrypted history
/// key, backed by `local_auth`.
class LocalAuthHistoryUnlockAuthenticator
    implements HistoryUnlockAuthenticator {
  LocalAuthHistoryUnlockAuthenticator([LocalAuthentication? auth])
    : _unlockSession = auth == null
          ? DeviceUnlockSession.instance
          : DeviceUnlockSession(prompt: _promptFor(auth));

  final DeviceUnlockSession _unlockSession;

  @override
  Future<bool> authenticate({required String reason}) async {
    return _unlockSession.authenticate(reason: reason);
  }

  static DeviceUnlockPrompt _promptFor(LocalAuthentication auth) {
    return (reason) async {
      try {
        final supported =
            await auth.isDeviceSupported() || await auth.canCheckBiometrics;
        if (!supported) {
          return false;
        }
        return await auth.authenticate(
          localizedReason: reason,
          // biometricOnly: false allows the device PIN/passphrase fallback.
          biometricOnly: false,
          persistAcrossBackgrounding: true,
        );
      } catch (_) {
        return false;
      }
    };
  }
}

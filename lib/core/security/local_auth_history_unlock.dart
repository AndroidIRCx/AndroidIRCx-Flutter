import 'package:androidircx/core/security/history_encryption_key_manager.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric (+ device PIN/passphrase fallback) gate for the encrypted history
/// key, backed by `local_auth`.
class LocalAuthHistoryUnlockAuthenticator implements HistoryUnlockAuthenticator {
  LocalAuthHistoryUnlockAuthenticator([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> authenticate({required String reason}) async {
    try {
      final supported =
          await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;
      if (!supported) {
        return false;
      }
      return await _auth.authenticate(
        localizedReason: reason,
        // biometricOnly: false allows the device PIN/passphrase fallback.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

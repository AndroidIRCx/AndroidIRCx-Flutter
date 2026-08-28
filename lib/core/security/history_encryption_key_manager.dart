import 'dart:convert';
import 'dart:math';

import 'package:androidircx/core/security/secret_storage.dart';

/// Gate that must pass before the encrypted history key is released.
///
/// The production implementation prompts for a fingerprint/face with a device
/// PIN/passphrase fallback (via `local_auth`). Tests supply a fake so the key
/// lifecycle can be verified without a device.
abstract class HistoryUnlockAuthenticator {
  Future<bool> authenticate({required String reason});
}

/// A [HistoryUnlockAuthenticator] that never prompts and always allows access.
///
/// Only for platforms/builds without a biometric/credential gate configured;
/// production Android must use the real biometric+PIN implementation so a stolen
/// database cannot be opened.
class AllowAllHistoryUnlockAuthenticator implements HistoryUnlockAuthenticator {
  const AllowAllHistoryUnlockAuthenticator();

  @override
  Future<bool> authenticate({required String reason}) async => true;
}

/// Owns the lifecycle of the SQLCipher database key.
///
/// The key is a random 256-bit value persisted in [SecretStorage] (Android
/// Keystore-backed at rest). It is only ever returned after the user passes the
/// biometric/PIN [HistoryUnlockAuthenticator], so extracting the database file
/// alone — or having it without authenticating — does not reveal chat history.
class HistoryEncryptionKeyManager {
  HistoryEncryptionKeyManager({
    required SecretStorage storage,
    required HistoryUnlockAuthenticator authenticator,
    List<int> Function()? keyBytesGenerator,
  }) : _storage = storage,
       _authenticator = authenticator,
       _keyBytesGenerator = keyBytesGenerator ?? _defaultKeyBytes;

  static const String storageKey = 'androidircx.history.databaseKey';
  static const int keyLengthBytes = 32; // 256-bit

  final SecretStorage _storage;
  final HistoryUnlockAuthenticator _authenticator;
  final List<int> Function() _keyBytesGenerator;

  /// Whether an encryption key has already been provisioned. Does not expose the
  /// key and does not require authentication — it is a status check only.
  Future<bool> hasKey() async {
    final existing = await _storage.getSecret(storageKey);
    return existing != null && existing.isNotEmpty;
  }

  /// Authenticates the user and returns the database key, generating one on
  /// first use. Returns null when authentication fails, leaving history locked.
  Future<String?> unlockKey({
    String reason = 'Unlock your chat history',
  }) async {
    final authenticated = await _authenticator.authenticate(reason: reason);
    if (!authenticated) {
      return null;
    }

    final existing = await _storage.getSecret(storageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = base64Encode(_keyBytesGenerator());
    await _storage.setSecret(storageKey, generated);
    return generated;
  }

  /// Permanently discards the key. The encrypted database becomes unreadable and
  /// must be recreated. Used for a "forget history" / re-key action.
  Future<void> resetKey() async {
    await _storage.removeSecret(storageKey);
  }

  static List<int> _defaultKeyBytes() {
    final random = Random.secure();
    return List<int>.generate(
      keyLengthBytes,
      (_) => random.nextInt(256),
      growable: false,
    );
  }
}

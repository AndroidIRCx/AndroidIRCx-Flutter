import 'dart:convert';

import 'package:androidircx/core/security/history_encryption_key_manager.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthenticator implements HistoryUnlockAuthenticator {
  _FakeAuthenticator(this.allow);

  bool allow;
  int calls = 0;
  String? lastReason;

  @override
  Future<bool> authenticate({required String reason}) async {
    calls++;
    lastReason = reason;
    return allow;
  }
}

void main() {
  group('HistoryEncryptionKeyManager', () {
    test('generates a key on first unlock and reuses it afterwards', () async {
      final storage = InMemorySecretStorage();
      final auth = _FakeAuthenticator(true);
      final manager = HistoryEncryptionKeyManager(
        storage: storage,
        authenticator: auth,
      );

      expect(await manager.hasKey(), isFalse);

      final first = await manager.unlockKey();
      expect(first, isNotNull);
      expect(await manager.hasKey(), isTrue);

      final second = await manager.unlockKey();
      expect(second, first);
      expect(auth.calls, 2);
    });

    test('generates a random 256-bit key', () async {
      final manager = HistoryEncryptionKeyManager(
        storage: InMemorySecretStorage(),
        authenticator: _FakeAuthenticator(true),
      );
      final key = await manager.unlockKey();
      expect(base64Decode(key!).length, 32);
    });

    test('returns null and provisions nothing when authentication fails',
        () async {
      final storage = InMemorySecretStorage();
      final manager = HistoryEncryptionKeyManager(
        storage: storage,
        authenticator: _FakeAuthenticator(false),
      );

      final key = await manager.unlockKey();
      expect(key, isNull);
      expect(await manager.hasKey(), isFalse);
      expect(await storage.getAllSecretKeys(), isEmpty);
    });

    test('does not release an existing key without authentication', () async {
      final storage = InMemorySecretStorage();
      final auth = _FakeAuthenticator(true);
      final manager = HistoryEncryptionKeyManager(
        storage: storage,
        authenticator: auth,
      );
      final provisioned = await manager.unlockKey();
      expect(provisioned, isNotNull);

      auth.allow = false;
      final blocked = await manager.unlockKey();
      expect(blocked, isNull);
      // The key still exists in storage; it just was not released.
      expect(await manager.hasKey(), isTrue);
    });

    test('resetKey discards the key so history can no longer be opened',
        () async {
      final manager = HistoryEncryptionKeyManager(
        storage: InMemorySecretStorage(),
        authenticator: _FakeAuthenticator(true),
      );
      await manager.unlockKey();
      expect(await manager.hasKey(), isTrue);

      await manager.resetKey();
      expect(await manager.hasKey(), isFalse);
    });

    test('passes the unlock reason through to the authenticator', () async {
      final auth = _FakeAuthenticator(true);
      final manager = HistoryEncryptionKeyManager(
        storage: InMemorySecretStorage(),
        authenticator: auth,
      );
      await manager.unlockKey(reason: 'Open #private history');
      expect(auth.lastReason, 'Open #private history');
    });

    test('uses the injected key generator deterministically', () async {
      final manager = HistoryEncryptionKeyManager(
        storage: InMemorySecretStorage(),
        authenticator: _FakeAuthenticator(true),
        keyBytesGenerator: () => List<int>.filled(32, 7),
      );
      final key = await manager.unlockKey();
      expect(key, base64Encode(List<int>.filled(32, 7)));
    });
  });
}

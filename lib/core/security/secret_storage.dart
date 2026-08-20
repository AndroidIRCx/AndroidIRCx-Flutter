import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small platform-neutral seam for secret persistence.
///
/// Production code uses [FlutterSecureSecretStorage]. Tests can use
/// [InMemorySecretStorage] for deterministic migration coverage.
abstract class SecretStorage {
  Future<void> setSecret(String key, String? value);
  Future<String?> getSecret(String key);
  Future<void> removeSecret(String key);
  Future<List<String>> getAllSecretKeys();
  Future<SecretStorageStatus> getStatus();
}

enum SecretStorageBackend {
  inMemory,
  sharedPreferencesFallback,
  platformSecureStorage,
}

class SecretStorageStatus {
  const SecretStorageStatus({
    required this.isSecure,
    required this.backend,
    this.warning,
  });

  final bool isSecure;
  final SecretStorageBackend backend;
  final String? warning;

  bool get isFallback => !isSecure;
}

class FlutterSecureSecretStorage implements SecretStorage {
  FlutterSecureSecretStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> setSecret(String key, String? value) async {
    _validateSecretKey(key);
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
      return;
    }

    await _storage.write(key: key, value: value);
  }

  @override
  Future<String?> getSecret(String key) async {
    _validateSecretKey(key);
    return _storage.read(key: key);
  }

  @override
  Future<void> removeSecret(String key) async {
    _validateSecretKey(key);
    await _storage.delete(key: key);
  }

  @override
  Future<List<String>> getAllSecretKeys() async {
    final values = await _storage.readAll();
    final keys = values.keys.toList(growable: false)..sort();
    return keys;
  }

  @override
  Future<SecretStorageStatus> getStatus() async {
    return const SecretStorageStatus(
      isSecure: true,
      backend: SecretStorageBackend.platformSecureStorage,
    );
  }
}

/// Test/dry-run implementation used to exercise migration behavior without
/// introducing a platform dependency.
///
/// Matching the React Native service contract, setting null or an empty string
/// removes the secret and getAllSecretKeys returns logical keys without backend
/// prefixes.
class InMemorySecretStorage implements SecretStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> setSecret(String key, String? value) async {
    _validateSecretKey(key);
    if (value == null || value.isEmpty) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<String?> getSecret(String key) async {
    _validateSecretKey(key);
    return _values[key];
  }

  @override
  Future<void> removeSecret(String key) async {
    _validateSecretKey(key);
    _values.remove(key);
  }

  @override
  Future<List<String>> getAllSecretKeys() async {
    final keys = _values.keys.toList(growable: false)..sort();
    return keys;
  }

  @override
  Future<SecretStorageStatus> getStatus() async {
    return const SecretStorageStatus(
      isSecure: false,
      backend: SecretStorageBackend.inMemory,
      warning:
          'In-memory secret storage is for tests and migration dry-runs only.',
    );
  }
}

void _validateSecretKey(String key) {
  if (key.trim().isEmpty) {
    throw ArgumentError.value(
      key,
      'key',
      'Secret storage key must not be empty.',
    );
  }
}

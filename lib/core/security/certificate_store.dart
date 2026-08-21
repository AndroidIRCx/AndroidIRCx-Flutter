import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/storage/network_secret_keys.dart';

/// A client certificate + private key pair used for SASL EXTERNAL / CertFP.
///
/// The PEM material is only ever held in memory transiently and persisted
/// through [SecretStorage]; it must never be written to the public network
/// config JSON, logs, or exports.
class ClientCertificate {
  const ClientCertificate({
    this.certificatePem = '',
    this.privateKeyPem = '',
    this.pkcs12Base64,
    this.privateKeyPassphrase,
  });

  final String certificatePem;
  final String privateKeyPem;

  /// Base64-encoded PKCS#12 (.p12/.pfx) bundle. When set, TLS uses this bundle
  /// (with [privateKeyPassphrase] as the import password) instead of the PEM
  /// fields. Dart's [SecurityContext] parses PKCS#12 natively.
  final String? pkcs12Base64;

  final String? privateKeyPassphrase;

  /// Whether this certificate is backed by a PKCS#12 bundle.
  bool get isPkcs12 => (pkcs12Base64 ?? '').isNotEmpty;

  @override
  String toString() =>
      'ClientCertificate(certificatePem: [REDACTED], '
      'privateKeyPem: [REDACTED], '
      'pkcs12Base64: ${isPkcs12 ? '[REDACTED]' : 'null'}, '
      'privateKeyPassphrase: ${privateKeyPassphrase == null ? 'null' : '[REDACTED]'})';
}

/// Raised when supplied PEM material does not look like a certificate/key pair.
class CertificateFormatException implements Exception {
  const CertificateFormatException(this.message);

  final String message;

  @override
  String toString() => 'CertificateFormatException: $message';
}

/// Stores per-network client certificates in secure storage.
///
/// Keys reuse [NetworkSecretField] so deleting a network (which iterates all
/// secret fields) also wipes its certificate, and so certificate material is
/// stripped from any public config export just like other secrets.
class CertificateStore {
  CertificateStore(this._storage);

  final SecretStorage _storage;

  Future<void> save(String networkId, ClientCertificate certificate) async {
    validateClientCertificate(certificate);
    await _storage.setSecret(
      _key(networkId, NetworkSecretField.clientCertificate),
      certificate.certificatePem.trim(),
    );
    await _storage.setSecret(
      _key(networkId, NetworkSecretField.clientPrivateKey),
      certificate.privateKeyPem.trim(),
    );
    await _storage.setSecret(
      _key(networkId, NetworkSecretField.clientPkcs12),
      certificate.pkcs12Base64?.trim(),
    );
    await _storage.setSecret(
      _key(networkId, NetworkSecretField.clientKeyPassphrase),
      certificate.privateKeyPassphrase,
    );
  }

  Future<ClientCertificate?> read(String networkId) async {
    final passphrase = await _storage.getSecret(
      _key(networkId, NetworkSecretField.clientKeyPassphrase),
    );
    final normalizedPassphrase =
        (passphrase == null || passphrase.isEmpty) ? null : passphrase;

    final pkcs12 = await _storage.getSecret(
      _key(networkId, NetworkSecretField.clientPkcs12),
    );
    if (pkcs12 != null && pkcs12.isNotEmpty) {
      return ClientCertificate(
        pkcs12Base64: pkcs12,
        privateKeyPassphrase: normalizedPassphrase,
      );
    }

    final certificatePem = await _storage.getSecret(
      _key(networkId, NetworkSecretField.clientCertificate),
    );
    final privateKeyPem = await _storage.getSecret(
      _key(networkId, NetworkSecretField.clientPrivateKey),
    );
    if (certificatePem == null ||
        certificatePem.isEmpty ||
        privateKeyPem == null ||
        privateKeyPem.isEmpty) {
      return null;
    }
    return ClientCertificate(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      privateKeyPassphrase: normalizedPassphrase,
    );
  }

  Future<bool> has(String networkId) async {
    final pkcs12 = await _storage.getSecret(
      _key(networkId, NetworkSecretField.clientPkcs12),
    );
    if (pkcs12 != null && pkcs12.isNotEmpty) {
      return true;
    }
    final certificatePem = await _storage.getSecret(
      _key(networkId, NetworkSecretField.clientCertificate),
    );
    final privateKeyPem = await _storage.getSecret(
      _key(networkId, NetworkSecretField.clientPrivateKey),
    );
    return certificatePem != null &&
        certificatePem.isNotEmpty &&
        privateKeyPem != null &&
        privateKeyPem.isNotEmpty;
  }

  Future<void> delete(String networkId) async {
    await _storage.removeSecret(
      _key(networkId, NetworkSecretField.clientCertificate),
    );
    await _storage.removeSecret(
      _key(networkId, NetworkSecretField.clientPrivateKey),
    );
    await _storage.removeSecret(
      _key(networkId, NetworkSecretField.clientPkcs12),
    );
    await _storage.removeSecret(
      _key(networkId, NetworkSecretField.clientKeyPassphrase),
    );
  }

  static String _key(String networkId, NetworkSecretField field) {
    return networkSecretStorageKey(networkId: networkId, field: field);
  }
}

/// Validates that [certificate] carries a PEM certificate and a PEM private key.
///
/// This is a structural check (well-formed BEGIN/END blocks with base64 bodies),
/// not a cryptographic verification — the TLS stack performs the real handshake.
void validateClientCertificate(ClientCertificate certificate) {
  if (certificate.isPkcs12) {
    final body = certificate.pkcs12Base64!.replaceAll(RegExp(r'\s'), '');
    if (body.isEmpty || !_isBase64(body)) {
      throw const CertificateFormatException(
        'PKCS#12 bundle must be base64-encoded .p12/.pfx data.',
      );
    }
    return;
  }
  if (!_isPemBlock(
    certificate.certificatePem,
    const ['CERTIFICATE'],
  )) {
    throw const CertificateFormatException(
      'Client certificate must be a PEM block '
      '(-----BEGIN CERTIFICATE----- … -----END CERTIFICATE-----).',
    );
  }
  if (!_isPemBlock(
    certificate.privateKeyPem,
    const [
      'PRIVATE KEY',
      'RSA PRIVATE KEY',
      'EC PRIVATE KEY',
      'ENCRYPTED PRIVATE KEY',
    ],
  )) {
    throw const CertificateFormatException(
      'Client private key must be a PEM private-key block.',
    );
  }
}

bool _isPemBlock(String value, List<String> allowedLabels) {
  final trimmed = value.trim();
  for (final label in allowedLabels) {
    final begin = '-----BEGIN $label-----';
    final end = '-----END $label-----';
    final beginIndex = trimmed.indexOf(begin);
    if (beginIndex == -1) {
      continue;
    }
    final endIndex = trimmed.indexOf(end, beginIndex + begin.length);
    if (endIndex == -1) {
      continue;
    }
    final body = trimmed
        .substring(beginIndex + begin.length, endIndex)
        .replaceAll(RegExp(r'\s'), '');
    if (body.isNotEmpty && _isBase64(body)) {
      return true;
    }
  }
  return false;
}

bool _isBase64(String value) {
  return RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(value);
}

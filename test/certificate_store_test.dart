import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/security/certificate_store.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/storage/network_secret_keys.dart';
import 'package:flutter_test/flutter_test.dart';

const _certPem = '-----BEGIN CERTIFICATE-----\n'
    'MIIBmockCertBody0123456789ABCDEFabcdef+/==\n'
    '-----END CERTIFICATE-----';
const _keyPem = '-----BEGIN PRIVATE KEY-----\n'
    'MIIEmockKeyBody0123456789ABCDEFabcdef+/==\n'
    '-----END PRIVATE KEY-----';

void main() {
  group('CertificateStore', () {
    test('saves and reads a client certificate pair', () async {
      final storage = InMemorySecretStorage();
      final store = CertificateStore(storage);

      await store.save(
        'net-1',
        const ClientCertificate(certificatePem: _certPem, privateKeyPem: _keyPem),
      );

      expect(await store.has('net-1'), isTrue);
      final read = await store.read('net-1');
      expect(read, isNotNull);
      expect(read!.certificatePem, _certPem);
      expect(read.privateKeyPem, _keyPem);
      expect(read.privateKeyPassphrase, isNull);
    });

    test('preserves an optional private-key passphrase', () async {
      final storage = InMemorySecretStorage();
      final store = CertificateStore(storage);

      await store.save(
        'net-1',
        const ClientCertificate(
          certificatePem: _certPem,
          privateKeyPem: _keyPem,
          privateKeyPassphrase: 'hunter2',
        ),
      );

      final read = await store.read('net-1');
      expect(read!.privateKeyPassphrase, 'hunter2');
    });

    test('returns null when no certificate is stored', () async {
      final store = CertificateStore(InMemorySecretStorage());
      expect(await store.read('missing'), isNull);
      expect(await store.has('missing'), isFalse);
    });

    test('delete removes certificate, key, and passphrase', () async {
      final storage = InMemorySecretStorage();
      final store = CertificateStore(storage);
      await store.save(
        'net-1',
        const ClientCertificate(
          certificatePem: _certPem,
          privateKeyPem: _keyPem,
          privateKeyPassphrase: 'hunter2',
        ),
      );

      await store.delete('net-1');

      expect(await store.has('net-1'), isFalse);
      expect(
        await storage.getSecret(
          networkSecretStorageKey(
            networkId: 'net-1',
            field: NetworkSecretField.clientKeyPassphrase,
          ),
        ),
        isNull,
      );
    });

    test('rejects a non-PEM certificate', () {
      expect(
        () => validateClientCertificate(
          const ClientCertificate(
            certificatePem: 'not a certificate',
            privateKeyPem: _keyPem,
          ),
        ),
        throwsA(isA<CertificateFormatException>()),
      );
    });

    test('rejects a non-PEM private key', () {
      expect(
        () => validateClientCertificate(
          const ClientCertificate(
            certificatePem: _certPem,
            privateKeyPem: '-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----',
          ),
        ),
        throwsA(isA<CertificateFormatException>()),
      );
    });

    test('accepts RSA and EC private-key PEM labels', () {
      const rsaKey = '-----BEGIN RSA PRIVATE KEY-----\nAAAABBBBCCCC+/==\n'
          '-----END RSA PRIVATE KEY-----';
      expect(
        () => validateClientCertificate(
          const ClientCertificate(certificatePem: _certPem, privateKeyPem: rsaKey),
        ),
        returnsNormally,
      );
    });

    test('save rejects invalid material before writing to storage', () async {
      final storage = InMemorySecretStorage();
      final store = CertificateStore(storage);
      await expectLater(
        store.save(
          'net-1',
          const ClientCertificate(
            certificatePem: 'garbage',
            privateKeyPem: _keyPem,
          ),
        ),
        throwsA(isA<CertificateFormatException>()),
      );
      expect(await storage.getAllSecretKeys(), isEmpty);
    });
  });

  test('NetworkConfig round-trips useClientCertificate', () {
    const config = NetworkConfig(
      id: 'n',
      name: 'N',
      host: 'irc.example.test',
      port: 6697,
      nickname: 'nick',
      saslMechanism: SaslMechanism.external,
      useClientCertificate: true,
    );
    final restored = NetworkConfig.fromJson(config.toJson());
    expect(restored.useClientCertificate, isTrue);
    expect(restored.saslMechanism, SaslMechanism.external);
    expect(config.copyWith().useClientCertificate, isTrue);
  });
}

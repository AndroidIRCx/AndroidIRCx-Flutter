/// Result of parsing a PEM file that may contain a certificate, a private key,
/// or both (a combined CertFP `.pem` as produced by the usual openssl one-liner).
class PemBundle {
  const PemBundle({this.certificate, this.privateKey});

  final String? certificate;
  final String? privateKey;

  bool get hasCertificate => (certificate ?? '').isNotEmpty;
  bool get hasPrivateKey => (privateKey ?? '').isNotEmpty;
  bool get isEmpty => !hasCertificate && !hasPrivateKey;

  static final RegExp _certificate = RegExp(
    r'-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----',
  );
  static final RegExp _privateKey = RegExp(
    r'-----BEGIN (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----'
    r'[\s\S]*?'
    r'-----END (?:RSA |EC |ENCRYPTED )?PRIVATE KEY-----',
  );

  /// Extracts every certificate block and the first private-key block from
  /// [text]. Returns an empty bundle when no PEM blocks are present (e.g. the
  /// file is binary DER/PKCS#12).
  static PemBundle parse(String text) {
    final certs = _certificate
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
    final keyMatch = _privateKey.firstMatch(text);
    return PemBundle(
      certificate: certs.isEmpty ? null : certs.join('\n'),
      privateKey: keyMatch?.group(0),
    );
  }
}

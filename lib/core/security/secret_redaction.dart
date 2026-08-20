const String redactedSecretValue = '[REDACTED]';

const Set<String> networkSecretJsonKeys = <String>{
  'password',
  'saslPassword',
  'autoJoinChannelKeys',
  'serverPassword',
  'clientKey',
  'clientPrivateKey',
  'privateKey',
  'clientCertificate',
  'clientCert',
  'certificatePem',
  'keyPem',
  'token',
  'authToken',
  'accessToken',
  'refreshToken',
};

bool isNetworkSecretJsonKey(String key) {
  if (networkSecretJsonKeys.contains(key)) {
    return true;
  }

  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized.endsWith('password') ||
      normalized.endsWith('token') ||
      normalized.contains('privatekey') ||
      normalized.contains('clientkey') ||
      normalized == 'certpem' ||
      normalized == 'certificatepem' ||
      normalized == 'clientcertificate' ||
      normalized == 'clientcert';
}

Object? redactNetworkSecretValue(String key, Object? value) {
  if (!isNetworkSecretJsonKey(key)) {
    return value;
  }

  return _hasSecretValue(value) ? redactedSecretValue : value;
}

Map<String, Object?> redactNetworkSecrets(Map<String, Object?> json) {
  return json.map(
    (key, value) => MapEntry(key, redactNetworkSecretValue(key, value)),
  );
}

bool _hasSecretValue(Object? value) {
  if (value is String) {
    return value.isNotEmpty;
  }
  if (value is Map) {
    return value.isNotEmpty;
  }
  return false;
}

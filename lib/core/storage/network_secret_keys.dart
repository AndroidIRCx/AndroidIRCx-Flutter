import 'dart:convert';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/security/secret_redaction.dart';

/// Stable logical namespace for network secret migration.
///
/// These keys provide a deterministic target for moving server passwords, SASL
/// passwords, and channel keys into SecretStorage.
const String networkSecretStoragePrefix = 'androidircx.network';

enum NetworkSecretField {
  password('password'),
  saslPassword('saslPassword'),
  autoJoinChannelKeys('autoJoinChannelKeys'),
  proxyPassword('proxyPassword');

  const NetworkSecretField(this.jsonKey);

  final String jsonKey;
}

NetworkSecretField? networkSecretFieldFromJsonKey(String jsonKey) {
  for (final field in NetworkSecretField.values) {
    if (field.jsonKey == jsonKey) {
      return field;
    }
  }
  return null;
}

String networkSecretStorageKey({
  required String networkId,
  required NetworkSecretField field,
}) {
  final normalizedNetworkId = networkId.trim();
  if (normalizedNetworkId.isEmpty) {
    throw ArgumentError.value(
      networkId,
      'networkId',
      'Network secret storage key requires a non-empty network id.',
    );
  }

  return '$networkSecretStoragePrefix.$normalizedNetworkId.${field.jsonKey}';
}

/// Returns only non-empty secrets that should eventually move out of raw
/// NetworkConfig JSON.
Map<String, String> networkSecretMigrationValues(NetworkConfig network) {
  final values = <String, String>{};
  _addIfPresent(values, network, NetworkSecretField.password, network.password);
  _addIfPresent(
    values,
    network,
    NetworkSecretField.saslPassword,
    network.saslPassword,
  );
  if (network.autoJoinChannelKeys.isNotEmpty) {
    _addIfPresent(
      values,
      network,
      NetworkSecretField.autoJoinChannelKeys,
      jsonEncode(network.autoJoinChannelKeys),
    );
  }
  _addIfPresent(
    values,
    network,
    NetworkSecretField.proxyPassword,
    network.proxyPassword,
  );
  return Map<String, String>.unmodifiable(values);
}

/// Redacts a planned secret write map for logs/assertion messages.
Map<String, String> redactNetworkSecretMigrationValues(
  Map<String, String> migrationValues,
) {
  return migrationValues.map(
    (key, value) => MapEntry(key, value.isEmpty ? value : redactedSecretValue),
  );
}

void _addIfPresent(
  Map<String, String> values,
  NetworkConfig network,
  NetworkSecretField field,
  String? value,
) {
  if (value == null || value.isEmpty) {
    return;
  }

  values[networkSecretStorageKey(networkId: network.id, field: field)] = value;
}

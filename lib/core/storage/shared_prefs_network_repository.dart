import 'dart:convert';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:androidircx/core/storage/network_secret_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsNetworkRepository implements NetworkRepository {
  SharedPrefsNetworkRepository({this.secretStorage});

  static const _storageKey = 'androidircx.networks';

  /// Constructing this repository without [secretStorage] keeps the legacy raw
  /// JSON behavior for tests/fallbacks. Production bootstrap must pass a
  /// platform-backed SecretStorage so public JSON stays secret-free.
  static const bool rawJsonFallbackStoresNetworkSecrets = true;

  final SecretStorage? secretStorage;

  bool get storesSecretsInRawJson => secretStorage == null;

  @override
  Future<void> deleteNetwork(String networkId) async {
    final prefs = await SharedPreferences.getInstance();
    final networks = await loadNetworks();
    final next = networks.where((network) => network.id != networkId).toList();
    await prefs.setString(_storageKey, _encode(next));
    if (secretStorage != null) {
      await _removeNetworkSecrets(networkId);
    }
  }

  @override
  Future<List<NetworkConfig>> loadNetworks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return List<NetworkConfig>.unmodifiable(_defaultSeed);
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    final networks = decoded
        .map((item) => NetworkConfig.fromJson(item as Map<String, Object?>))
        .map(_normalizeNetwork)
        .toList(growable: false);

    if (secretStorage == null) {
      return networks;
    }

    var migratedLegacyRawSecrets = false;
    final recombined = <NetworkConfig>[];
    for (final network in networks) {
      if (_hasRawNetworkSecrets(network)) {
        await _writeNetworkSecrets(network);
        migratedLegacyRawSecrets = true;
      }
      recombined.add(await _withStoredNetworkSecrets(network));
    }

    if (migratedLegacyRawSecrets) {
      await prefs.setString(_storageKey, _encode(recombined));
    }

    return recombined;
  }

  @override
  Future<void> saveNetwork(NetworkConfig network) async {
    final prefs = await SharedPreferences.getInstance();
    final networks = (await loadNetworks()).toList();
    final index = networks.indexWhere((item) => item.id == network.id);
    if (index == -1) {
      networks.add(network);
    } else {
      networks[index] = network;
    }
    if (secretStorage != null) {
      await _writeNetworkSecrets(network);
    }
    await prefs.setString(_storageKey, _encode(networks));
  }

  String _encode(List<NetworkConfig> networks) {
    return jsonEncode(
      networks
          .map(
            (network) => secretStorage == null
                ? network.toJson()
                : _publicNetworkJson(network),
          )
          .toList(growable: false),
    );
  }

  Map<String, Object?> _publicNetworkJson(NetworkConfig network) {
    final json = network.toJson();
    for (final field in NetworkSecretField.values) {
      json.remove(field.jsonKey);
    }
    return json;
  }

  Future<void> _writeNetworkSecrets(NetworkConfig network) async {
    final storage = secretStorage;
    if (storage == null) {
      return;
    }

    await storage.setSecret(
      networkSecretStorageKey(
        networkId: network.id,
        field: NetworkSecretField.password,
      ),
      network.password,
    );
    await storage.setSecret(
      networkSecretStorageKey(
        networkId: network.id,
        field: NetworkSecretField.saslPassword,
      ),
      network.saslPassword,
    );
    await storage.setSecret(
      networkSecretStorageKey(
        networkId: network.id,
        field: NetworkSecretField.autoJoinChannelKeys,
      ),
      network.autoJoinChannelKeys.isEmpty
          ? null
          : jsonEncode(network.autoJoinChannelKeys),
    );
    await storage.setSecret(
      networkSecretStorageKey(
        networkId: network.id,
        field: NetworkSecretField.proxyPassword,
      ),
      network.proxyPassword,
    );
  }

  Future<void> _removeNetworkSecrets(String networkId) async {
    final storage = secretStorage;
    if (storage == null) {
      return;
    }

    for (final field in NetworkSecretField.values) {
      await storage.removeSecret(
        networkSecretStorageKey(networkId: networkId, field: field),
      );
    }
  }

  Future<NetworkConfig> _withStoredNetworkSecrets(NetworkConfig network) async {
    final storage = secretStorage;
    if (storage == null) {
      return network;
    }

    final password = await storage.getSecret(
      networkSecretStorageKey(
        networkId: network.id,
        field: NetworkSecretField.password,
      ),
    );
    final saslPassword = await storage.getSecret(
      networkSecretStorageKey(
        networkId: network.id,
        field: NetworkSecretField.saslPassword,
      ),
    );
    final autoJoinChannelKeys = await storage.getSecret(
      networkSecretStorageKey(
        networkId: network.id,
        field: NetworkSecretField.autoJoinChannelKeys,
      ),
    );
    final proxyPassword = await storage.getSecret(
      networkSecretStorageKey(
        networkId: network.id,
        field: NetworkSecretField.proxyPassword,
      ),
    );

    return _copyNetworkSecrets(
      network,
      password: password ?? network.password,
      saslPassword: saslPassword ?? network.saslPassword,
      autoJoinChannelKeys: autoJoinChannelKeys == null
          ? network.autoJoinChannelKeys
          : _decodeChannelKeys(autoJoinChannelKeys),
      proxyPassword: proxyPassword ?? network.proxyPassword,
    );
  }

  NetworkConfig _copyNetworkSecrets(
    NetworkConfig network, {
    String? password,
    String? saslPassword,
    Map<String, String>? autoJoinChannelKeys,
    String? proxyPassword,
  }) {
    return NetworkConfig(
      id: network.id,
      name: network.name,
      host: network.host,
      port: network.port,
      nickname: network.nickname,
      altNickname: network.altNickname,
      username: network.username,
      realName: network.realName,
      useTls: network.useTls,
      webSocketPort: network.webSocketPort,
      webSocketPath: network.webSocketPath,
      password: password,
      saslAccount: network.saslAccount,
      saslPassword: saslPassword,
      saslMechanism: network.saslMechanism,
      autoConnect: network.autoConnect,
      autoJoinChannels: network.autoJoinChannels,
      autoJoinChannelKeys: autoJoinChannelKeys ?? network.autoJoinChannelKeys,
      serviceAuthFallback: network.serviceAuthFallback,
      serviceAuthTarget: network.serviceAuthTarget,
      proxyType: network.proxyType,
      proxyHost: network.proxyHost,
      proxyPort: network.proxyPort,
      proxyUsername: network.proxyUsername,
      proxyPassword: proxyPassword,
      profileLabel: network.profileLabel,
      profileGroup: network.profileGroup,
    );
  }

  bool _hasRawNetworkSecrets(NetworkConfig network) {
    return (network.password != null && network.password!.isNotEmpty) ||
        (network.saslPassword != null && network.saslPassword!.isNotEmpty) ||
        network.autoJoinChannelKeys.isNotEmpty ||
        (network.proxyPassword != null && network.proxyPassword!.isNotEmpty);
  }

  Map<String, String> _decodeChannelKeys(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      return const <String, String>{};
    }
    return NetworkConfig.fromJson({
      'id': 'channel-key-decode',
      'name': 'ChannelKeyDecode',
      'host': 'irc.invalid',
      'port': 6667,
      'nickname': 'AndroidIRCX',
      'autoJoinChannelKeys': decoded,
    }).autoJoinChannelKeys;
  }

  NetworkConfig _normalizeNetwork(NetworkConfig network) {
    if (network.host == 'irc.dbase.in.rs' && network.webSocketPort == null) {
      return network.copyWith(webSocketPort: 16697);
    }

    return network;
  }

  static const List<NetworkConfig> _defaultSeed = [
    NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      webSocketPort: 16697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
      useTls: true,
    ),
  ];
}

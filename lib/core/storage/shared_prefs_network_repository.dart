import 'dart:convert';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsNetworkRepository implements NetworkRepository {
  static const _storageKey = 'androidircx.networks';

  @override
  Future<void> deleteNetwork(String networkId) async {
    final prefs = await SharedPreferences.getInstance();
    final networks = await loadNetworks();
    final next = networks.where((network) => network.id != networkId).toList();
    await prefs.setString(_storageKey, _encode(next));
  }

  @override
  Future<List<NetworkConfig>> loadNetworks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return List<NetworkConfig>.unmodifiable(_defaultSeed);
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => NetworkConfig.fromJson(item as Map<String, Object?>))
        .toList(growable: false);
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
    await prefs.setString(_storageKey, _encode(networks));
  }

  String _encode(List<NetworkConfig> networks) {
    return jsonEncode(
      networks.map((network) => network.toJson()).toList(growable: false),
    );
  }

  static const List<NetworkConfig> _defaultSeed = [
    NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      useTls: true,
    ),
  ];
}

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/network_repository.dart';

class InMemoryNetworkRepository implements NetworkRepository {
  InMemoryNetworkRepository([
    List<NetworkConfig>? seed,
  ]) : _networks = List<NetworkConfig>.from(seed ?? _defaultSeed);

  final List<NetworkConfig> _networks;

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

  @override
  Future<void> deleteNetwork(String networkId) async {
    _networks.removeWhere((network) => network.id == networkId);
  }

  @override
  Future<List<NetworkConfig>> loadNetworks() async {
    return List<NetworkConfig>.unmodifiable(
      _networks.map(_normalizeNetwork),
    );
  }

  @override
  Future<void> saveNetwork(NetworkConfig network) async {
    final index = _networks.indexWhere((item) => item.id == network.id);
    if (index == -1) {
      _networks.add(_normalizeNetwork(network));
      return;
    }

    _networks[index] = _normalizeNetwork(network);
  }

  NetworkConfig _normalizeNetwork(NetworkConfig network) {
    if (network.host == 'irc.dbase.in.rs' && network.webSocketPort == null) {
      return network.copyWith(webSocketPort: 16697);
    }

    return network;
  }
}

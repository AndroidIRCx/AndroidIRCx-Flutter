import 'package:androidircx/core/models/network_config.dart';

abstract class NetworkRepository {
  Future<List<NetworkConfig>> loadNetworks();
  Future<void> saveNetwork(NetworkConfig network);
  Future<void> deleteNetwork(String networkId);
}

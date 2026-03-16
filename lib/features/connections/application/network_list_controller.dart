import 'dart:math';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:flutter/foundation.dart';

class NetworkListController extends ChangeNotifier {
  NetworkListController({
    required NetworkRepository repository,
  }) : _repository = repository;

  final NetworkRepository _repository;

  List<NetworkConfig> _networks = const [];
  bool _isLoading = true;

  List<NetworkConfig> get networks => _networks;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _networks = await _repository.loadNetworks();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveNetwork({
    required String name,
    required String host,
    required int port,
    required String nickname,
    required bool useTls,
    String? networkId,
  }) async {
    final network = NetworkConfig(
      id: networkId ?? _createId(name),
      name: name,
      host: host,
      port: port,
      nickname: nickname,
      useTls: useTls,
    );

    await _repository.saveNetwork(network);
    await load();
  }

  Future<void> deleteNetwork(String networkId) async {
    await _repository.deleteNetwork(networkId);
    await load();
  }

  String _createId(String seed) {
    final normalized = seed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return '$normalized-${Random().nextInt(9999).toString().padLeft(4, '0')}';
  }
}

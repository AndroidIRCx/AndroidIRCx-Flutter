import 'dart:math';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/security/certificate_store.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:flutter/foundation.dart';

class NetworkListController extends ChangeNotifier {
  NetworkListController({
    required NetworkRepository repository,
    CertificateStore? certificateStore,
  }) : _repository = repository,
       _certificateStore =
           certificateStore ??
           CertificateStore(FlutterSecureSecretStorage());

  final NetworkRepository _repository;
  final CertificateStore _certificateStore;

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
    required String altNickname,
    required bool useTls,
    int? webSocketPort,
    String? webSocketPath,
    required bool autoConnect,
    List<String> autoJoinChannels = const <String>[],
    Map<String, String> autoJoinChannelKeys = const <String, String>{},
    String? profileLabel,
    String? profileGroup,
    required SaslMechanism saslMechanism,
    String? saslAccount,
    String? saslPassword,
    ServiceAuthFallback serviceAuthFallback = ServiceAuthFallback.disabled,
    String? serviceAuthTarget,
    IrcProxyType proxyType = IrcProxyType.none,
    String? proxyHost,
    int? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
    String? identityProfileId,
    bool useClientCertificate = false,
    String? clientCertificatePem,
    String? clientPrivateKeyPem,
    String? clientPkcs12Base64,
    String? clientKeyPassphrase,
    String? networkId,
  }) async {
    final network = NetworkConfig(
      id: networkId ?? _createId(name),
      identityProfileId: _optionalText(identityProfileId),
      useClientCertificate: useClientCertificate,
      name: name,
      host: host,
      port: port,
      nickname: nickname,
      altNickname: altNickname.trim(),
      useTls: useTls,
      webSocketPort: webSocketPort,
      webSocketPath: (webSocketPath ?? '').trim().isEmpty
          ? null
          : webSocketPath?.trim(),
      autoConnect: autoConnect,
      autoJoinChannels: _normalizeChannels(autoJoinChannels),
      profileLabel: _optionalText(profileLabel),
      profileGroup: _optionalText(profileGroup),
      saslMechanism: saslMechanism,
      saslAccount: (saslAccount ?? '').trim().isEmpty
          ? null
          : saslAccount?.trim(),
      saslPassword: (saslPassword ?? '').trim().isEmpty ? null : saslPassword,
      serviceAuthFallback: serviceAuthFallback,
      serviceAuthTarget: _optionalText(serviceAuthTarget) ?? 'NickServ',
      autoJoinChannelKeys: _normalizeChannelKeys(autoJoinChannelKeys),
      proxyType: proxyType,
      proxyHost: _optionalText(proxyHost),
      proxyPort: proxyType == IrcProxyType.none ? null : proxyPort,
      proxyUsername: _optionalText(proxyUsername),
      proxyPassword: (proxyPassword ?? '').trim().isEmpty
          ? null
          : proxyPassword,
    );

    await _repository.saveNetwork(network);

    final certPem = (clientCertificatePem ?? '').trim();
    final keyPem = (clientPrivateKeyPem ?? '').trim();
    final pkcs12 = (clientPkcs12Base64 ?? '').trim();
    final passphrase = (clientKeyPassphrase ?? '').trim().isEmpty
        ? null
        : clientKeyPassphrase;
    if (useClientCertificate && pkcs12.isNotEmpty) {
      await _certificateStore.save(
        network.id,
        ClientCertificate(
          pkcs12Base64: pkcs12,
          privateKeyPassphrase: passphrase,
        ),
      );
    } else if (useClientCertificate &&
        certPem.isNotEmpty &&
        keyPem.isNotEmpty) {
      await _certificateStore.save(
        network.id,
        ClientCertificate(
          certificatePem: certPem,
          privateKeyPem: keyPem,
          privateKeyPassphrase: passphrase,
        ),
      );
    }

    await load();
  }

  Future<void> deleteNetwork(String networkId) async {
    await _repository.deleteNetwork(networkId);
    await load();
  }

  String _createId(String seed) {
    final normalized = seed.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    return '$normalized-${Random().nextInt(9999).toString().padLeft(4, '0')}';
  }

  List<String> _normalizeChannels(List<String> channels) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in channels) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final channel = trimmed.startsWith('#') ? trimmed : '#$trimmed';
      if (seen.add(channel.toLowerCase())) {
        result.add(channel);
      }
    }
    return result;
  }

  Map<String, String> _normalizeChannelKeys(Map<String, String> channelKeys) {
    final result = <String, String>{};
    channelKeys.forEach((rawChannel, rawKey) {
      final channelValue = rawChannel.trim();
      final keyValue = rawKey.trim();
      if (channelValue.isEmpty || keyValue.isEmpty) {
        return;
      }
      final channel = channelValue.startsWith('#')
          ? channelValue
          : '#$channelValue';
      result[channel] = keyValue;
    });
    return Map<String, String>.unmodifiable(result);
  }

  String? _optionalText(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

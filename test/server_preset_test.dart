import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/presets/server_preset.dart';
import 'package:androidircx/core/presets/server_preset_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = '''
{
  "meta": { "pagination": { "current_page": 1, "total": 2 } },
  "data": [
    { "network_name": "SmallNet", "average_users": 100, "server_list": [
      { "hostname": "plain.example", "port": 6667, "use_ssl": false, "ircd": "ngircd" }
    ]},
    { "network_name": "Libera", "average_users": 30398, "server_list": [
      { "hostname": "plain.libera.chat", "port": 6667, "use_ssl": false },
      { "hostname": "irc.libera.chat", "port": 6697, "use_ssl": true, "ircd": "solanum" }
    ]},
    { "network_name": "NoServers", "average_users": 5, "server_list": [] },
    { "not": "a network" }
  ]
}
''';

void main() {
  group('parseServerPresets', () {
    test('parses networks, skips empty/malformed, sorts by users desc', () {
      final presets = parseServerPresets(_sample);
      expect(presets.map((p) => p.networkName), ['Libera', 'SmallNet']);
      expect(presets.first.averageUsers, 30398);
    });

    test('preferredServer prefers a TLS server', () {
      final libera = parseServerPresets(
        _sample,
      ).firstWhere((p) => p.networkName == 'Libera');
      expect(libera.preferredServer!.hostname, 'irc.libera.chat');
      expect(libera.preferredServer!.useSsl, isTrue);
      expect(libera.preferredServer!.port, 6697);
    });

    test('returns empty for a non-directory payload', () {
      expect(parseServerPresets('{"unexpected": true}'), isEmpty);
      expect(parseServerPresets('[]'), isEmpty);
    });
  });

  group('networkConfigFromPreset', () {
    test('maps the preferred server into a NetworkConfig', () {
      final libera = parseServerPresets(
        _sample,
      ).firstWhere((p) => p.networkName == 'Libera');
      final config = networkConfigFromPreset(libera, id: 'net-1');
      expect(config.name, 'Libera');
      expect(config.host, 'irc.libera.chat');
      expect(config.port, 6697);
      expect(config.useTls, isTrue);
      expect(config.nickname, 'AndroidIRCX');
    });

    test('maps a specific chosen server', () {
      final libera = parseServerPresets(
        _sample,
      ).firstWhere((p) => p.networkName == 'Libera');
      final plain = libera.servers.firstWhere((s) => !s.useSsl);
      final config = networkConfigFromPreset(
        libera,
        id: 'net-2',
        server: plain,
      );
      expect(config.host, 'plain.libera.chat');
      expect(config.port, 6667);
      expect(config.useTls, isFalse);
    });
  });

  group('ServerPresetService', () {
    test('fetchPresets parses the injected payload', () async {
      final service = ServerPresetService(httpGet: (_) async => _sample);
      final presets = await service.fetchPresets();
      expect(presets.map((p) => p.networkName), ['Libera', 'SmallNet']);
    });

    test('falls back to DBase when the request throws', () async {
      final service = ServerPresetService(
        httpGet: (_) async => throw Exception('offline'),
      );
      final presets = await service.fetchPresetsOrFallback();
      expect(presets, hasLength(1));
      expect(presets.single.networkName, 'DBase');
      expect(presets.single.preferredServer!.hostname, 'irc.dbase.in.rs');
      expect(presets.single.preferredServer!.port, 6697);
      expect(presets.single.preferredServer!.useSsl, isTrue);
    });

    test('falls back to DBase on an empty directory', () async {
      final service = ServerPresetService(httpGet: (_) async => '{"data": []}');
      final presets = await service.fetchPresetsOrFallback();
      expect(presets.single.networkName, 'DBase');
    });

    test('prepends DBase when the directory omits it', () async {
      final service = ServerPresetService(httpGet: (_) async => _sample);
      final presets = await service.fetchPresetsOrFallback();
      expect(presets.first.networkName, 'DBase');
      expect(presets.map((p) => p.networkName), contains('Libera'));
    });

    test('keeps a single DBase entry when the directory includes it', () async {
      const payload = '''
      {"data": [
        { "network_name": "DBase", "average_users": 42, "server_list": [
          { "hostname": "irc.dbase.in.rs", "port": 6697, "use_ssl": true }
        ]}
      ]}
      ''';
      final service = ServerPresetService(httpGet: (_) async => payload);
      final presets = await service.fetchPresetsOrFallback();
      expect(
        presets.where((p) => p.networkName.toLowerCase() == 'dbase'),
        hasLength(1),
      );
    });

    test('uses the directory endpoint URL', () {
      expect(
        ServerPresetService.endpoint.toString(),
        'https://irc.dbase.in.rs/api/irc/server-presets',
      );
    });
  });

  test('fallbackPreset maps to the old app default network', () {
    final config = networkConfigFromPreset(
      ServerPresetService.fallbackPreset,
      id: 'dbase-default',
    );
    expect(config.host, 'irc.dbase.in.rs');
    expect(config.port, 6697);
    expect(config.useTls, isTrue);
    expect(config, isA<NetworkConfig>());
  });
}

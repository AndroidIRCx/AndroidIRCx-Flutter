import 'dart:convert';

import 'package:androidircx/core/models/network_config.dart';

/// A single scanned server within a network preset.
class ServerPresetServer {
  const ServerPresetServer({
    required this.hostname,
    required this.port,
    required this.useSsl,
    this.ircd,
  });

  final String hostname;
  final int port;
  final bool useSsl;
  final String? ircd;
}

/// A network entry from the server-presets directory
/// (`https://irc.dbase.in.rs/api/irc/server-presets`).
class ServerPreset {
  const ServerPreset({
    required this.networkName,
    required this.averageUsers,
    required this.servers,
  });

  final String networkName;
  final int averageUsers;
  final List<ServerPresetServer> servers;

  /// Best server to connect to: prefer a TLS server, otherwise the first one.
  ServerPresetServer? get preferredServer {
    if (servers.isEmpty) {
      return null;
    }
    for (final server in servers) {
      if (server.useSsl) {
        return server;
      }
    }
    return servers.first;
  }
}

/// Parses the `{ meta, data: [...] }` directory payload into presets.
///
/// Malformed entries and networks without servers are skipped rather than
/// throwing, so a partially bad payload still yields the usable presets.
List<ServerPreset> parseServerPresets(String jsonBody) {
  final decoded = jsonDecode(jsonBody);
  final Object? data = decoded is Map<String, Object?>
      ? decoded['data']
      : (decoded is List ? decoded : null);
  if (data is! List) {
    return const <ServerPreset>[];
  }

  final presets = <ServerPreset>[];
  for (final entry in data) {
    if (entry is! Map) {
      continue;
    }
    final name = (entry['network_name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      continue;
    }
    final servers = <ServerPresetServer>[];
    final rawServers = entry['server_list'];
    if (rawServers is List) {
      for (final rawServer in rawServers) {
        if (rawServer is! Map) {
          continue;
        }
        final hostname = (rawServer['hostname'] as String?)?.trim();
        final port = (rawServer['port'] as num?)?.toInt();
        if (hostname == null || hostname.isEmpty || port == null || port <= 0) {
          continue;
        }
        servers.add(
          ServerPresetServer(
            hostname: hostname,
            port: port,
            useSsl: (rawServer['use_ssl'] as bool?) ?? false,
            ircd: (rawServer['ircd'] as String?)?.trim(),
          ),
        );
      }
    }
    if (servers.isEmpty) {
      continue;
    }
    presets.add(
      ServerPreset(
        networkName: name,
        averageUsers: (entry['average_users'] as num?)?.toInt() ?? 0,
        servers: List<ServerPresetServer>.unmodifiable(servers),
      ),
    );
  }

  presets.sort((a, b) => b.averageUsers.compareTo(a.averageUsers));
  return List<ServerPreset>.unmodifiable(presets);
}

/// Maps a preset (and optionally a specific server) to a new [NetworkConfig],
/// carrying the old app's default identity.
NetworkConfig networkConfigFromPreset(
  ServerPreset preset, {
  required String id,
  String nickname = 'AndroidIRCX',
  String altNickname = 'AndroidIRCX_',
  ServerPresetServer? server,
}) {
  final target = server ?? preset.preferredServer;
  if (target == null) {
    throw ArgumentError.value(
      preset.networkName,
      'preset',
      'Preset has no usable server to map.',
    );
  }
  return NetworkConfig(
    id: id,
    name: preset.networkName,
    host: target.hostname,
    port: target.port,
    nickname: nickname,
    altNickname: altNickname,
    useTls: target.useSsl,
  );
}

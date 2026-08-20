import 'dart:convert';
import 'dart:io';

import 'package:androidircx/core/presets/server_preset.dart';

/// Fetches a URL and returns the response body as text. Injectable so tests can
/// supply canned payloads without real network access.
typedef PresetHttpGet = Future<String> Function(Uri url);

/// Loads default IRC server presets from the directory API, with an offline
/// fallback to the bundled DBase default (mirroring the old app's
/// `DEFAULT_SERVER`).
class ServerPresetService {
  ServerPresetService({PresetHttpGet? httpGet})
      : _httpGet = httpGet ?? _defaultHttpGet;

  final PresetHttpGet _httpGet;

  static final Uri endpoint =
      Uri.parse('https://irc.dbase.in.rs/api/irc/server-presets');

  /// The old app's default network, used when the directory cannot be reached.
  static const ServerPreset fallbackPreset = ServerPreset(
    networkName: 'DBase',
    averageUsers: 0,
    servers: [
      ServerPresetServer(
        hostname: 'irc.dbase.in.rs',
        port: 6697,
        useSsl: true,
      ),
    ],
  );

  static const List<ServerPreset> fallbackPresets = [fallbackPreset];

  /// Fetches and parses presets. Throws on network/parse failure.
  Future<List<ServerPreset>> fetchPresets() async {
    final body = await _httpGet(endpoint);
    return parseServerPresets(body);
  }

  /// Fetches presets, falling back to [fallbackPresets] on any failure or an
  /// empty result so the add-network flow always has something to show.
  Future<List<ServerPreset>> fetchPresetsOrFallback() async {
    try {
      final presets = await fetchPresets();
      if (presets.isEmpty) {
        return fallbackPresets;
      }
      // Guarantee the DBase default is always offered, at the top if absent.
      final hasDbase = presets.any(
        (preset) => preset.networkName.toLowerCase() == 'dbase',
      );
      if (hasDbase) {
        return presets;
      }
      return List<ServerPreset>.unmodifiable([fallbackPreset, ...presets]);
    } catch (_) {
      return fallbackPresets;
    }
  }

  static Future<String> _defaultHttpGet(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Server presets request failed: HTTP ${response.statusCode}',
          uri: url,
        );
      }
      return response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

import 'package:androidircx/core/models/network_config.dart';

class ParsedIrcUrl {
  const ParsedIrcUrl({
    required this.protocol,
    required this.server,
    required this.port,
    required this.ssl,
    required this.isValid,
    this.nick,
    this.altNick,
    this.realName,
    this.ident,
    this.password,
    this.channel,
    this.channelKey,
    this.error,
  });

  final String protocol;
  final String server;
  final int port;
  final bool ssl;
  final bool isValid;
  final String? nick;
  final String? altNick;
  final String? realName;
  final String? ident;
  final String? password;
  final String? channel;
  final String? channelKey;
  final String? error;
}

bool isIrcUrl(String url) {
  final trimmed = url.trim().toLowerCase();
  return trimmed.startsWith('irc://') || trimmed.startsWith('ircs://');
}

ParsedIrcUrl parseIrcUrl(String url) {
  ParsedIrcUrl invalid(String error) => ParsedIrcUrl(
        protocol: 'irc',
        server: '',
        port: 6667,
        ssl: false,
        isValid: false,
        error: error,
      );

  if (url.trim().isEmpty) {
    return invalid('URL is empty or invalid');
  }

  final match = RegExp(r'^(irc|ircs):\/\/', caseSensitive: false).firstMatch(url.trim());
  if (match == null) {
    return invalid('Invalid IRC URL format. Expected: irc:// or ircs://');
  }

  final protocol = match.group(1)!.toLowerCase();
  final ssl = protocol == 'ircs';
  final defaultPort = ssl ? 6697 : 6667;
  var remaining = url.trim().substring(match.group(0)!.length);

  final queryParams = <String, String>{};
  final queryIndex = remaining.indexOf('?');
  if (queryIndex != -1) {
    final query = remaining.substring(queryIndex + 1);
    remaining = remaining.substring(0, queryIndex);
    for (final entry in Uri.splitQueryString(query).entries) {
      queryParams[entry.key.toLowerCase()] = entry.value;
    }
  }

  String? channel;
  String? channelKey;
  final slashIndex = remaining.indexOf('/');
  if (slashIndex != -1) {
    final channelPart = remaining.substring(slashIndex + 1);
    remaining = remaining.substring(0, slashIndex);
    if (channelPart.isNotEmpty) {
      final parts = channelPart.split(',');
      channel = Uri.decodeComponent(parts.first.trim());
      if (channel.isNotEmpty && !channel.startsWith('#')) {
        channel = '#$channel';
      }
      if (parts.length > 1) {
        channelKey = Uri.decodeComponent(parts[1].trim());
      }
    }
  }

  String? nick;
  String? password;
  final atIndex = remaining.lastIndexOf('@');
  if (atIndex != -1) {
    final authPart = remaining.substring(0, atIndex);
    remaining = remaining.substring(atIndex + 1);
    final colonIndex = authPart.indexOf(':');
    if (colonIndex != -1) {
      nick = Uri.decodeComponent(authPart.substring(0, colonIndex).trim());
      password = Uri.decodeComponent(authPart.substring(colonIndex + 1).trim());
    } else {
      nick = Uri.decodeComponent(authPart.trim());
    }
  }

  late final String server;
  var port = defaultPort;

  if (remaining.startsWith('[')) {
    final closeBracket = remaining.indexOf(']');
    if (closeBracket == -1) {
      return invalid('Invalid IPv6 address format. Missing closing bracket.');
    }
    server = remaining.substring(1, closeBracket);
    remaining = remaining.substring(closeBracket + 1);
    if (remaining.startsWith(':')) {
      final rawPort = remaining.substring(1);
      final parsedPort = int.tryParse(rawPort);
      if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
        return invalid('Invalid port: $rawPort. Must be 1-65535.');
      }
      port = parsedPort;
    }
  } else {
    final colonIndex = remaining.lastIndexOf(':');
    if (colonIndex != -1) {
      server = remaining.substring(0, colonIndex).trim();
      final rawPort = remaining.substring(colonIndex + 1).trim();
      final parsedPort = int.tryParse(rawPort);
      if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
        return invalid('Invalid port: $rawPort. Must be 1-65535.');
      }
      port = parsedPort;
    } else {
      server = remaining.trim();
    }
  }

  if (server.isEmpty) {
    return invalid('Server hostname is missing');
  }

  return ParsedIrcUrl(
    protocol: protocol,
    server: server,
    port: port,
    ssl: ssl,
    isValid: true,
    nick: queryParams['nick'] ?? nick,
    altNick: queryParams['altnick'] ?? queryParams['alt_nick'],
    realName: queryParams['realname'] ?? queryParams['real_name'],
    ident: queryParams['ident'],
    password: password,
    channel: channel,
    channelKey: channelKey,
  );
}

String getIrcUrlDisplayName(ParsedIrcUrl parsedUrl) {
  if (!parsedUrl.isValid) {
    return 'invalid URL';
  }

  final parts = <String>[parsedUrl.server];
  if (parsedUrl.port != (parsedUrl.ssl ? 6697 : 6667)) {
    parts.add(':${parsedUrl.port}');
  }
  if ((parsedUrl.channel ?? '').isNotEmpty) {
    parts.add(' / ${parsedUrl.channel}');
  }
  return parts.join();
}

NetworkConfig toTemporaryNetworkConfig(
  ParsedIrcUrl parsedUrl, {
  String defaultNickname = 'AndroidIRCX',
  String defaultAltNickname = 'AndroidIRCX_',
  String defaultRealName = 'AndroidIRCX',
  String defaultUsername = 'androidircx',
}) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return NetworkConfig(
    id: 'temp_${timestamp}_${parsedUrl.server}',
    name: parsedUrl.server,
    host: parsedUrl.server,
    port: parsedUrl.port,
    nickname: parsedUrl.nick ?? defaultNickname,
    altNickname: parsedUrl.altNick ?? defaultAltNickname,
    realName: parsedUrl.realName ?? defaultRealName,
    username: parsedUrl.ident ?? defaultUsername,
    useTls: parsedUrl.ssl,
    password: parsedUrl.password,
  );
}

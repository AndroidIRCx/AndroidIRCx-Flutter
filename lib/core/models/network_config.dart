import 'package:androidircx/core/security/secret_redaction.dart';

enum SaslMechanism { plain, scramSha256, external }

class NetworkConfig {
  const NetworkConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.nickname,
    this.altNickname,
    this.username = 'androidircx',
    this.realName = 'AndroidIRCX',
    this.useTls = true,
    this.webSocketPort,
    this.webSocketPath,
    this.password,
    this.saslAccount,
    this.saslPassword,
    this.saslMechanism = SaslMechanism.plain,
    this.autoConnect = false,
    this.autoJoinChannels = const <String>[],
    this.autoJoinChannelKeys = const <String, String>{},
    this.profileLabel,
    this.profileGroup,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String nickname;
  final String? altNickname;
  final String username;
  final String realName;
  final bool useTls;
  final int? webSocketPort;
  final String? webSocketPath;
  final String? password;
  final String? saslAccount;
  final String? saslPassword;
  final SaslMechanism saslMechanism;
  final bool autoConnect;
  final List<String> autoJoinChannels;
  final Map<String, String> autoJoinChannelKeys;
  final String? profileLabel;
  final String? profileGroup;

  NetworkConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? nickname,
    String? altNickname,
    String? username,
    String? realName,
    bool? useTls,
    int? webSocketPort,
    String? webSocketPath,
    String? password,
    String? saslAccount,
    String? saslPassword,
    SaslMechanism? saslMechanism,
    bool? autoConnect,
    List<String>? autoJoinChannels,
    Map<String, String>? autoJoinChannelKeys,
    String? profileLabel,
    String? profileGroup,
  }) {
    return NetworkConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      nickname: nickname ?? this.nickname,
      altNickname: altNickname ?? this.altNickname,
      username: username ?? this.username,
      realName: realName ?? this.realName,
      useTls: useTls ?? this.useTls,
      webSocketPort: webSocketPort ?? this.webSocketPort,
      webSocketPath: webSocketPath ?? this.webSocketPath,
      password: password ?? this.password,
      saslAccount: saslAccount ?? this.saslAccount,
      saslPassword: saslPassword ?? this.saslPassword,
      saslMechanism: saslMechanism ?? this.saslMechanism,
      autoConnect: autoConnect ?? this.autoConnect,
      autoJoinChannels: autoJoinChannels ?? this.autoJoinChannels,
      autoJoinChannelKeys: autoJoinChannelKeys ?? this.autoJoinChannelKeys,
      profileLabel: profileLabel ?? this.profileLabel,
      profileGroup: profileGroup ?? this.profileGroup,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'nickname': nickname,
      'altNickname': altNickname,
      'username': username,
      'realName': realName,
      'useTls': useTls,
      'webSocketPort': webSocketPort,
      'webSocketPath': webSocketPath,
      'password': password,
      'saslAccount': saslAccount,
      'saslPassword': saslPassword,
      'saslMechanism': saslMechanism.name,
      'autoConnect': autoConnect,
      'autoJoinChannels': autoJoinChannels,
      'autoJoinChannelKeys': autoJoinChannelKeys,
      'profileLabel': profileLabel,
      'profileGroup': profileGroup,
    };
  }

  Map<String, Object?> toRedactedJson() {
    return redactNetworkSecrets(toJson());
  }

  @override
  String toString() {
    return 'NetworkConfig(${toRedactedJson()})';
  }

  factory NetworkConfig.fromJson(Map<String, Object?> json) {
    return NetworkConfig(
      id: json['id']! as String,
      name: json['name']! as String,
      host: json['host']! as String,
      port: (json['port']! as num).toInt(),
      nickname: json['nickname']! as String,
      altNickname: json['altNickname'] as String?,
      username: (json['username'] as String?) ?? 'androidircx',
      realName: (json['realName'] as String?) ?? 'AndroidIRCX',
      useTls: (json['useTls'] as bool?) ?? true,
      webSocketPort: (json['webSocketPort'] as num?)?.toInt(),
      webSocketPath: json['webSocketPath'] as String?,
      password: json['password'] as String?,
      saslAccount: json['saslAccount'] as String?,
      saslPassword: json['saslPassword'] as String?,
      saslMechanism: json['saslMechanism'] == null
          ? SaslMechanism.plain
          : SaslMechanism.values.byName(json['saslMechanism']! as String),
      autoConnect: (json['autoConnect'] as bool?) ?? false,
      autoJoinChannels: _stringList(json['autoJoinChannels']),
      autoJoinChannelKeys: _channelKeyMap(json['autoJoinChannelKeys']),
      profileLabel: _nonEmptyString(json['profileLabel']),
      profileGroup: _nonEmptyString(json['profileGroup']),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }

    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, String> _channelKeyMap(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    value.forEach((rawChannel, rawKey) {
      if (rawChannel is! String || rawKey is! String) {
        return;
      }
      final trimmedChannel = rawChannel.trim();
      final trimmedKey = rawKey.trim();
      if (trimmedChannel.isEmpty || trimmedKey.isEmpty) {
        return;
      }
      final channel = trimmedChannel.startsWith('#')
          ? trimmedChannel
          : '#$trimmedChannel';
      result[channel] = trimmedKey;
    });
    return Map<String, String>.unmodifiable(result);
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

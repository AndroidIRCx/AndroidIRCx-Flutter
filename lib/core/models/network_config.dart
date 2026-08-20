import 'package:androidircx/core/security/secret_redaction.dart';

enum SaslMechanism { plain, scramSha256, external }

enum ServiceAuthFallback { disabled, nickServ }

enum IrcProxyType { none, socks5 }

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
    this.useClientCertificate = false,
    this.serviceAuthFallback = ServiceAuthFallback.disabled,
    this.serviceAuthTarget = 'NickServ',
    this.autoConnect = false,
    this.autoJoinChannels = const <String>[],
    this.autoJoinChannelKeys = const <String, String>{},
    this.proxyType = IrcProxyType.none,
    this.proxyHost,
    this.proxyPort,
    this.proxyUsername,
    this.proxyPassword,
    this.profileLabel,
    this.profileGroup,
    this.identityProfileId,
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

  /// Whether this network authenticates with a stored client certificate
  /// (SASL EXTERNAL / CertFP). The certificate and private key themselves live
  /// in secure storage, never in this config.
  final bool useClientCertificate;
  final ServiceAuthFallback serviceAuthFallback;
  final String serviceAuthTarget;
  final bool autoConnect;
  final List<String> autoJoinChannels;
  final Map<String, String> autoJoinChannelKeys;
  final IrcProxyType proxyType;
  final String? proxyHost;
  final int? proxyPort;
  final String? proxyUsername;
  final String? proxyPassword;
  final String? profileLabel;
  final String? profileGroup;

  /// Optional id of the attached [IdentityProfile] whose nick/realname/ident/
  /// SASL account override this network's identity on connect.
  final String? identityProfileId;

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
    bool? useClientCertificate,
    ServiceAuthFallback? serviceAuthFallback,
    String? serviceAuthTarget,
    bool? autoConnect,
    List<String>? autoJoinChannels,
    Map<String, String>? autoJoinChannelKeys,
    IrcProxyType? proxyType,
    String? proxyHost,
    int? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
    String? profileLabel,
    String? profileGroup,
    String? identityProfileId,
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
      useClientCertificate: useClientCertificate ?? this.useClientCertificate,
      serviceAuthFallback: serviceAuthFallback ?? this.serviceAuthFallback,
      serviceAuthTarget: serviceAuthTarget ?? this.serviceAuthTarget,
      autoConnect: autoConnect ?? this.autoConnect,
      autoJoinChannels: autoJoinChannels ?? this.autoJoinChannels,
      autoJoinChannelKeys: autoJoinChannelKeys ?? this.autoJoinChannelKeys,
      proxyType: proxyType ?? this.proxyType,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: proxyPort ?? this.proxyPort,
      proxyUsername: proxyUsername ?? this.proxyUsername,
      proxyPassword: proxyPassword ?? this.proxyPassword,
      profileLabel: profileLabel ?? this.profileLabel,
      profileGroup: profileGroup ?? this.profileGroup,
      identityProfileId: identityProfileId ?? this.identityProfileId,
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
      'useClientCertificate': useClientCertificate,
      'serviceAuthFallback': serviceAuthFallback.name,
      'serviceAuthTarget': serviceAuthTarget,
      'autoConnect': autoConnect,
      'autoJoinChannels': autoJoinChannels,
      'autoJoinChannelKeys': autoJoinChannelKeys,
      'proxyType': proxyType.name,
      'proxyHost': proxyHost,
      'proxyPort': proxyPort,
      'proxyUsername': proxyUsername,
      'proxyPassword': proxyPassword,
      'profileLabel': profileLabel,
      'profileGroup': profileGroup,
      'identityProfileId': identityProfileId,
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
      saslMechanism: _enumByName(
        SaslMechanism.values,
        json['saslMechanism'],
        SaslMechanism.plain,
      ),
      useClientCertificate: (json['useClientCertificate'] as bool?) ?? false,
      serviceAuthFallback: _enumByName(
        ServiceAuthFallback.values,
        json['serviceAuthFallback'],
        ServiceAuthFallback.disabled,
      ),
      serviceAuthTarget:
          _nonEmptyString(json['serviceAuthTarget']) ?? 'NickServ',
      autoConnect: (json['autoConnect'] as bool?) ?? false,
      autoJoinChannels: _stringList(json['autoJoinChannels']),
      autoJoinChannelKeys: _channelKeyMap(json['autoJoinChannelKeys']),
      proxyType: _enumByName(
        IrcProxyType.values,
        json['proxyType'],
        IrcProxyType.none,
      ),
      proxyHost: _nonEmptyString(json['proxyHost']),
      proxyPort: (json['proxyPort'] as num?)?.toInt(),
      proxyUsername: _nonEmptyString(json['proxyUsername']),
      proxyPassword: json['proxyPassword'] as String?,
      profileLabel: _nonEmptyString(json['profileLabel']),
      profileGroup: _nonEmptyString(json['profileGroup']),
      identityProfileId: _nonEmptyString(json['identityProfileId']),
    );
  }

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    Object? value,
    T fallback,
  ) {
    if (value is! String) {
      return fallback;
    }

    for (final entry in values) {
      if (entry.name == value) {
        return entry;
      }
    }
    return fallback;
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

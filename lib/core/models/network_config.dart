enum SaslMechanism {
  plain,
  scramSha256,
}

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
    this.password,
    this.saslAccount,
    this.saslPassword,
    this.saslMechanism = SaslMechanism.plain,
    this.autoConnect = false,
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
  final String? password;
  final String? saslAccount;
  final String? saslPassword;
  final SaslMechanism saslMechanism;
  final bool autoConnect;

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
    String? password,
    String? saslAccount,
    String? saslPassword,
    SaslMechanism? saslMechanism,
    bool? autoConnect,
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
      password: password ?? this.password,
      saslAccount: saslAccount ?? this.saslAccount,
      saslPassword: saslPassword ?? this.saslPassword,
      saslMechanism: saslMechanism ?? this.saslMechanism,
      autoConnect: autoConnect ?? this.autoConnect,
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
      'password': password,
      'saslAccount': saslAccount,
      'saslPassword': saslPassword,
      'saslMechanism': saslMechanism.name,
      'autoConnect': autoConnect,
    };
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
      password: json['password'] as String?,
      saslAccount: json['saslAccount'] as String?,
      saslPassword: json['saslPassword'] as String?,
      saslMechanism: json['saslMechanism'] == null
          ? SaslMechanism.plain
          : SaslMechanism.values.byName(json['saslMechanism']! as String),
      autoConnect: (json['autoConnect'] as bool?) ?? false,
    );
  }
}

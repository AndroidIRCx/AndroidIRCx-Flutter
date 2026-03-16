class NetworkConfig {
  const NetworkConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.nickname,
    this.username = 'androidircx',
    this.realName = 'AndroidIRCX',
    this.useTls = true,
    this.password,
    this.autoConnect = false,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String nickname;
  final String username;
  final String realName;
  final bool useTls;
  final String? password;
  final bool autoConnect;

  NetworkConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? nickname,
    String? username,
    String? realName,
    bool? useTls,
    String? password,
    bool? autoConnect,
  }) {
    return NetworkConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      nickname: nickname ?? this.nickname,
      username: username ?? this.username,
      realName: realName ?? this.realName,
      useTls: useTls ?? this.useTls,
      password: password ?? this.password,
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
      'username': username,
      'realName': realName,
      'useTls': useTls,
      'password': password,
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
      username: (json['username'] as String?) ?? 'androidircx',
      realName: (json['realName'] as String?) ?? 'AndroidIRCX',
      useTls: (json['useTls'] as bool?) ?? true,
      password: json['password'] as String?,
      autoConnect: (json['autoConnect'] as bool?) ?? false,
    );
  }
}

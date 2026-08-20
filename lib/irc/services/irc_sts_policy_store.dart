import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class IrcStsPolicy {
  const IrcStsPolicy({
    required this.host,
    required this.port,
    required this.durationSeconds,
    required this.expiresAt,
    this.preload = false,
  });

  final String host;
  final int port;
  final int durationSeconds;
  final DateTime expiresAt;
  final bool preload;

  bool isActive(DateTime now) => expiresAt.isAfter(now);

  IrcStsPolicy reschedule(DateTime now) {
    return IrcStsPolicy(
      host: host,
      port: port,
      durationSeconds: durationSeconds,
      expiresAt: now.add(Duration(seconds: durationSeconds)),
      preload: preload,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'host': host,
      'port': port,
      'durationSeconds': durationSeconds,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'preload': preload,
    };
  }

  factory IrcStsPolicy.fromJson(Map<String, Object?> json) {
    return IrcStsPolicy(
      host: _normalizeHost(json['host']! as String),
      port: (json['port']! as num).toInt(),
      durationSeconds: (json['durationSeconds']! as num).toInt(),
      expiresAt: DateTime.parse(json['expiresAt']! as String).toUtc(),
      preload: (json['preload'] as bool?) ?? false,
    );
  }
}

abstract class IrcStsPolicyStore {
  Future<IrcStsPolicy?> loadPolicy(String host);
  Future<void> savePolicy(IrcStsPolicy policy);
  Future<void> deletePolicy(String host);
}

class InMemoryIrcStsPolicyStore implements IrcStsPolicyStore {
  final Map<String, IrcStsPolicy> _policies = <String, IrcStsPolicy>{};

  @override
  Future<IrcStsPolicy?> loadPolicy(String host) async {
    return _policies[_normalizeHost(host)];
  }

  @override
  Future<void> savePolicy(IrcStsPolicy policy) async {
    _policies[_normalizeHost(policy.host)] = policy;
  }

  @override
  Future<void> deletePolicy(String host) async {
    _policies.remove(_normalizeHost(host));
  }
}

class SharedPrefsIrcStsPolicyStore implements IrcStsPolicyStore {
  SharedPrefsIrcStsPolicyStore({IrcStsPolicyStore? fallback})
    : _fallback = fallback ?? InMemoryIrcStsPolicyStore();

  static const _storagePrefix = 'androidircx.irc.sts.';

  final IrcStsPolicyStore _fallback;

  @override
  Future<IrcStsPolicy?> loadPolicy(String host) async {
    final prefs = await _sharedPreferencesOrNull();
    if (prefs == null) {
      return _fallback.loadPolicy(host);
    }

    final raw = prefs.getString(_key(host));
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return IrcStsPolicy.fromJson(decoded);
    } on Object {
      await prefs.remove(_key(host));
      return null;
    }
  }

  @override
  Future<void> savePolicy(IrcStsPolicy policy) async {
    final prefs = await _sharedPreferencesOrNull();
    if (prefs == null) {
      await _fallback.savePolicy(policy);
      return;
    }

    await prefs.setString(_key(policy.host), jsonEncode(policy.toJson()));
  }

  @override
  Future<void> deletePolicy(String host) async {
    final prefs = await _sharedPreferencesOrNull();
    if (prefs == null) {
      await _fallback.deletePolicy(host);
      return;
    }

    await prefs.remove(_key(host));
  }

  Future<SharedPreferences?> _sharedPreferencesOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } on Object {
      return null;
    }
  }

  String _key(String host) => '$_storagePrefix${_normalizeHost(host)}';
}

String _normalizeHost(String host) => host.trim().toLowerCase();

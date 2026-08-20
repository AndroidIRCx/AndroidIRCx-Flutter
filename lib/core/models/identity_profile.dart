import 'package:androidircx/core/models/network_config.dart';

/// A reusable identity/connection profile that can be attached to a network to
/// override its nick/realname/ident and SASL account on connect.
///
/// Mirrors the old app's `IdentityProfile`. Secret values (SASL/NickServ/oper
/// passwords) are intentionally not stored here — they stay in the network's
/// secure storage — so profiles remain non-secret and export-safe.
class IdentityProfile {
  const IdentityProfile({
    required this.id,
    required this.name,
    required this.nick,
    this.altNick,
    this.realName,
    this.ident,
    this.saslAccount,
    this.saslMechanism,
    this.onConnectCommands = const <String>[],
  });

  final String id;
  final String name;
  final String nick;
  final String? altNick;
  final String? realName;
  final String? ident;
  final String? saslAccount;
  final SaslMechanism? saslMechanism;
  final List<String> onConnectCommands;

  static const String defaultProfileId = 'androidircx-default-profile';

  /// The old app's built-in default identity.
  static const IdentityProfile defaultProfile = IdentityProfile(
    id: defaultProfileId,
    name: 'AndroidIRCX',
    nick: 'AndroidIRCX',
    altNick: 'AndroidIRCX_',
    realName: 'AndroidIRCX User',
    ident: 'androidircx',
  );

  IdentityProfile copyWith({
    String? id,
    String? name,
    String? nick,
    String? altNick,
    String? realName,
    String? ident,
    String? saslAccount,
    SaslMechanism? saslMechanism,
    List<String>? onConnectCommands,
  }) {
    return IdentityProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      nick: nick ?? this.nick,
      altNick: altNick ?? this.altNick,
      realName: realName ?? this.realName,
      ident: ident ?? this.ident,
      saslAccount: saslAccount ?? this.saslAccount,
      saslMechanism: saslMechanism ?? this.saslMechanism,
      onConnectCommands: onConnectCommands ?? this.onConnectCommands,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'nick': nick,
      'altNick': altNick,
      'realName': realName,
      'ident': ident,
      'saslAccount': saslAccount,
      'saslMechanism': saslMechanism?.name,
      'onConnectCommands': onConnectCommands,
    };
  }

  factory IdentityProfile.fromJson(Map<String, Object?> json) {
    return IdentityProfile(
      id: json['id']! as String,
      name: json['name']! as String,
      nick: json['nick']! as String,
      altNick: _nonEmpty(json['altNick']),
      realName: _nonEmpty(json['realName']),
      ident: _nonEmpty(json['ident']),
      saslAccount: _nonEmpty(json['saslAccount']),
      saslMechanism: _mechanism(json['saslMechanism']),
      onConnectCommands: _stringList(json['onConnectCommands']),
    );
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static SaslMechanism? _mechanism(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final mechanism in SaslMechanism.values) {
      if (mechanism.name == value) {
        return mechanism;
      }
    }
    return null;
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
}

/// Returns a copy of [network] with the identity fields from [profile] applied.
///
/// Only non-empty profile fields override the network; the profile reference is
/// recorded via [NetworkConfig.identityProfileId]. SASL passwords remain on the
/// network. This is the connect-time resolution used before a session starts.
NetworkConfig applyIdentityProfile(
  NetworkConfig network,
  IdentityProfile profile,
) {
  return network.copyWith(
    identityProfileId: profile.id,
    nickname: profile.nick.trim().isEmpty ? network.nickname : profile.nick,
    altNickname: (profile.altNick ?? '').trim().isEmpty
        ? network.altNickname
        : profile.altNick,
    realName: (profile.realName ?? '').trim().isEmpty
        ? network.realName
        : profile.realName,
    username: (profile.ident ?? '').trim().isEmpty
        ? network.username
        : profile.ident,
    saslAccount: (profile.saslAccount ?? '').trim().isEmpty
        ? network.saslAccount
        : profile.saslAccount,
    saslMechanism: profile.saslMechanism ?? network.saslMechanism,
  );
}

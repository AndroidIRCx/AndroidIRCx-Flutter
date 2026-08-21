import 'dart:convert';

/// The kinds of automatic-mode user lists. Each grants a channel mode to a
/// matching user when they join a channel where we hold the needed privilege.
enum UserListType {
  autoOp('autoop', 'o', 'Auto-op'),
  autoHalfOp('autohalfop', 'h', 'Auto-halfop'),
  autoVoice('autovoice', 'v', 'Auto-voice');

  const UserListType(this.id, this.modeChar, this.label);

  /// Stable storage id.
  final String id;

  /// The channel mode letter this list grants (`o`, `h`, `v`).
  final String modeChar;

  /// Human-readable label.
  final String label;

  static UserListType? fromId(String id) {
    for (final type in UserListType.values) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
  }
}

/// A single automatic-mode rule: grant [type]'s mode to users matching [mask]
/// in the given [channels] (empty = all channels) on the given [network]
/// (null = all networks).
class UserListEntry {
  const UserListEntry({
    required this.type,
    required this.mask,
    this.channels = const <String>[],
    this.network,
  });

  final UserListType type;

  /// A `nick`, `nick!user@host`, or wildcard mask (`*` / `?`). A bare nick is
  /// treated as `nick!*@*`.
  final String mask;

  /// Channels this rule applies to (case-insensitive). Empty means all.
  final List<String> channels;

  /// Network id this rule applies to; null means all networks.
  final String? network;

  /// Normalizes [mask] to full `nick!user@host` form for matching.
  String get normalizedMask {
    final trimmed = mask.trim();
    if (trimmed.isEmpty) {
      return '*!*@*';
    }
    if (!trimmed.contains('!') && !trimmed.contains('@')) {
      return '$trimmed!*@*';
    }
    return trimmed;
  }

  bool appliesToNetwork(String? networkId) =>
      network == null || network == networkId;

  bool appliesToChannel(String channel) {
    if (channels.isEmpty) {
      return true;
    }
    final target = channel.toLowerCase();
    return channels.any((c) => c.trim().toLowerCase() == target);
  }

  /// Whether this rule matches the given user on [channel]/[networkId].
  bool matches({
    required String nick,
    String? ident,
    String? host,
    required String channel,
    String? networkId,
  }) {
    if (!appliesToNetwork(networkId) || !appliesToChannel(channel)) {
      return false;
    }
    final target =
        '${nick.trim()}!${(ident ?? '*').trim()}@${(host ?? '*').trim()}';
    return maskMatches(normalizedMask, target);
  }

  UserListEntry copyWith({
    UserListType? type,
    String? mask,
    List<String>? channels,
    String? network,
    bool clearNetwork = false,
  }) {
    return UserListEntry(
      type: type ?? this.type,
      mask: mask ?? this.mask,
      channels: channels ?? this.channels,
      network: clearNetwork ? null : (network ?? this.network),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.id,
    'mask': mask,
    if (channels.isNotEmpty) 'channels': channels,
    if (network != null) 'network': network,
  };

  static UserListEntry? fromJson(Map<String, dynamic> json) {
    final type = UserListType.fromId('${json['type']}');
    final mask = (json['mask'] as String?)?.trim() ?? '';
    if (type == null || mask.isEmpty) {
      return null;
    }
    final rawChannels = json['channels'];
    final channels = rawChannels is List
        ? rawChannels.map((e) => '$e').where((e) => e.isNotEmpty).toList()
        : const <String>[];
    return UserListEntry(
      type: type,
      mask: mask,
      channels: channels,
      network: (json['network'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['network'] as String).trim(),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Stable identity used for de-duplication and removal.
  String get key =>
      '${type.id}|${network ?? '*'}|${normalizedMask.toLowerCase()}|'
      '${(List<String>.from(channels)..sort()).join(',').toLowerCase()}';
}

/// Case-insensitive IRC mask matching with `*` (any run) and `?` (one char).
bool maskMatches(String mask, String target) {
  final pattern = StringBuffer('^');
  for (final rune in mask.runes) {
    final char = String.fromCharCode(rune);
    switch (char) {
      case '*':
        pattern.write('.*');
      case '?':
        pattern.write('.');
      default:
        pattern.write(RegExp.escape(char));
    }
  }
  pattern.write(r'$');
  return RegExp(
    pattern.toString(),
    caseSensitive: false,
  ).hasMatch(target.trim());
}

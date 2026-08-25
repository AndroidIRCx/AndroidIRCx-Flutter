import 'dart:convert';

/// The kinds of user lists supported by the IRC client.
///
/// Auto-mode entries grant channel modes on join. Notify/protected/other are
/// local watch lists. Blacklist entries may also carry an enforcement action.
enum UserListType {
  autoOp('autoop', 'o', 'Auto-op'),
  autoHalfOp('autohalfop', 'h', 'Auto-halfop'),
  autoVoice('autovoice', 'v', 'Auto-voice'),
  notify('notify', null, 'Notify'),
  protectedUser('protected', null, 'Protected'),
  other('other', null, 'Other'),
  blacklist('blacklist', null, 'Blacklist');

  const UserListType(this.id, this.modeChar, this.label);

  /// Stable storage id.
  final String id;

  /// The channel mode letter this list grants (`o`, `h`, `v`) for auto-mode
  /// entries. Null for local/watch-list-only entries.
  final String? modeChar;

  /// Human-readable label.
  final String label;

  bool get isAutoMode => modeChar != null;

  static const List<UserListType> autoModeTypes = <UserListType>[
    autoOp,
    autoHalfOp,
    autoVoice,
  ];

  static const List<UserListType> managementTypes = <UserListType>[
    autoOp,
    autoHalfOp,
    autoVoice,
    notify,
    protectedUser,
    other,
    blacklist,
  ];

  static UserListType? fromId(String id) {
    for (final type in UserListType.values) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
  }
}

enum BlacklistAction {
  ignore('ignore', 'Ignore'),
  ban('ban', 'Ban'),
  kickBan('kick_ban', 'Kick + ban'),
  quiet('quiet', 'Quiet'),
  custom('custom', 'Custom raw');

  const BlacklistAction(this.id, this.label);

  final String id;
  final String label;

  static BlacklistAction? fromId(String id) {
    for (final action in BlacklistAction.values) {
      if (action.id == id) {
        return action;
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
    this.blacklistAction,
    this.reason,
    this.duration,
    this.customRaw,
  });

  final UserListType type;

  /// A `nick`, `nick!user@host`, or wildcard mask (`*` / `?`). A bare nick is
  /// treated as `nick!*@*`.
  final String mask;

  /// Channels this rule applies to (case-insensitive). Empty means all.
  final List<String> channels;

  /// Network id this rule applies to; null means all networks.
  final String? network;

  /// Enforcement action for [UserListType.blacklist]. Defaults to ignore when
  /// absent.
  final BlacklistAction? blacklistAction;

  /// Optional reason used for blacklist and kick/ban flows.
  final String? reason;

  /// Optional action duration. For moderation actions this is used as timed
  /// unban/unquiet duration; for custom raw it feeds the `{duration}` token.
  final Duration? duration;

  /// Custom raw IRC template for [BlacklistAction.custom].
  final String? customRaw;

  BlacklistAction get effectiveBlacklistAction =>
      blacklistAction ?? BlacklistAction.ignore;

  bool get isBlacklist => type == UserListType.blacklist;

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
    BlacklistAction? blacklistAction,
    String? reason,
    Duration? duration,
    String? customRaw,
    bool clearNetwork = false,
    bool clearBlacklistAction = false,
    bool clearReason = false,
    bool clearDuration = false,
    bool clearCustomRaw = false,
  }) {
    return UserListEntry(
      type: type ?? this.type,
      mask: mask ?? this.mask,
      channels: channels ?? this.channels,
      network: clearNetwork ? null : (network ?? this.network),
      blacklistAction: clearBlacklistAction
          ? null
          : (blacklistAction ?? this.blacklistAction),
      reason: clearReason ? null : (reason ?? this.reason),
      duration: clearDuration ? null : (duration ?? this.duration),
      customRaw: clearCustomRaw ? null : (customRaw ?? this.customRaw),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.id,
    'mask': mask,
    if (channels.isNotEmpty) 'channels': channels,
    if (network != null) 'network': network,
    if (blacklistAction != null) 'blacklistAction': blacklistAction!.id,
    if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
    if (duration != null && duration!.inMinutes > 0)
      'durationMinutes': duration!.inMinutes,
    if ((customRaw ?? '').trim().isNotEmpty) 'customRaw': customRaw!.trim(),
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
    final durationMinutes = (json['durationMinutes'] as num?)?.toInt();
    return UserListEntry(
      type: type,
      mask: mask,
      channels: channels,
      network: (json['network'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['network'] as String).trim(),
      blacklistAction: BlacklistAction.fromId(
        '${json['blacklistAction'] ?? json['action'] ?? ''}',
      ),
      reason: (json['reason'] as String?)?.trim(),
      duration: durationMinutes == null || durationMinutes <= 0
          ? null
          : Duration(minutes: durationMinutes),
      customRaw: (json['customRaw'] as String?)?.trim(),
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

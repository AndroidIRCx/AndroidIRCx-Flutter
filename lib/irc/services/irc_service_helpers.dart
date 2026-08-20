import 'package:androidircx/irc/models/irc_message_frame.dart';

enum IrcServiceKind {
  nickServ,
  chanServ,
  hostServ,
  memoServ,
  botServ,
  operServ,
  q,
  x,
  generic,
}

enum IrcServiceFamily { anope, atheme, ircu, srvx, generic }

enum IrcBouncerFamily { znc, soju, generic }

class IrcServiceDetection {
  const IrcServiceDetection({
    required this.nick,
    required this.kind,
    required this.family,
    this.host,
  });

  final String nick;
  final IrcServiceKind kind;
  final IrcServiceFamily family;
  final String? host;

  bool get isNickService => kind == IrcServiceKind.nickServ;
}

class ServiceIdentifyCommand {
  const ServiceIdentifyCommand({
    required this.target,
    required this.command,
    required this.redactedCommand,
  });

  final String target;
  final String command;
  final String redactedCommand;
}

class IrcBouncerCompatibilityReport {
  const IrcBouncerCompatibilityReport({
    required this.family,
    required this.summary,
    this.supportsPlayback = false,
    this.supportsNetworkManagement = false,
    this.supportsReadMarkers = false,
  });

  final IrcBouncerFamily family;
  final String summary;
  final bool supportsPlayback;
  final bool supportsNetworkManagement;
  final bool supportsReadMarkers;
}

IrcServiceDetection? detectIrcService(IrcMessageFrame frame) {
  return detectIrcServicePrefix(frame.prefix);
}

IrcServiceDetection? detectIrcServicePrefix(String? prefix) {
  final parsed = _parsePrefix(prefix);
  final nick = parsed.nick;
  if (nick == null || nick.isEmpty) {
    return null;
  }

  final kind = _serviceKindForNick(nick);
  if (kind == null) {
    return null;
  }

  return IrcServiceDetection(
    nick: nick,
    kind: kind,
    family: _serviceFamilyForHost(parsed.host),
    host: parsed.host,
  );
}

ServiceIdentifyCommand buildNickServIdentifyCommand({
  required String password,
  String? account,
  String target = 'NickServ',
}) {
  final trimmedTarget = target.trim().isEmpty ? 'NickServ' : target.trim();
  final trimmedAccount = (account ?? '').trim();
  final trimmedPassword = password.trim();
  final command = trimmedAccount.isEmpty
      ? 'IDENTIFY $trimmedPassword'
      : 'IDENTIFY $trimmedAccount $trimmedPassword';
  final redactedCommand = trimmedAccount.isEmpty
      ? 'IDENTIFY [REDACTED]'
      : 'IDENTIFY $trimmedAccount [REDACTED]';
  return ServiceIdentifyCommand(
    target: trimmedTarget,
    command: command,
    redactedCommand: redactedCommand,
  );
}

IrcBouncerCompatibilityReport detectBouncerCompatibility({
  required Set<String> availableCapabilities,
  required Set<String> enabledCapabilities,
  String? serverName,
  String? networkName,
}) {
  final available = availableCapabilities.map((item) => item.toLowerCase());
  final enabled = enabledCapabilities.map((item) => item.toLowerCase());
  final allCaps = <String>{...available, ...enabled};
  final source = '${serverName ?? ''} ${networkName ?? ''}'.toLowerCase();

  if (allCaps.any((cap) => cap.startsWith('soju.im/')) ||
      source.contains('soju')) {
    return IrcBouncerCompatibilityReport(
      family: IrcBouncerFamily.soju,
      summary:
          'soju detected; CHATHISTORY and bouncer network caps are preferred.',
      supportsPlayback:
          allCaps.contains('chathistory') ||
          allCaps.contains('draft/chathistory'),
      supportsNetworkManagement:
          allCaps.contains('soju.im/bouncer-networks') ||
          allCaps.contains('soju.im/bouncer-networks-notify'),
      supportsReadMarkers:
          allCaps.contains('soju.im/read') ||
          allCaps.contains('draft/read-marker'),
    );
  }

  if (allCaps.any((cap) => cap.startsWith('znc.in/')) ||
      source.contains('znc')) {
    return IrcBouncerCompatibilityReport(
      family: IrcBouncerFamily.znc,
      summary:
          'ZNC detected; playback batches and status buffers are supported.',
      supportsPlayback:
          allCaps.contains('znc.in/playback') || allCaps.contains('batch'),
    );
  }

  return IrcBouncerCompatibilityReport(
    family: IrcBouncerFamily.generic,
    summary: 'Generic IRC server; use advertised IRCv3 capabilities.',
    supportsPlayback:
        allCaps.contains('chathistory') ||
        allCaps.contains('draft/chathistory') ||
        allCaps.contains('batch'),
    supportsReadMarkers: allCaps.contains('draft/read-marker'),
  );
}

({String? nick, String? host}) _parsePrefix(String? prefix) {
  final value = (prefix ?? '').trim();
  if (value.isEmpty) {
    return (nick: null, host: null);
  }

  final bangIndex = value.indexOf('!');
  if (bangIndex == -1) {
    return (nick: value, host: null);
  }

  final nick = value.substring(0, bangIndex);
  final atIndex = value.indexOf('@', bangIndex + 1);
  final host = atIndex == -1 ? null : value.substring(atIndex + 1);
  return (nick: nick, host: host);
}

IrcServiceKind? _serviceKindForNick(String nick) {
  return switch (nick.toLowerCase()) {
    'nickserv' => IrcServiceKind.nickServ,
    'chanserv' => IrcServiceKind.chanServ,
    'hostserv' => IrcServiceKind.hostServ,
    'memoserv' => IrcServiceKind.memoServ,
    'botserv' => IrcServiceKind.botServ,
    'operserv' => IrcServiceKind.operServ,
    'q' => IrcServiceKind.q,
    'x' => IrcServiceKind.x,
    _ => null,
  };
}

IrcServiceFamily _serviceFamilyForHost(String? host) {
  final value = (host ?? '').toLowerCase();
  if (value.contains('anope')) {
    return IrcServiceFamily.anope;
  }
  if (value.contains('atheme')) {
    return IrcServiceFamily.atheme;
  }
  if (value.contains('undernet') || value.endsWith('.users.undernet.org')) {
    return IrcServiceFamily.ircu;
  }
  if (value.contains('srvx')) {
    return IrcServiceFamily.srvx;
  }
  return IrcServiceFamily.generic;
}

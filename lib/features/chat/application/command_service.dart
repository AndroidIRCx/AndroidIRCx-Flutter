import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CommandAlias {
  const CommandAlias({required this.alias, required this.command});

  final String alias;
  final String command;
}

enum CommandSuggestionSource { command, alias, history }

class CommandSuggestion {
  const CommandSuggestion({
    required this.text,
    required this.source,
    this.description,
    this.usage,
  });

  final String text;
  final CommandSuggestionSource source;
  final String? description;
  final String? usage;
}

enum CommandKind {
  channel,
  message,
  query,
  status,
  capability,
  service,
  dcc,
  local,
  operator,
  utility,
}

class CommandDefinition {
  const CommandDefinition({
    required this.name,
    required this.usage,
    required this.description,
    required this.kind,
    this.requiresTarget = false,
  });

  final String name;
  final String usage;
  final String description;
  final CommandKind kind;
  final bool requiresTarget;
}

class CommandHistoryEntry {
  const CommandHistoryEntry({
    required this.id,
    required this.command,
    required this.timestamp,
  });

  final String id;
  final String command;
  final DateTime timestamp;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'command': command,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory CommandHistoryEntry.fromJson(Map<String, Object?> json) {
    return CommandHistoryEntry(
      id: json['id']! as String,
      command: json['command']! as String,
      timestamp: DateTime.parse(json['timestamp']! as String),
    );
  }
}

class CommandService {
  static const _historyKey = 'androidircx.commandHistory';
  static const _maxHistory = 50;

  static const Map<String, String> serviceAliases = {
    'nickserv': 'NickServ',
    'chanserv': 'ChanServ',
    'hostserv': 'HostServ',
    'operserv': 'OperServ',
    'memoserv': 'MemoServ',
    'botserv': 'BotServ',
  };

  static const List<CommandDefinition> _defaultCommands = [
    CommandDefinition(
      name: 'join',
      usage: '/join <channel> [key]',
      description: 'Join a channel',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'part',
      usage: '/part [channel] [message]',
      description: 'Leave a channel',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'quit',
      usage: '/quit [message]',
      description: 'Disconnect from IRC',
      kind: CommandKind.status,
    ),
    CommandDefinition(
      name: 'nick',
      usage: '/nick <nickname>',
      description: 'Change nickname',
      kind: CommandKind.status,
    ),
    CommandDefinition(
      name: 'msg',
      usage: '/msg <nick|channel> <message>',
      description: 'Send a private message',
      kind: CommandKind.message,
    ),
    CommandDefinition(
      name: 'query',
      usage: '/query <nick>',
      description: 'Open a private chat',
      kind: CommandKind.local,
    ),
    CommandDefinition(
      name: 'notice',
      usage: '/notice <nick|channel> <message>',
      description: 'Send a notice',
      kind: CommandKind.message,
    ),
    CommandDefinition(
      name: 'me',
      usage: '/me <action>',
      description: 'Send a CTCP ACTION to the current target',
      kind: CommandKind.message,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'action',
      usage: '/action <text>',
      description: 'Send a CTCP ACTION to the current target',
      kind: CommandKind.message,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'ctcp',
      usage: '/ctcp <nick|channel> <command> [args]',
      description: 'Send a CTCP request',
      kind: CommandKind.message,
    ),
    CommandDefinition(
      name: 'topic',
      usage: '/topic [channel] [topic]',
      description: 'Show or set channel topic',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'mode',
      usage: '/mode <target> [modes] [args]',
      description: 'Show or change user/channel modes',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'op',
      usage: '/op <nick>',
      description: 'Give channel operator status',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'deop',
      usage: '/deop <nick>',
      description: 'Remove channel operator status',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'voice',
      usage: '/voice <nick>',
      description: 'Give channel voice',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'devoice',
      usage: '/devoice <nick>',
      description: 'Remove channel voice',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'ban',
      usage: '/ban <nick|mask> [channel]',
      description: 'Ban a nick or mask from a channel',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'unban',
      usage: '/unban <mask> [channel]',
      description: 'Remove a channel ban',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'kick',
      usage: '/kick <nick> [reason]',
      description: 'Kick a user from the current channel',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'kickban',
      usage: '/kickban <nick> [reason]',
      description: 'Ban and kick a user from the current channel',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'invite',
      usage: '/invite <nick> [channel]',
      description: 'Invite a user to a channel',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'banlist',
      usage: '/banlist',
      description: 'Show the current channel ban list',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'exceptlist',
      usage: '/exceptlist',
      description: 'Show the current channel exception list',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'invitelist',
      usage: '/invitelist',
      description: 'Show the current channel invite-exception list',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'quietlist',
      usage: '/quietlist',
      description: 'Show the current channel quiet list',
      kind: CommandKind.channel,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'whois',
      usage: '/whois <nick> [server]',
      description: 'Request WHOIS information',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'whowas',
      usage: '/whowas <nick> [count] [server]',
      description: 'Request WHOWAS information',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'who',
      usage: '/who [mask]',
      description: 'Request WHO information',
      kind: CommandKind.query,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'names',
      usage: '/names [channel]',
      description: 'List users in a channel',
      kind: CommandKind.query,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'list',
      usage: '/list [channel|options]',
      description: 'List channels on the server',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'chathistory',
      usage: '/chathistory [latest|before|after|around] [msgid|limit] [limit]',
      description: 'Request IRCv3 chat history for the current tab',
      kind: CommandKind.capability,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'lusers',
      usage: '/lusers [server]',
      description: 'Request server user statistics',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'motd',
      usage: '/motd [server]',
      description: 'Request the message of the day',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'time',
      usage: '/time [server]',
      description: 'Request server time',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'version',
      usage: '/version [server]',
      description: 'Request server version',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'admin',
      usage: '/admin [server]',
      description: 'Request server admin information',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'links',
      usage: '/links [mask]',
      description: 'List linked servers',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'stats',
      usage: '/stats [query] [server]',
      description: 'Request server statistics',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'info',
      usage: '/info [server]',
      description: 'Request server information',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'rules',
      usage: '/rules [server]',
      description: 'Request server rules',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'servlist',
      usage: '/servlist [mask] [type]',
      description: 'List IRC services',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'ping',
      usage: '/ping [server|token]',
      description: 'Send an IRC PING',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'trace',
      usage: '/trace [server]',
      description: 'Request route tracing',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'userip',
      usage: '/userip <nick>',
      description: 'Request a user IP address when supported',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'users',
      usage: '/users [server]',
      description: 'Request users from the server',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'watch',
      usage: '/watch <+nick|-nick|list>',
      description: 'Use legacy WATCH user monitoring',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'knock',
      usage: '/knock <channel> [message]',
      description: 'Request an invite to a channel',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'squery',
      usage: '/squery <service> <message>',
      description: 'Send a service query',
      kind: CommandKind.service,
    ),
    CommandDefinition(
      name: 'away',
      usage: '/away [message]',
      description: 'Set or clear away status',
      kind: CommandKind.status,
    ),
    CommandDefinition(
      name: 'back',
      usage: '/back',
      description: 'Clear away status',
      kind: CommandKind.status,
    ),
    CommandDefinition(
      name: 'disconnect',
      usage: '/disconnect [message]',
      description: 'Disconnect from IRC',
      kind: CommandKind.status,
    ),
    CommandDefinition(
      name: 'cap',
      usage: '/cap <subcommand> [args]',
      description: 'Send an IRCv3 CAP command',
      kind: CommandKind.capability,
    ),
    CommandDefinition(
      name: 'monitor',
      usage: '/monitor <subcommand> [nick ...]',
      description: 'Send an IRCv3 MONITOR command',
      kind: CommandKind.capability,
    ),
    CommandDefinition(
      name: 'ison',
      usage: '/ison <nick> [nick ...]',
      description: 'Check whether users are online',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'userhost',
      usage: '/userhost <nick> [nick ...]',
      description: 'Request user host information',
      kind: CommandKind.query,
    ),
    CommandDefinition(
      name: 'setname',
      usage: '/setname <real name>',
      description: 'Change real name through IRCv3 setname',
      kind: CommandKind.capability,
    ),
    CommandDefinition(
      name: 'metadata',
      usage: '/metadata <target> <get|set|list|clear> [key] [value]',
      description: 'Send an IRCv3 METADATA command',
      kind: CommandKind.capability,
    ),
    CommandDefinition(
      name: 'rename',
      usage: '/rename <new-channel-name> [reason]',
      description: 'Rename the current channel when supported',
      kind: CommandKind.capability,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'dccchat',
      usage: '/dccchat <nick>',
      description: 'Offer DCC CHAT to a nick',
      kind: CommandKind.dcc,
    ),
    CommandDefinition(
      name: 'dccsend',
      usage: '/dccsend <nick> <file path>',
      description: 'Offer DCC SEND to a nick',
      kind: CommandKind.dcc,
    ),
    CommandDefinition(
      name: 'dccresume',
      usage: '/dccresume [offset]',
      description: 'Send DCC RESUME for the active DCC SEND tab',
      kind: CommandKind.dcc,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'dccaccept',
      usage: '/dccaccept [offset]',
      description: 'Send DCC ACCEPT for the active DCC SEND tab',
      kind: CommandKind.dcc,
      requiresTarget: true,
    ),
    CommandDefinition(
      name: 'raw',
      usage: '/raw <irc command>',
      description: 'Send a raw IRC command',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'quote',
      usage: '/quote <irc command>',
      description: 'Send a raw IRC command',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'clear',
      usage: '/clear',
      description: 'Clear messages in the current tab',
      kind: CommandKind.local,
    ),
    CommandDefinition(
      name: 'close',
      usage: '/close',
      description: 'Close the current tab',
      kind: CommandKind.local,
    ),
    CommandDefinition(
      name: 'echo',
      usage: '/echo <message>',
      description: 'Print a local-only message in the current tab',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'help',
      usage: '/help [command]',
      description: 'List commands or show help for one command',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'ignore',
      usage: '/ignore [nick|mask]',
      description: 'Ignore a nick or nick!user@host mask, or list ignores',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'unignore',
      usage: '/unignore <nick|mask>',
      description: 'Stop ignoring a nick or mask',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'amsg',
      usage: '/amsg <message>',
      description: 'Send a message to all joined channels',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'ame',
      usage: '/ame <action>',
      description: 'Send a CTCP ACTION to all joined channels',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'dns',
      usage: '/dns <nick>',
      description: 'Resolve a nick host from known data or the server',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'clones',
      usage: '/clones [channel]',
      description: 'Detect users sharing the same host in a channel',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'reconnect',
      usage: '/reconnect',
      description: 'Reconnect the current network',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'filter',
      usage: '/filter [-g] <text>',
      description: 'Hide incoming messages containing text, or list filters',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'unfilter',
      usage: '/unfilter <text>',
      description: 'Remove a message filter',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'window',
      usage: '/window [-a] <name>',
      description: 'Open a tab, or activate an existing one with -a',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'timer',
      usage: '/timer <name> <delay_ms> <repetitions> <command>',
      description: 'Run a command after a delay (0 repetitions = forever)',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'cnotice',
      usage: '/cnotice <nick> <channel> <message>',
      description: 'Send a channel notice',
      kind: CommandKind.message,
    ),
    CommandDefinition(
      name: 'cprivmsg',
      usage: '/cprivmsg <nick> <channel> <message>',
      description: 'Send a channel private message',
      kind: CommandKind.message,
    ),
    CommandDefinition(
      name: 'oper',
      usage: '/oper <name> <password>',
      description: 'Authenticate as an IRC operator',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'rehash',
      usage: '/rehash',
      description: 'Ask the server to rehash configuration',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'squit',
      usage: '/squit <server> [reason]',
      description: 'Disconnect a linked server',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'kill',
      usage: '/kill <nick> <reason>',
      description: 'Kill a user connection',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'connect',
      usage: '/connect <server> <port> [remote]',
      description: 'Ask the IRC server to connect to another server',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'die',
      usage: '/die',
      description: 'Ask the server to shut down',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'wallops',
      usage: '/wallops <message>',
      description: 'Send WALLOPS',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'locops',
      usage: '/locops <message>',
      description: 'Send LOCOPS',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'globops',
      usage: '/globops <message>',
      description: 'Send GLOBOPS',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'adchat',
      usage: '/adchat <message>',
      description: 'Send ADCHAT',
      kind: CommandKind.operator,
    ),
    CommandDefinition(
      name: 'nickserv',
      usage: '/nickserv <command>',
      description: 'Send a command to NickServ',
      kind: CommandKind.service,
    ),
    CommandDefinition(
      name: 'chanserv',
      usage: '/chanserv <command>',
      description: 'Send a command to ChanServ',
      kind: CommandKind.service,
    ),
    CommandDefinition(
      name: 'hostserv',
      usage: '/hostserv <command>',
      description: 'Send a command to HostServ',
      kind: CommandKind.service,
    ),
    CommandDefinition(
      name: 'operserv',
      usage: '/operserv <command>',
      description: 'Send a command to OperServ',
      kind: CommandKind.service,
    ),
    CommandDefinition(
      name: 'memoserv',
      usage: '/memoserv <command>',
      description: 'Send a command to MemoServ',
      kind: CommandKind.service,
    ),
    CommandDefinition(
      name: 'botserv',
      usage: '/botserv <command>',
      description: 'Send a command to BotServ',
      kind: CommandKind.service,
    ),
    CommandDefinition(
      name: 'autovoice',
      usage: '/autovoice <nick|mask> [#chan,#chan]',
      description: 'Auto-voice matching users on join',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'unautovoice',
      usage: '/unautovoice <nick|mask>',
      description: 'Remove an auto-voice rule',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'autoop',
      usage: '/autoop <nick|mask> [#chan,#chan]',
      description: 'Auto-op matching users on join',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'unautoop',
      usage: '/unautoop <nick|mask>',
      description: 'Remove an auto-op rule',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'autohalfop',
      usage: '/autohalfop <nick|mask> [#chan,#chan]',
      description: 'Auto-halfop matching users on join',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'unautohalfop',
      usage: '/unautohalfop <nick|mask>',
      description: 'Remove an auto-halfop rule',
      kind: CommandKind.channel,
    ),
    CommandDefinition(
      name: 'autolist',
      usage: '/autolist',
      description: 'List configured auto-mode rules',
      kind: CommandKind.local,
    ),
    CommandDefinition(
      name: 'notify',
      usage: '/notify <nick|mask>',
      description: 'Add a nick to the notify/watch list',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'unnotify',
      usage: '/unnotify <nick|mask>',
      description: 'Remove a nick from the notify/watch list',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'protect',
      usage: '/protect <nick|mask>',
      description: 'Add a user to the protected list',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'unprotect',
      usage: '/unprotect <nick|mask>',
      description: 'Remove a user from the protected list',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'blacklist',
      usage:
          '/blacklist <nick|mask> [ignore|ban|kick_ban|quiet|custom] [reason]',
      description: 'Add a blacklist rule and optional enforcement action',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'unblacklist',
      usage: '/unblacklist <nick|mask>',
      description: 'Remove a blacklist rule',
      kind: CommandKind.utility,
    ),
    CommandDefinition(
      name: 'userlist',
      usage: '/userlist [notify|protected|other|blacklist|autoop|autovoice]',
      description: 'List user-list entries',
      kind: CommandKind.local,
    ),
  ];

  static final Map<String, CommandDefinition> _commandRegistry = {
    for (final command in _defaultCommands) command.name: command,
  };

  final Map<String, CommandAlias> _aliases = {
    'j': const CommandAlias(alias: 'j', command: '/join'),
    'p': const CommandAlias(alias: 'p', command: '/part'),
    'q': const CommandAlias(alias: 'q', command: '/quit'),
    'w': const CommandAlias(alias: 'w', command: '/whois'),
    'n': const CommandAlias(alias: 'n', command: '/nick'),
    'm': const CommandAlias(alias: 'm', command: '/msg'),
    'a': const CommandAlias(alias: 'a', command: '/me'),
    'k': const CommandAlias(alias: 'k', command: '/kick'),
    'kb': const CommandAlias(alias: 'kb', command: '/kickban'),
    'ns': const CommandAlias(alias: 'ns', command: '/nickserv'),
    'cs': const CommandAlias(alias: 'cs', command: '/chanserv'),
    'hs': const CommandAlias(alias: 'hs', command: '/hostserv'),
    'os': const CommandAlias(alias: 'os', command: '/operserv'),
    'ms': const CommandAlias(alias: 'ms', command: '/memoserv'),
    'bs': const CommandAlias(alias: 'bs', command: '/botserv'),
  };

  List<CommandHistoryEntry> _history = const [];

  List<CommandHistoryEntry> get history =>
      List<CommandHistoryEntry>.unmodifiable(_history);

  List<CommandDefinition> get commands =>
      List<CommandDefinition>.unmodifiable(_defaultCommands);

  CommandDefinition? getCommand(String name) =>
      _commandRegistry[name.toLowerCase()];

  bool isKnownCommand(String name) => getCommand(name) != null;

  /// Returns slash-command suggestions for the first token in [input].
  ///
  /// Suggestions are only produced for a slash-prefixed command prefix and are
  /// drawn from the command registry plus default/service aliases. Matching is
  /// case-insensitive, de-duplicated by displayed text, and sorted
  /// deterministically so UI callers do not need to duplicate MessageInput logic.
  List<CommandSuggestion> suggestCommands(String input, {int limit = 8}) {
    final prefix = _slashCommandPrefix(input);
    if (prefix == null) {
      return const [];
    }

    final normalizedPrefix = prefix.toLowerCase();
    final suggestions = <CommandSuggestion>[];
    final seen = <String>{};

    void add(CommandSuggestion suggestion) {
      final key = suggestion.text.toLowerCase();
      if (seen.add(key)) {
        suggestions.add(suggestion);
      }
    }

    final commandMatches =
        _defaultCommands
            .where(
              (command) =>
                  '/${command.name}'.toLowerCase().startsWith(normalizedPrefix),
            )
            .map(
              (command) => CommandSuggestion(
                text: '/${command.name}',
                source: CommandSuggestionSource.command,
                description: command.description,
                usage: command.usage,
              ),
            )
            .toList(growable: false)
          ..sort(_compareSuggestionsByText);

    final aliasMatches =
        _aliases.values
            .where(
              (alias) =>
                  '/${alias.alias}'.toLowerCase().startsWith(normalizedPrefix),
            )
            .map(
              (alias) => CommandSuggestion(
                text: '/${alias.alias}',
                source: CommandSuggestionSource.alias,
                description: alias.command,
              ),
            )
            .toList(growable: false)
          ..sort(_compareSuggestionsByText);

    final allMatches = [...commandMatches, ...aliasMatches]
      ..sort(_compareSuggestionsByText);

    for (final suggestion in allMatches) {
      add(suggestion);
      if (suggestions.length >= limit) {
        return List<CommandSuggestion>.unmodifiable(suggestions);
      }
    }

    return List<CommandSuggestion>.unmodifiable(suggestions);
  }

  /// Returns recent slash-command history entries matching [input], newest first.
  ///
  /// History suggestions are intentionally separate from command suggestions so
  /// callers can merge/render them without this helper mutating stored history.
  List<CommandSuggestion> suggestHistory(String input, {int limit = 6}) {
    final prefix = _slashCommandPrefix(input);
    if (prefix == null) {
      return const [];
    }

    final normalizedPrefix = prefix.toLowerCase();
    final seen = <String>{};
    final suggestions = <CommandSuggestion>[];
    for (final entry in _history) {
      if (!entry.command.toLowerCase().startsWith(normalizedPrefix)) {
        continue;
      }
      if (!seen.add(entry.command.toLowerCase())) {
        continue;
      }
      suggestions.add(
        CommandSuggestion(
          text: entry.command,
          source: CommandSuggestionSource.history,
        ),
      );
      if (suggestions.length >= limit) {
        break;
      }
    }
    return List<CommandSuggestion>.unmodifiable(suggestions);
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) {
      _history = const [];
      return;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    _history = decoded
        .map(
          (item) => CommandHistoryEntry.fromJson(item as Map<String, Object?>),
        )
        .toList(growable: false);
  }

  Future<void> addToHistory(String command) async {
    final now = DateTime.now();
    final entry = CommandHistoryEntry(
      id: '${now.microsecondsSinceEpoch}',
      command: command,
      timestamp: now,
    );
    _history = [entry, ..._history].take(_maxHistory).toList(growable: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(_history.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  String normalizeCommand(String input) {
    if (!input.startsWith('/')) {
      return input;
    }

    final parts = input.split(' ');
    final head = parts.first.substring(1).toLowerCase();
    final alias = _aliases[head];
    if (alias == null) {
      return input;
    }

    final tail = parts.length > 1 ? ' ${parts.skip(1).join(' ')}' : '';
    return '${alias.command}$tail';
  }

  String? toRawCommand(String input, {String? currentTarget}) {
    final normalized = normalizeCommand(input.trim());
    if (!normalized.startsWith('/')) {
      return null;
    }

    final commandLine = normalized.substring(1).trim();
    if (commandLine.isEmpty) {
      return null;
    }

    final firstSpace = commandLine.indexOf(RegExp(r'\s'));
    final command =
        (firstSpace == -1 ? commandLine : commandLine.substring(0, firstSpace))
            .toLowerCase();
    final rest = firstSpace == -1
        ? ''
        : commandLine.substring(firstSpace + 1).trim();
    if (!isKnownCommand(command)) {
      return null;
    }

    final parts = rest.isEmpty ? const <String>[] : rest.split(RegExp(r'\s+'));
    final channelTarget = _isChannelName(currentTarget) ? currentTarget : null;

    switch (command) {
      case 'join':
        return rest.isEmpty ? null : 'JOIN $rest';
      case 'part':
        final target = parts.isNotEmpty && _isChannelName(parts.first)
            ? parts.first
            : channelTarget;
        if (target == null) {
          return null;
        }
        final reasonParts = parts.isNotEmpty && _isChannelName(parts.first)
            ? parts.skip(1)
            : parts;
        final reason = reasonParts.join(' ');
        return reason.isEmpty ? 'PART $target' : 'PART $target :$reason';
      case 'quit':
        return rest.isEmpty ? 'QUIT' : 'QUIT :$rest';
      case 'nick':
        return rest.isEmpty ? null : 'NICK ${parts.first}';
      case 'msg':
        return _messageRaw('PRIVMSG', rest);
      case 'query':
        return null;
      case 'notice':
        return _messageRaw('NOTICE', rest);
      case 'me':
      case 'action':
        if (rest.isEmpty || currentTarget == null || currentTarget.isEmpty) {
          return null;
        }
        return 'PRIVMSG $currentTarget :\u0001ACTION $rest\u0001';
      case 'ctcp':
        return _ctcpRaw(rest);
      case 'topic':
        final target = parts.isNotEmpty && _isChannelName(parts.first)
            ? parts.first
            : channelTarget;
        if (target == null) {
          return null;
        }
        final topicParts = parts.isNotEmpty && _isChannelName(parts.first)
            ? parts.skip(1)
            : parts;
        final topic = topicParts.join(' ');
        return topic.isEmpty ? 'TOPIC $target' : 'TOPIC $target :$topic';
      case 'mode':
        if (rest.isEmpty) {
          return currentTarget == null || currentTarget.isEmpty
              ? null
              : 'MODE $currentTarget';
        }
        return _isModeTarget(parts.first) || currentTarget == null
            ? 'MODE $rest'
            : 'MODE $currentTarget $rest';
      case 'op':
        return _channelModeShortcut('+o', parts, channelTarget);
      case 'deop':
        return _channelModeShortcut('-o', parts, channelTarget);
      case 'voice':
        return _channelModeShortcut('+v', parts, channelTarget);
      case 'devoice':
        return _channelModeShortcut('-v', parts, channelTarget);
      case 'ban':
        return _channelModeShortcut(
          '+b',
          parts,
          channelTarget,
          normalizeBanMask: true,
        );
      case 'unban':
        return _channelModeShortcut('-b', parts, channelTarget);
      case 'kick':
        return _kickRaw(parts, channelTarget);
      case 'kickban':
        return null;
      case 'invite':
        return _inviteRaw(parts, channelTarget);
      case 'banlist':
        return channelTarget == null ? null : 'MODE $channelTarget +b';
      case 'exceptlist':
        return channelTarget == null ? null : 'MODE $channelTarget +e';
      case 'invitelist':
        return channelTarget == null ? null : 'MODE $channelTarget +I';
      case 'quietlist':
        return channelTarget == null ? null : 'MODE $channelTarget +q';
      case 'whois':
        return rest.isEmpty ? null : 'WHOIS $rest';
      case 'whowas':
        return rest.isEmpty ? null : 'WHOWAS $rest';
      case 'who':
        final target = rest.isEmpty ? currentTarget : rest;
        return target == null || target.isEmpty ? null : 'WHO $target';
      case 'names':
        final target = rest.isEmpty ? currentTarget : rest;
        return target == null || target.isEmpty ? null : 'NAMES $target';
      case 'list':
        return rest.isEmpty ? 'LIST' : 'LIST $rest';
      case 'chathistory':
        return _chatHistoryRaw(rest, channelTarget);
      case 'lusers':
        return _simpleRaw('LUSERS', rest);
      case 'motd':
        return _simpleRaw('MOTD', rest);
      case 'time':
        return _simpleRaw('TIME', rest);
      case 'version':
        return _simpleRaw('VERSION', rest);
      case 'admin':
        return _simpleRaw('ADMIN', rest);
      case 'links':
        return _simpleRaw('LINKS', rest);
      case 'stats':
        return _simpleRaw('STATS', rest);
      case 'info':
        return _simpleRaw('INFO', rest);
      case 'rules':
        return _simpleRaw('RULES', rest);
      case 'servlist':
        return _simpleRaw('SERVLIST', rest);
      case 'ping':
        return _simpleRaw('PING', rest);
      case 'trace':
        return _simpleRaw('TRACE', rest);
      case 'userip':
        return rest.isEmpty ? null : 'USERIP $rest';
      case 'users':
        return _simpleRaw('USERS', rest);
      case 'watch':
        return rest.isEmpty ? null : 'WATCH $rest';
      case 'knock':
        return _knockRaw(parts);
      case 'squery':
        return _serviceQueryRaw(rest);
      case 'away':
        return rest.isEmpty ? 'AWAY' : 'AWAY :$rest';
      case 'back':
        return 'AWAY';
      case 'disconnect':
        return rest.isEmpty ? 'QUIT' : 'QUIT :$rest';
      case 'cap':
        return rest.isEmpty ? null : 'CAP $rest';
      case 'monitor':
        return rest.isEmpty ? null : 'MONITOR $rest';
      case 'ison':
        return rest.isEmpty ? null : 'ISON $rest';
      case 'userhost':
        return rest.isEmpty ? null : 'USERHOST $rest';
      case 'setname':
        return rest.isEmpty ? null : 'SETNAME :$rest';
      case 'metadata':
        return _metadataRaw(parts);
      case 'rename':
        return _renameRaw(parts, channelTarget);
      case 'raw':
      case 'quote':
        return rest.isEmpty ? null : rest;
      case 'clear':
      case 'close':
      case 'dccchat':
      case 'dccsend':
      case 'dccresume':
      case 'dccaccept':
        return null;
      case 'cnotice':
        return _channelMessageRaw('CNOTICE', rest);
      case 'cprivmsg':
        return _channelMessageRaw('CPRIVMSG', rest);
      case 'oper':
        return parts.length < 2 ? null : 'OPER ${parts[0]} ${parts[1]}';
      case 'rehash':
        return 'REHASH';
      case 'squit':
        return _firstWithOptionalReason('SQUIT', parts);
      case 'kill':
        return _firstWithRequiredReason('KILL', parts);
      case 'connect':
        return parts.length < 2 ? null : 'CONNECT $rest';
      case 'die':
        return 'DIE';
      case 'wallops':
        return rest.isEmpty ? null : 'WALLOPS :$rest';
      case 'locops':
        return rest.isEmpty ? null : 'LOCOPS :$rest';
      case 'globops':
        return rest.isEmpty ? null : 'GLOBOPS :$rest';
      case 'adchat':
        return rest.isEmpty ? null : 'ADCHAT :$rest';
      default:
        final service = serviceAliases[command];
        if (service != null && rest.isNotEmpty) {
          return 'PRIVMSG $service :$rest';
        }
        return null;
    }
  }

  static bool _isChannelName(String? value) {
    if (value == null || value.isEmpty) {
      return false;
    }
    return value.startsWith('#') ||
        value.startsWith('&') ||
        value.startsWith('+') ||
        value.startsWith('!');
  }

  static bool _isModeTarget(String value) {
    if (value.startsWith('+') || value.startsWith('-')) {
      return false;
    }
    return _isChannelName(value) ||
        value.startsWith('*') ||
        value.contains('.') ||
        value.contains('@');
  }

  static String? _slashCommandPrefix(String input) {
    final value = input.trimLeft();
    if (!value.startsWith('/')) {
      return null;
    }
    final firstToken = value.split(RegExp(r'\s+')).first;
    if (firstToken.length < 2) {
      return null;
    }
    return firstToken;
  }

  static int _compareSuggestionsByText(
    CommandSuggestion left,
    CommandSuggestion right,
  ) {
    final leftText = left.text.toLowerCase();
    final rightText = right.text.toLowerCase();
    final result = leftText.compareTo(rightText);
    return result == 0 ? left.text.compareTo(right.text) : result;
  }

  static String? _messageRaw(String verb, String rest) {
    final space = rest.indexOf(RegExp(r'\s'));
    if (space == -1) {
      return null;
    }
    final target = rest.substring(0, space).trim();
    final text = rest.substring(space + 1).trim();
    if (target.isEmpty || text.isEmpty) {
      return null;
    }
    return '$verb $target :$text';
  }

  static String _simpleRaw(String verb, String rest) {
    return rest.isEmpty ? verb : '$verb $rest';
  }

  static String? _ctcpRaw(String rest) {
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.first.isEmpty) {
      return null;
    }
    final target = parts.first;
    final command = parts[1].toUpperCase();
    final args = parts.length > 2 ? parts.skip(2).join(' ') : null;
    return 'PRIVMSG $target :\u0001$command${args == null || args.isEmpty ? '' : ' $args'}\u0001';
  }

  static String? _channelModeShortcut(
    String mode,
    List<String> parts,
    String? currentChannel, {
    bool normalizeBanMask = false,
  }) {
    if (parts.isEmpty) {
      return null;
    }
    final first = parts.first;
    final explicitChannel = parts.length > 1 && _isChannelName(parts[1])
        ? parts[1]
        : null;
    final channel = explicitChannel ?? currentChannel;
    if (channel == null) {
      return null;
    }
    final target = normalizeBanMask ? _banMask(first) : first;
    return 'MODE $channel $mode $target';
  }

  static String? _kickRaw(List<String> parts, String? currentChannel) {
    if (parts.isEmpty) {
      return null;
    }
    final hasExplicitChannel = _isChannelName(parts.first);
    final channel = hasExplicitChannel ? parts.first : currentChannel;
    if (channel == null) {
      return null;
    }
    final nickIndex = hasExplicitChannel ? 1 : 0;
    if (parts.length <= nickIndex) {
      return null;
    }
    final nick = parts[nickIndex];
    final reasonParts = parts.skip(nickIndex + 1).toList(growable: false);
    return reasonParts.isEmpty
        ? 'KICK $channel $nick'
        : 'KICK $channel $nick :${reasonParts.join(' ')}';
  }

  static String? _inviteRaw(List<String> parts, String? currentChannel) {
    if (parts.isEmpty) {
      return null;
    }
    final channel = parts.length > 1 && _isChannelName(parts[1])
        ? parts[1]
        : currentChannel;
    if (channel == null) {
      return null;
    }
    return 'INVITE ${parts.first} $channel';
  }

  static String? _chatHistoryRaw(String rest, String? target) {
    final parts = rest
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (target == null &&
        (parts.isEmpty || parts.first.toUpperCase() != 'TARGETS')) {
      return null;
    }
    if (parts.isEmpty) {
      return 'CHATHISTORY LATEST $target * 50';
    }
    final keyword = parts.first.toUpperCase();
    if (keyword == 'TARGETS') {
      if (parts.length < 3) {
        return null;
      }
      final limit = parts.length > 3 ? parts[3] : '50';
      return 'CHATHISTORY TARGETS ${_timestampHistorySelector(parts[1])} ${_timestampHistorySelector(parts[2])} $limit';
    }
    if (target == null) {
      return null;
    }
    if (keyword == 'BETWEEN') {
      if (parts.length < 3) {
        return null;
      }
      final limit = parts.length > 3 ? parts[3] : '50';
      return 'CHATHISTORY BETWEEN $target ${_historySelector(parts[1])} ${_historySelector(parts[2])} $limit';
    }
    if (keyword == 'LATEST') {
      if (parts.length == 1) {
        return 'CHATHISTORY LATEST $target * 50';
      }
      final secondAsLimit = int.tryParse(parts[1]);
      if (secondAsLimit != null) {
        return 'CHATHISTORY LATEST $target * ${parts[1]}';
      }
      final reference = _historySelector(parts[1]);
      final limit = parts.length > 2 ? parts[2] : '50';
      return 'CHATHISTORY LATEST $target $reference $limit';
    }
    if (keyword == 'BEFORE' || keyword == 'AFTER' || keyword == 'AROUND') {
      final reference = parts.length > 1 ? _historySelector(parts[1]) : '*';
      final limit = parts.length > 2 ? parts[2] : '50';
      return 'CHATHISTORY $keyword $target $reference $limit';
    }
    return 'CHATHISTORY LATEST $target * ${parts.first}';
  }

  static String? _knockRaw(List<String> parts) {
    if (parts.isEmpty || !_isChannelName(parts.first)) {
      return null;
    }
    final message = parts.skip(1).join(' ');
    return message.isEmpty
        ? 'KNOCK ${parts.first}'
        : 'KNOCK ${parts.first} :$message';
  }

  static String? _serviceQueryRaw(String rest) {
    final space = rest.indexOf(RegExp(r'\s'));
    if (space == -1) {
      return null;
    }
    final service = rest.substring(0, space).trim();
    final text = rest.substring(space + 1).trim();
    if (service.isEmpty || text.isEmpty) {
      return null;
    }
    return 'PRIVMSG $service :$text';
  }

  static String? _metadataRaw(List<String> parts) {
    if (parts.length < 2) {
      return null;
    }
    if (parts.length <= 3) {
      return 'METADATA ${parts.join(' ')}';
    }
    final head = parts.take(3).join(' ');
    final value = parts.skip(3).join(' ');
    return 'METADATA $head :$value';
  }

  static String? _renameRaw(List<String> parts, String? currentChannel) {
    if (currentChannel == null || parts.isEmpty) {
      return null;
    }
    final reason = parts.skip(1).join(' ');
    return reason.isEmpty
        ? 'RENAME $currentChannel ${parts.first}'
        : 'RENAME $currentChannel ${parts.first} :$reason';
  }

  static String? _channelMessageRaw(String verb, String rest) {
    final parts = rest.split(RegExp(r'\s+'));
    if (parts.length < 3) {
      return null;
    }
    final nick = parts.first;
    final channel = parts[1];
    final text = parts.skip(2).join(' ');
    return '$verb $nick $channel :$text';
  }

  static String? _firstWithOptionalReason(String verb, List<String> parts) {
    if (parts.isEmpty) {
      return null;
    }
    final reason = parts.skip(1).join(' ');
    return reason.isEmpty
        ? '$verb ${parts.first}'
        : '$verb ${parts.first} :$reason';
  }

  static String? _firstWithRequiredReason(String verb, List<String> parts) {
    if (parts.length < 2) {
      return null;
    }
    return '$verb ${parts.first} :${parts.skip(1).join(' ')}';
  }

  static String _banMask(String value) {
    return value.contains('!') || value.contains('@') ? value : '$value!*@*';
  }

  static String _historySelector(String value) {
    final trimmed = value.trim();
    if (trimmed == '*' || trimmed.isEmpty) {
      return '*';
    }
    final normalized = trimmed.toLowerCase();
    if (normalized.startsWith('msgid=') ||
        normalized.startsWith('timestamp=')) {
      return trimmed;
    }
    if (DateTime.tryParse(trimmed) != null) {
      return 'timestamp=$trimmed';
    }
    return 'msgid=$trimmed';
  }

  static String _timestampHistorySelector(String value) {
    final trimmed = value.trim();
    if (trimmed.toLowerCase().startsWith('timestamp=')) {
      return trimmed;
    }
    return 'timestamp=$trimmed';
  }
}

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

enum CommandKind { channel, message, query, status, capability, service }

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
      case 'notice':
        return _messageRaw('NOTICE', rest);
      case 'me':
        if (rest.isEmpty || currentTarget == null || currentTarget.isEmpty) {
          return null;
        }
        return 'PRIVMSG $currentTarget :\u0001ACTION $rest\u0001';
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
      case 'away':
        return rest.isEmpty ? 'AWAY' : 'AWAY :$rest';
      case 'back':
        return 'AWAY';
      case 'cap':
        return rest.isEmpty ? null : 'CAP $rest';
      case 'monitor':
        return rest.isEmpty ? null : 'MONITOR $rest';
      case 'ison':
        return rest.isEmpty ? null : 'ISON $rest';
      case 'userhost':
        return rest.isEmpty ? null : 'USERHOST $rest';
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
}

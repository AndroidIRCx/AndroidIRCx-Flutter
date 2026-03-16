import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CommandAlias {
  const CommandAlias({
    required this.alias,
    required this.command,
  });

  final String alias;
  final String command;
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

  List<CommandHistoryEntry> get history => List<CommandHistoryEntry>.unmodifiable(_history);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) {
      _history = const [];
      return;
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    _history = decoded
        .map((item) => CommandHistoryEntry.fromJson(item as Map<String, Object?>))
        .toList(growable: false);
  }

  Future<void> addToHistory(String command) async {
    final entry = CommandHistoryEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      command: command,
      timestamp: DateTime.now(),
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
}

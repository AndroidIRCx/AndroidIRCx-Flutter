import 'dart:math' as math;

import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/features/chat/application/message_history_formatter.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';

abstract class MessageHistoryRepository {
  Future<void> append({required String networkId, required IrcMessage message});

  Future<void> appendAll({
    required String networkId,
    required Iterable<IrcMessage> messages,
  });

  Future<List<IrcMessage>> loadTabHistory({
    required String networkId,
    required String tabId,
    int limit = 50,
    String? beforeMessageId,
  });

  Future<List<IrcMessage>> search({
    required String networkId,
    String? tabId,
    String query = '',
    Set<IrcMessageKind> kinds = const <IrcMessageKind>{},
    DateTime? from,
    DateTime? to,
    int limit = 100,
  });

  Future<String> exportTabHistory({
    required String networkId,
    required String tabId,
    String query = '',
    Set<IrcMessageKind> kinds = const <IrcMessageKind>{},
    DateTime? from,
    DateTime? to,
    int limit = 10000,
  });

  Future<void> enforceRetention({
    required String networkId,
    String? tabId,
    int? maxMessages,
    DateTime? deleteBefore,
  });

  Future<void> deleteTabHistory({
    required String networkId,
    required String tabId,
  });

  Future<void> deleteNetworkHistory(String networkId);
}

class InMemoryMessageHistoryRepository implements MessageHistoryRepository {
  final Map<String, Map<String, List<IrcMessage>>> _messages =
      <String, Map<String, List<IrcMessage>>>{};
  final Map<String, Set<String>> _msgids = <String, Set<String>>{};

  @override
  Future<void> append({
    required String networkId,
    required IrcMessage message,
  }) async {
    final networkMessages = _messages.putIfAbsent(
      networkId,
      () => <String, List<IrcMessage>>{},
    );
    final tabMessages = networkMessages.putIfAbsent(
      message.tabId,
      () => <IrcMessage>[],
    );
    final dedupeId = _dedupeId(message);
    if (dedupeId != null) {
      final ids = _msgids.putIfAbsent(
        _msgidKey(networkId, message.tabId),
        () => <String>{},
      );
      if (ids.contains(dedupeId)) {
        return;
      }
      ids.add(dedupeId);
    }

    tabMessages.add(
      message.networkId == networkId
          ? message
          : message.copyWith(networkId: networkId),
    );
  }

  @override
  Future<void> appendAll({
    required String networkId,
    required Iterable<IrcMessage> messages,
  }) async {
    for (final message in messages) {
      await append(networkId: networkId, message: message);
    }
  }

  @override
  Future<List<IrcMessage>> loadTabHistory({
    required String networkId,
    required String tabId,
    int limit = 50,
    String? beforeMessageId,
  }) async {
    final source = _messages[networkId]?[tabId] ?? const <IrcMessage>[];
    final normalizedLimit = limit.clamp(1, 1000);
    final beforeIndex = _anchorIndex(source, beforeMessageId) ?? source.length;
    final start = math.max(0, beforeIndex - normalizedLimit);
    return List<IrcMessage>.unmodifiable(source.sublist(start, beforeIndex));
  }

  @override
  Future<List<IrcMessage>> search({
    required String networkId,
    String? tabId,
    String query = '',
    Set<IrcMessageKind> kinds = const <IrcMessageKind>{},
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final normalizedLimit = limit.clamp(1, 10000);
    final normalizedQuery = formatIrcPlainText(
      query,
      collapseWhitespace: true,
    ).toLowerCase();
    final matches = <IrcMessage>[];

    for (final message in _messagesForSearch(networkId, tabId)) {
      if (kinds.isNotEmpty && !kinds.contains(message.kind)) {
        continue;
      }
      if (from != null && message.timestamp.isBefore(from)) {
        continue;
      }
      if (to != null && message.timestamp.isAfter(to)) {
        continue;
      }
      if (normalizedQuery.isNotEmpty &&
          !_messageSearchText(message).contains(normalizedQuery)) {
        continue;
      }
      matches.add(message);
      if (matches.length >= normalizedLimit) {
        break;
      }
    }

    return List<IrcMessage>.unmodifiable(matches);
  }

  @override
  Future<String> exportTabHistory({
    required String networkId,
    required String tabId,
    String query = '',
    Set<IrcMessageKind> kinds = const <IrcMessageKind>{},
    DateTime? from,
    DateTime? to,
    int limit = 10000,
  }) async {
    final messages = await search(
      networkId: networkId,
      tabId: tabId,
      query: query,
      kinds: kinds,
      from: from,
      to: to,
      limit: limit,
    );
    return messages.map(formatIrcMessagePlainText).join('\n');
  }

  @override
  Future<void> enforceRetention({
    required String networkId,
    String? tabId,
    int? maxMessages,
    DateTime? deleteBefore,
  }) async {
    final tabs = _messages[networkId];
    if (tabs == null) {
      return;
    }

    for (final entry in tabs.entries.toList(growable: false)) {
      if (tabId != null && entry.key != tabId) {
        continue;
      }

      var retained = entry.value;
      if (deleteBefore != null) {
        retained = retained
            .where((message) => !message.timestamp.isBefore(deleteBefore))
            .toList(growable: true);
      }
      if (maxMessages != null &&
          maxMessages > 0 &&
          retained.length > maxMessages) {
        retained = retained.sublist(retained.length - maxMessages);
      }
      tabs[entry.key] = retained;
      _rebuildMsgidIndex(networkId, entry.key);
    }
  }

  @override
  Future<void> deleteTabHistory({
    required String networkId,
    required String tabId,
  }) async {
    _messages[networkId]?.remove(tabId);
    _msgids.remove(_msgidKey(networkId, tabId));
  }

  @override
  Future<void> deleteNetworkHistory(String networkId) async {
    _messages.remove(networkId);
    _msgids.removeWhere((key, _) => key.startsWith('$networkId\x1f'));
  }

  Iterable<IrcMessage> _messagesForSearch(String networkId, String? tabId) {
    final tabs = _messages[networkId];
    if (tabs == null) {
      return const <IrcMessage>[];
    }
    if (tabId != null) {
      return tabs[tabId] ?? const <IrcMessage>[];
    }
    final all = <IrcMessage>[];
    for (final messages in tabs.values) {
      all.addAll(messages);
    }
    all.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return all;
  }

  int? _anchorIndex(List<IrcMessage> messages, String? beforeMessageId) {
    final anchor = (beforeMessageId ?? '').trim();
    if (anchor.isEmpty) {
      return null;
    }

    final index = messages.indexWhere(
      (message) => message.id == anchor || message.tags['msgid'] == anchor,
    );
    return index == -1 ? null : index;
  }

  String _messageSearchText(IrcMessage message) {
    return [
      message.sender,
      formatIrcPlainText(message.content),
      for (final attachment in message.attachments) ...[
        attachment.label,
        attachment.uri,
        attachment.mediaId,
        attachment.transferId,
        attachment.peerNick,
        attachment.fileName,
        attachment.direction,
        attachment.status,
      ],
    ].whereType<String>().join(' ').toLowerCase();
  }

  void _rebuildMsgidIndex(String networkId, String tabId) {
    final key = _msgidKey(networkId, tabId);
    final ids = <String>{};
    for (final message
        in _messages[networkId]?[tabId] ?? const <IrcMessage>[]) {
      final id = _dedupeId(message);
      if (id != null) {
        ids.add(id);
      }
    }
    if (ids.isEmpty) {
      _msgids.remove(key);
    } else {
      _msgids[key] = ids;
    }
  }

  String? _dedupeId(IrcMessage message) {
    final msgid = (message.tags['msgid'] ?? '').trim();
    return msgid.isEmpty ? null : msgid;
  }

  String _msgidKey(String networkId, String tabId) => '$networkId\x1f$tabId';
}

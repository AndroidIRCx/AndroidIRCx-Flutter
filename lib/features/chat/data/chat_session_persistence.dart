import 'dart:convert';

import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatSessionSnapshot {
  const ChatSessionSnapshot({
    required this.tabs,
    required this.messagesByTab,
    required this.activeTabId,
  });

  final List<ChatTab> tabs;
  final Map<String, List<IrcMessage>> messagesByTab;
  final String activeTabId;
}

class ChatSessionPersistence {
  ChatSessionPersistence({
    this.maxMessagesPerTab = 1000,
    this.retainMessagesAfter,
  });

  final int maxMessagesPerTab;
  final DateTime? retainMessagesAfter;

  Future<ChatSessionSnapshot?> load(String networkId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(networkId));
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, Object?>;
    final tabs = ((decoded['tabs'] as List<dynamic>?) ?? const [])
        .map((item) => ChatTab.fromJson(item as Map<String, Object?>))
        .toList();
    final messagesMap = <String, List<IrcMessage>>{};
    final rawMessages =
        (decoded['messagesByTab'] as Map<String, dynamic>?) ?? const {};
    for (final entry in rawMessages.entries) {
      messagesMap[entry.key] = _dedupeByMsgid(
        (entry.value as List<dynamic>)
            .map((item) => IrcMessage.fromJson(item as Map<String, Object?>))
            .toList(),
      );
    }

    return ChatSessionSnapshot(
      tabs: tabs,
      messagesByTab: messagesMap,
      activeTabId: (decoded['activeTabId'] as String?) ?? '',
    );
  }

  Future<void> save({
    required String networkId,
    required List<ChatTab> tabs,
    required Map<String, List<IrcMessage>> messagesByTab,
    required String activeTabId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      'tabs': tabs.map((tab) => tab.toJson()).toList(growable: false),
      'messagesByTab': messagesByTab.map(
        (key, value) => MapEntry(
          key,
          _retainedMessages(
            value,
          ).map((message) => message.toJson()).toList(growable: false),
        ),
      ),
      'activeTabId': activeTabId,
    });
    await prefs.setString(_key(networkId), encoded);
  }

  String _key(String networkId) => 'androidircx.chat.$networkId';

  List<IrcMessage> _retainedMessages(List<IrcMessage> messages) {
    Iterable<IrcMessage> retained = _dedupeByMsgid(messages);
    final retainAfter = retainMessagesAfter;
    if (retainAfter != null) {
      retained = retained.where(
        (message) => !message.timestamp.isBefore(retainAfter),
      );
    }

    final maxItems = maxMessagesPerTab < 0 ? 0 : maxMessagesPerTab;
    return retained
        .toList(growable: false)
        .takeLast(maxItems)
        .toList(growable: false);
  }

  List<IrcMessage> _dedupeByMsgid(List<IrcMessage> messages) {
    final seen = <String>{};
    final deduped = <IrcMessage>[];
    for (final message in messages) {
      final msgid = (message.tags['msgid'] ?? '').trim();
      if (msgid.isNotEmpty && !seen.add('${message.tabId}\x1f$msgid')) {
        continue;
      }
      deduped.add(message);
    }
    return deduped;
  }
}

extension on List<IrcMessage> {
  Iterable<IrcMessage> takeLast(int maxItems) {
    if (length <= maxItems) {
      return this;
    }

    return sublist(length - maxItems);
  }
}

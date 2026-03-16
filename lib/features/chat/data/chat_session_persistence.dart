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
  Future<ChatSessionSnapshot?> load(String networkId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(networkId));
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, Object?>;
    final tabs = ((decoded['tabs'] as List<dynamic>?) ?? const [])
        .map((item) => ChatTab.fromJson(item as Map<String, Object?>))
        .toList(growable: false);
    final messagesMap = <String, List<IrcMessage>>{};
    final rawMessages = (decoded['messagesByTab'] as Map<String, dynamic>?) ?? const {};
    for (final entry in rawMessages.entries) {
      messagesMap[entry.key] = (entry.value as List<dynamic>)
          .map((item) => IrcMessage.fromJson(item as Map<String, Object?>))
          .toList(growable: false);
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
          value
              .takeLast(200)
              .map((message) => message.toJson())
              .toList(growable: false),
        ),
      ),
      'activeTabId': activeTabId,
    });
    await prefs.setString(_key(networkId), encoded);
  }

  String _key(String networkId) => 'androidircx.chat.$networkId';
}

extension on List<IrcMessage> {
  Iterable<IrcMessage> takeLast(int maxItems) {
    if (length <= maxItems) {
      return this;
    }

    return sublist(length - maxItems);
  }
}

enum IrcMessageKind { chat, system, raw }

class IrcMessage {
  const IrcMessage({
    required this.id,
    required this.tabId,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.tags = const <String, String?>{},
    this.isPlayback = false,
    this.isOwn = false,
    this.kind = IrcMessageKind.chat,
  });

  final String id;
  final String tabId;
  final String sender;
  final String content;
  final DateTime timestamp;
  final Map<String, String?> tags;
  final bool isPlayback;
  final bool isOwn;
  final IrcMessageKind kind;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'tabId': tabId,
      'sender': sender,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'tags': tags,
      'isPlayback': isPlayback,
      'isOwn': isOwn,
      'kind': kind.name,
    };
  }

  factory IrcMessage.fromJson(Map<String, Object?> json) {
    return IrcMessage(
      id: json['id']! as String,
      tabId: json['tabId']! as String,
      sender: json['sender']! as String,
      content: json['content']! as String,
      timestamp: DateTime.parse(json['timestamp']! as String),
      tags: Map<String, String?>.from((json['tags'] as Map?) ?? const <String, String?>{}),
      isPlayback: (json['isPlayback'] as bool?) ?? false,
      isOwn: (json['isOwn'] as bool?) ?? false,
      kind: IrcMessageKind.values.byName(
        (json['kind'] as String?) ?? IrcMessageKind.chat.name,
      ),
    );
  }
}

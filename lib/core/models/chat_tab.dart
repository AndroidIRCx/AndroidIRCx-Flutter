enum ChatTabType { server, channel, query, notice, dcc }

class ChatTab {
  const ChatTab({
    required this.id,
    required this.name,
    required this.type,
    required this.networkId,
    this.hasActivity = false,
    this.unreadCount = 0,
    this.isEncrypted = false,
  });

  final String id;
  final String name;
  final ChatTabType type;
  final String networkId;
  final bool hasActivity;
  final int unreadCount;
  final bool isEncrypted;

  ChatTab copyWith({
    String? id,
    String? name,
    ChatTabType? type,
    String? networkId,
    bool? hasActivity,
    int? unreadCount,
    bool? isEncrypted,
  }) {
    return ChatTab(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      networkId: networkId ?? this.networkId,
      hasActivity: hasActivity ?? this.hasActivity,
      unreadCount: unreadCount ?? this.unreadCount,
      isEncrypted: isEncrypted ?? this.isEncrypted,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'networkId': networkId,
      'hasActivity': hasActivity,
      'unreadCount': unreadCount,
      'isEncrypted': isEncrypted,
    };
  }

  factory ChatTab.fromJson(Map<String, Object?> json) {
    return ChatTab(
      id: json['id']! as String,
      name: json['name']! as String,
      type: ChatTabType.values.byName(json['type']! as String),
      networkId: json['networkId']! as String,
      hasActivity: (json['hasActivity'] as bool?) ?? false,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      isEncrypted: (json['isEncrypted'] as bool?) ?? false,
    );
  }
}

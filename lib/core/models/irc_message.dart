enum IrcMessageKind {
  chat,
  action,
  notice,
  system,
  raw,
  error,
  event,
  dcc,
  media,
}

enum IrcMessageAttachmentType {
  url,
  image,
  video,
  audio,
  file,
  media,
  dccChat,
  dccSend,
}

class IrcMessageAttachment {
  const IrcMessageAttachment({
    required this.type,
    required this.label,
    this.uri,
    this.mediaId,
    this.transferId,
    this.peerNick,
    this.fileName,
    this.size,
    this.direction,
    this.status,
  });

  final IrcMessageAttachmentType type;
  final String label;
  final String? uri;
  final String? mediaId;
  final String? transferId;
  final String? peerNick;
  final String? fileName;
  final int? size;
  final String? direction;
  final String? status;

  Map<String, Object?> toJson() {
    return {
      'type': type.name,
      'label': label,
      'uri': uri,
      'mediaId': mediaId,
      'transferId': transferId,
      'peerNick': peerNick,
      'fileName': fileName,
      'size': size,
      'direction': direction,
      'status': status,
    };
  }

  factory IrcMessageAttachment.fromJson(Map<String, Object?> json) {
    return IrcMessageAttachment(
      type: _enumByName(
        IrcMessageAttachmentType.values,
        json['type'],
        IrcMessageAttachmentType.url,
      ),
      label: (json['label'] as String?) ?? '',
      uri: json['uri'] as String?,
      mediaId: json['mediaId'] as String?,
      transferId: json['transferId'] as String?,
      peerNick: json['peerNick'] as String?,
      fileName: json['fileName'] as String?,
      size: json['size'] as int?,
      direction: json['direction'] as String?,
      status: json['status'] as String?,
    );
  }
}

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
    this.networkId,
    this.receivedTimestamp,
    this.rawFrame,
    this.attachments = const <IrcMessageAttachment>[],
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
  final String? networkId;
  final DateTime? receivedTimestamp;
  final String? rawFrame;
  final List<IrcMessageAttachment> attachments;

  IrcMessage copyWith({
    String? id,
    String? tabId,
    String? sender,
    String? content,
    DateTime? timestamp,
    Map<String, String?>? tags,
    bool? isPlayback,
    bool? isOwn,
    IrcMessageKind? kind,
    String? networkId,
    DateTime? receivedTimestamp,
    String? rawFrame,
    List<IrcMessageAttachment>? attachments,
  }) {
    return IrcMessage(
      id: id ?? this.id,
      tabId: tabId ?? this.tabId,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      tags: tags ?? this.tags,
      isPlayback: isPlayback ?? this.isPlayback,
      isOwn: isOwn ?? this.isOwn,
      kind: kind ?? this.kind,
      networkId: networkId ?? this.networkId,
      receivedTimestamp: receivedTimestamp ?? this.receivedTimestamp,
      rawFrame: rawFrame ?? this.rawFrame,
      attachments: attachments ?? this.attachments,
    );
  }

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
      'networkId': networkId,
      'receivedTimestamp': receivedTimestamp?.toIso8601String(),
      'rawFrame': rawFrame,
      'attachments': attachments
          .map((attachment) => attachment.toJson())
          .toList(growable: false),
    };
  }

  factory IrcMessage.fromJson(Map<String, Object?> json) {
    final timestamp = DateTime.parse(json['timestamp']! as String);
    return IrcMessage(
      id: json['id']! as String,
      tabId: json['tabId']! as String,
      sender: json['sender']! as String,
      content: json['content']! as String,
      timestamp: timestamp,
      tags: Map<String, String?>.from(
        (json['tags'] as Map?) ?? const <String, String?>{},
      ),
      isPlayback: (json['isPlayback'] as bool?) ?? false,
      isOwn: (json['isOwn'] as bool?) ?? false,
      kind: _enumByName(
        IrcMessageKind.values,
        json['kind'],
        IrcMessageKind.chat,
      ),
      networkId: json['networkId'] as String?,
      receivedTimestamp: json['receivedTimestamp'] == null
          ? timestamp
          : DateTime.tryParse(json['receivedTimestamp']! as String) ??
                timestamp,
      rawFrame: json['rawFrame'] as String?,
      attachments: ((json['attachments'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                IrcMessageAttachment.fromJson(Map<String, Object?>.from(item)),
          )
          .toList(growable: false),
    );
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw as String?;
  if (name == null) {
    return fallback;
  }

  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}

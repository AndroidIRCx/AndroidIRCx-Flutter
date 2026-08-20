enum DccSessionType { chat, send, unknown }

enum DccSessionStatus { pending, offering, connecting, connected, closed, failed }

class DccSession {
  const DccSession({
    required this.id,
    required this.tabId,
    required this.peerNick,
    required this.type,
    required this.status,
    required this.direction,
    this.filename,
    this.host,
    this.port,
    this.size,
    this.token,
    this.filePath,
    this.bytesTransferred = 0,
    this.resumeOffset = 0,
    this.isReverse = false,
    this.error,
  });

  final String id;
  final String tabId;
  final String peerNick;
  final DccSessionType type;
  final DccSessionStatus status;
  final String direction;
  final String? filename;
  final String? host;
  final int? port;
  final int? size;
  final String? token;
  final String? filePath;
  final int bytesTransferred;
  final int resumeOffset;
  final bool isReverse;
  final String? error;

  DccSession copyWith({
    String? id,
    String? tabId,
    String? peerNick,
    DccSessionType? type,
    DccSessionStatus? status,
    String? direction,
    String? filename,
    String? host,
    int? port,
    int? size,
    String? token,
    String? filePath,
    int? bytesTransferred,
    int? resumeOffset,
    bool? isReverse,
    String? error,
  }) {
    return DccSession(
      id: id ?? this.id,
      tabId: tabId ?? this.tabId,
      peerNick: peerNick ?? this.peerNick,
      type: type ?? this.type,
      status: status ?? this.status,
      direction: direction ?? this.direction,
      filename: filename ?? this.filename,
      host: host ?? this.host,
      port: port ?? this.port,
      size: size ?? this.size,
      token: token ?? this.token,
      filePath: filePath ?? this.filePath,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      resumeOffset: resumeOffset ?? this.resumeOffset,
      isReverse: isReverse ?? this.isReverse,
      error: error ?? this.error,
    );
  }
}

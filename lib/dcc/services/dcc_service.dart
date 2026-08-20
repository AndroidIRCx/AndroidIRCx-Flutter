import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:androidircx/core/models/dcc_session.dart';

import 'dcc_file_store.dart';
import 'dcc_socket_backend.dart';

typedef DccMessageEvent = ({
  String tabId,
  String sender,
  String content,
  bool isOwn,
});

class DccService {
  DccService({DccSocketBackend? backend, String? downloadDirectoryPath})
    : _backend = backend ?? createDccSocketBackend(),
      _downloadDirectoryPath = _normalizeDownloadDirectory(
        downloadDirectoryPath,
      );

  final DccSocketBackend _backend;
  final Map<String, DccSession> _sessions = <String, DccSession>{};
  final Map<String, DccSocketConnection> _connections =
      <String, DccSocketConnection>{};
  final Map<String, DccSocketServer> _servers = <String, DccSocketServer>{};
  final Map<String, DccTempFile> _tempFiles = <String, DccTempFile>{};
  final Map<String, StreamSubscription<List<int>>> _subscriptions =
      <String, StreamSubscription<List<int>>>{};
  final StreamController<DccSession> _sessionController =
      StreamController<DccSession>.broadcast(sync: true);
  final StreamController<DccMessageEvent> _messageController =
      StreamController<DccMessageEvent>.broadcast(sync: true);

  Stream<DccSession> get sessions => _sessionController.stream;
  Stream<DccMessageEvent> get messages => _messageController.stream;
  DccSession? sessionForTab(String tabId) => _sessions[tabId];
  String? _downloadDirectoryPath;

  void updateDownloadDirectory(String? path) {
    _downloadDirectoryPath = _normalizeDownloadDirectory(path);
  }

  void _emitSession(DccSession session) {
    if (!_sessionController.isClosed) {
      _sessionController.add(session);
    }
  }

  void _emitMessage(DccMessageEvent event) {
    if (!_messageController.isClosed) {
      _messageController.add(event);
    }
  }

  void registerSession(DccSession session) {
    _sessions[session.tabId] = session;
    _emitSession(session);
  }

  Future<void> accept(DccSession session) async {
    switch (session.type) {
      case DccSessionType.chat:
        await _acceptChat(session);
      case DccSessionType.send:
        await _acceptSend(session);
      case DccSessionType.unknown:
        final failed = session.copyWith(
          status: DccSessionStatus.failed,
          error: 'Unsupported DCC offer.',
        );
        _sessions[session.tabId] = failed;
        _emitSession(failed);
    }
  }

  Future<void> acceptReverseSend({
    required DccSession session,
    required void Function(String ctcpOffer) onOfferReady,
  }) async {
    if (session.type != DccSessionType.send || !session.isReverse) {
      await accept(session);
      return;
    }

    final connecting = session.copyWith(status: DccSessionStatus.connecting);
    _sessions[session.tabId] = connecting;
    _emitSession(connecting);
    try {
      final server = await _backend.bindEphemeral();
      _servers[session.tabId] = server;
      final fileName = session.filename ?? 'dcc-download.bin';
      final offering = connecting.copyWith(
        status: DccSessionStatus.offering,
        host: server.address,
        port: server.port,
      );
      _sessions[session.tabId] = offering;
      _emitSession(offering);

      final ipValue = _ipToInt(server.address);
      final payloadHost = ipValue == null ? server.address : ipValue.toString();
      final size = session.size ?? 0;
      final token = (session.token ?? '').trim();
      final tokenSuffix = token.isEmpty ? '' : ' $token';
      onOfferReady(
        '\u0001DCC SEND "$fileName" $payloadHost ${server.port} $size$tokenSuffix\u0001',
      );

      unawaited(
        server.connections.first
            .then((connection) async {
              _connections[session.tabId] = connection;
              await _prepareIncomingSendTransfer(
                baseSession: offering,
                connection: connection,
                fileName: fileName,
              );
            })
            .catchError((Object error) {
              final failed = offering.copyWith(
                status: DccSessionStatus.failed,
                error: error.toString(),
              );
              _sessions[session.tabId] = failed;
              _emitSession(failed);
            }),
      );
    } catch (error) {
      await _deleteTempFile(session.tabId);
      final failed = connecting.copyWith(
        status: DccSessionStatus.failed,
        error: error.toString(),
      );
      _sessions[session.tabId] = failed;
      _emitSession(failed);
    }
  }

  Future<void> close(DccSession session) async {
    final activeSession = _sessions[session.tabId] ?? session;
    await _subscriptions.remove(session.tabId)?.cancel();
    await _connections.remove(session.tabId)?.close();
    await _servers.remove(session.tabId)?.close();
    if (activeSession.type == DccSessionType.send &&
        activeSession.direction == 'incoming' &&
        activeSession.status != DccSessionStatus.closed) {
      await _deleteTempFile(session.tabId);
    }
    final closed = activeSession.copyWith(status: DccSessionStatus.closed);
    _sessions[session.tabId] = closed;
    _emitSession(closed);
  }

  Future<bool> sendChatMessage({
    required DccSession session,
    required String sender,
    required String text,
  }) async {
    final connection = _connections[session.tabId];
    if (connection == null || session.status != DccSessionStatus.connected) {
      return false;
    }

    await connection.sendBytes(utf8.encode('$text\n'));
    _emitMessage((
      tabId: session.tabId,
      sender: sender,
      content: text,
      isOwn: true,
    ));
    return true;
  }

  Future<DccSession> startOutgoingChat({
    required String peerNick,
    required void Function(String ctcpOffer) onOfferReady,
    required String tabId,
  }) async {
    final server = await _backend.bindEphemeral();
    final session = DccSession(
      id: 'dcc-${DateTime.now().microsecondsSinceEpoch}',
      tabId: tabId,
      peerNick: peerNick,
      type: DccSessionType.chat,
      status: DccSessionStatus.offering,
      direction: 'outgoing',
      host: server.address,
      port: server.port,
    );
    _sessions[tabId] = session;
    _servers[tabId] = server;
    _emitSession(session);

    final ipValue = _ipToInt(server.address);
    final payloadHost = ipValue == null ? server.address : ipValue.toString();
    onOfferReady('\u0001DCC CHAT chat $payloadHost ${server.port}\u0001');

    unawaited(
      server.connections.first.then((connection) async {
        _connections[tabId] = connection;
        final connected = session.copyWith(status: DccSessionStatus.connected);
        _sessions[tabId] = connected;
        _emitSession(connected);
        _subscriptions[tabId] = connection.bytes.listen(
          (data) => _emitMessage((
            tabId: tabId,
            sender: peerNick,
            content: utf8.decode(data).trim(),
            isOwn: false,
          )),
          onDone: () {
            final closed = connected.copyWith(status: DccSessionStatus.closed);
            _sessions[tabId] = closed;
            _emitSession(closed);
          },
          onError: (Object error, StackTrace stackTrace) {
            final failed = connected.copyWith(
              status: DccSessionStatus.failed,
              error: error.toString(),
            );
            _sessions[tabId] = failed;
            _emitSession(failed);
          },
        );
      }),
    );

    return session;
  }

  Future<DccSession> startOutgoingSend({
    required String peerNick,
    required String filePath,
    required void Function(String ctcpOffer) onOfferReady,
    required String tabId,
  }) async {
    final sourceFile = await openDccSourceFile(filePath);
    final server = await _backend.bindEphemeral();
    final session = DccSession(
      id: 'dcc-${DateTime.now().microsecondsSinceEpoch}',
      tabId: tabId,
      peerNick: peerNick,
      type: DccSessionType.send,
      status: DccSessionStatus.offering,
      direction: 'outgoing',
      filename: sourceFile.fileName,
      host: server.address,
      port: server.port,
      size: sourceFile.size,
      filePath: sourceFile.path,
    );
    _sessions[tabId] = session;
    _servers[tabId] = server;
    _emitSession(session);

    final ipValue = _ipToInt(server.address);
    final payloadHost = ipValue == null ? server.address : ipValue.toString();
    onOfferReady(
      '\u0001DCC SEND "${sourceFile.fileName}" $payloadHost ${server.port} ${sourceFile.size}\u0001',
    );

    unawaited(
      server.connections.first.then((connection) async {
        _connections[tabId] = connection;
        final startedAt = DateTime.now();
        var latest = session.copyWith(
          status: DccSessionStatus.connected,
          transferStartedAt: startedAt,
          lastProgressAt: startedAt,
        );
        _sessions[tabId] = latest;
        _emitSession(latest);
        try {
          var transferred = 0;
          await for (final chunk in sourceFile.openRead()) {
            await connection.sendBytes(chunk);
            transferred += chunk.length;
            latest = _withTransferProgress(latest, transferred);
            _sessions[tabId] = latest;
            _emitSession(latest);
          }
          final completed = _withTransferProgress(
            latest,
            transferred,
            status: DccSessionStatus.closed,
          );
          _sessions[tabId] = completed;
          _emitSession(completed);
          await connection.close();
        } catch (error) {
          final failed = latest.copyWith(
            status: DccSessionStatus.failed,
            error: error.toString(),
          );
          _sessions[tabId] = failed;
          _emitSession(failed);
        }
      }),
    );

    return session;
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    for (final connection in _connections.values) {
      await connection.close();
    }
    for (final server in _servers.values) {
      await server.close();
    }
    for (final tabId in _tempFiles.keys.toList(growable: false)) {
      await _deleteTempFile(tabId);
    }
    await _sessionController.close();
    await _messageController.close();
  }

  Future<void> _acceptChat(DccSession session) async {
    final connecting = session.copyWith(status: DccSessionStatus.connecting);
    _sessions[session.tabId] = connecting;
    _emitSession(connecting);
    try {
      final connection = await _backend.connect(
        host: session.host ?? '',
        port: session.port ?? 0,
      );
      _connections[session.tabId] = connection;
      final connected = connecting.copyWith(status: DccSessionStatus.connected);
      _sessions[session.tabId] = connected;
      _emitSession(connected);
      _subscriptions[session.tabId] = connection.bytes.listen(
        (data) => _emitMessage((
          tabId: session.tabId,
          sender: session.peerNick,
          content: utf8.decode(data).trim(),
          isOwn: false,
        )),
        onDone: () {
          final closed = connected.copyWith(status: DccSessionStatus.closed);
          _sessions[session.tabId] = closed;
          _emitSession(closed);
        },
        onError: (Object error, StackTrace stackTrace) {
          final failed = connected.copyWith(
            status: DccSessionStatus.failed,
            error: error.toString(),
          );
          _sessions[session.tabId] = failed;
          _emitSession(failed);
        },
      );
    } catch (error) {
      final failed = connecting.copyWith(
        status: DccSessionStatus.failed,
        error: error.toString(),
      );
      _sessions[session.tabId] = failed;
      _emitSession(failed);
    }
  }

  Future<void> _acceptSend(DccSession session) async {
    final connecting = session.copyWith(status: DccSessionStatus.connecting);
    _sessions[session.tabId] = connecting;
    _emitSession(connecting);
    try {
      final connection = await _backend.connect(
        host: session.host ?? '',
        port: session.port ?? 0,
      );
      _connections[session.tabId] = connection;
      final fileName = session.filename ?? 'dcc-download.bin';
      await _prepareIncomingSendTransfer(
        baseSession: connecting,
        connection: connection,
        fileName: fileName,
      );
    } catch (error) {
      await _deleteTempFile(session.tabId);
      final failed = connecting.copyWith(
        status: DccSessionStatus.failed,
        error: error.toString(),
      );
      _sessions[session.tabId] = failed;
      _emitSession(failed);
    }
  }

  Future<DccSession> _prepareIncomingSendTransfer({
    required DccSession baseSession,
    required DccSocketConnection connection,
    required String fileName,
  }) async {
    final tempFile = await createDccTempFile(
      fileName,
      directoryPath: _downloadDirectoryPath,
    );
    _tempFiles[baseSession.tabId] = tempFile;
    final sink = tempFile.sink;
    final startedAt = DateTime.now();
    var latest = baseSession.copyWith(
      status: DccSessionStatus.connected,
      filePath: tempFile.path,
      transferStartedAt: startedAt,
      lastProgressAt: startedAt,
    );
    _sessions[baseSession.tabId] = latest;
    _emitSession(latest);
    var transferred = 0;
    _subscriptions[baseSession.tabId] = connection.bytes.listen(
      (data) async {
        sink.add(data);
        transferred += data.length;
        latest = _withTransferProgress(latest, transferred);
        _sessions[baseSession.tabId] = latest;
        _emitSession(latest);
        final ack = ByteData(4)..setUint32(0, transferred, Endian.big);
        await connection.sendBytes(ack.buffer.asUint8List());
      },
      onDone: () async {
        await sink.flush();
        await sink.close();
        final completed = _withTransferProgress(
          latest,
          transferred,
          status: DccSessionStatus.closed,
        );
        _tempFiles.remove(baseSession.tabId);
        _sessions[baseSession.tabId] = completed;
        _emitSession(completed);
      },
      onError: (Object error, StackTrace stackTrace) async {
        await _deleteTempFile(baseSession.tabId);
        final failed = latest.copyWith(
          status: DccSessionStatus.failed,
          error: error.toString(),
          bytesTransferred: transferred,
        );
        _sessions[baseSession.tabId] = failed;
        _emitSession(failed);
      },
    );
    return latest;
  }

  DccSession _withTransferProgress(
    DccSession session,
    int bytesTransferred, {
    DccSessionStatus? status,
  }) {
    final now = DateTime.now();
    final startedAt = session.transferStartedAt ?? now;
    final elapsedMicros = now.difference(startedAt).inMicroseconds;
    final elapsed = elapsedMicros <= 0 ? 1 : elapsedMicros;
    final bytesPerSecond = bytesTransferred <= 0
        ? session.bytesPerSecond
        : bytesTransferred * Duration.microsecondsPerSecond / elapsed;
    Duration? estimatedRemaining = session.estimatedRemaining;
    final totalBytes = session.size;
    if (status == DccSessionStatus.closed) {
      estimatedRemaining = Duration.zero;
    } else if (totalBytes != null &&
        totalBytes > 0 &&
        bytesPerSecond != null &&
        bytesPerSecond > 0) {
      final remainingBytes = totalBytes - bytesTransferred;
      estimatedRemaining = remainingBytes <= 0
          ? Duration.zero
          : Duration(
              microseconds:
                  (remainingBytes *
                          Duration.microsecondsPerSecond /
                          bytesPerSecond)
                      .round(),
            );
    }

    return session.copyWith(
      status: status,
      bytesTransferred: bytesTransferred,
      transferStartedAt: startedAt,
      lastProgressAt: now,
      bytesPerSecond: bytesPerSecond,
      estimatedRemaining: estimatedRemaining,
    );
  }

  int? _ipToInt(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList(growable: false);
    if (parts.length != 4 || parts.any((part) => part == null)) {
      return null;
    }

    return ((parts[0]! << 24) >>> 0) +
        (parts[1]! << 16) +
        (parts[2]! << 8) +
        parts[3]!;
  }

  Future<void> _deleteTempFile(String tabId) async {
    final tempFile = _tempFiles.remove(tabId);
    if (tempFile == null) {
      return;
    }
    try {
      await tempFile.sink.flush();
    } catch (_) {
      // Best-effort cleanup only. The transfer state already reports failure or close.
    }
    try {
      await tempFile.sink.close();
    } catch (_) {
      // Best-effort cleanup only. The transfer state already reports failure or close.
    }
    try {
      await tempFile.delete();
    } catch (_) {
      // Best-effort cleanup only. The transfer state already reports failure or close.
    }
  }

  static String? _normalizeDownloadDirectory(String? path) {
    final normalized = path?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

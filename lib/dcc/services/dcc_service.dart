import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:androidircx/core/models/dcc_session.dart';

import 'dcc_file_store.dart';
import 'dcc_socket_backend.dart';

typedef DccMessageEvent = ({String tabId, String sender, String content, bool isOwn});

class DccService {
  DccService({
    DccSocketBackend? backend,
  }) : _backend = backend ?? createDccSocketBackend();

  final DccSocketBackend _backend;
  final Map<String, DccSession> _sessions = <String, DccSession>{};
  final Map<String, DccSocketConnection> _connections = <String, DccSocketConnection>{};
  final Map<String, DccSocketServer> _servers = <String, DccSocketServer>{};
  final Map<String, StreamSubscription<List<int>>> _subscriptions =
      <String, StreamSubscription<List<int>>>{};
  final StreamController<DccSession> _sessionController =
      StreamController<DccSession>.broadcast(sync: true);
  final StreamController<DccMessageEvent> _messageController =
      StreamController<DccMessageEvent>.broadcast(sync: true);

  Stream<DccSession> get sessions => _sessionController.stream;
  Stream<DccMessageEvent> get messages => _messageController.stream;
  DccSession? sessionForTab(String tabId) => _sessions[tabId];

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

  Future<void> close(DccSession session) async {
    await _subscriptions.remove(session.tabId)?.cancel();
    await _connections.remove(session.tabId)?.close();
    await _servers.remove(session.tabId)?.close();
    final closed = session.copyWith(status: DccSessionStatus.closed);
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
        final connected = session.copyWith(status: DccSessionStatus.connected);
        _sessions[tabId] = connected;
        _emitSession(connected);
        try {
          final payload = await sourceFile.readAllBytes();
          await connection.sendBytes(payload);
          final completed = connected.copyWith(
            status: DccSessionStatus.closed,
            bytesTransferred: payload.length,
          );
          _sessions[tabId] = completed;
          _emitSession(completed);
          await connection.close();
        } catch (error) {
          final failed = connected.copyWith(
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
    DccFileSink? sink;
    try {
      final connection = await _backend.connect(
        host: session.host ?? '',
        port: session.port ?? 0,
      );
      _connections[session.tabId] = connection;
      final fileName = session.filename ?? 'dcc-download.bin';
      final tempFile = await createDccTempFile(fileName);
      sink = tempFile.sink;
      final connected = connecting.copyWith(
        status: DccSessionStatus.connected,
        filePath: tempFile.path,
      );
      _sessions[session.tabId] = connected;
      _emitSession(connected);
      var transferred = 0;
      _subscriptions[session.tabId] = connection.bytes.listen(
        (data) async {
          sink!.add(data);
          transferred += data.length;
          final updated = connected.copyWith(bytesTransferred: transferred);
          _sessions[session.tabId] = updated;
          _emitSession(updated);
          final ack = ByteData(4)..setUint32(0, transferred, Endian.big);
          await connection.sendBytes(ack.buffer.asUint8List());
        },
        onDone: () async {
          await sink?.flush();
          await sink?.close();
          final completed = connected.copyWith(
            status: DccSessionStatus.closed,
            bytesTransferred: transferred,
          );
          _sessions[session.tabId] = completed;
          _emitSession(completed);
        },
        onError: (Object error, StackTrace stackTrace) async {
          await sink?.close();
          final failed = connected.copyWith(
            status: DccSessionStatus.failed,
            error: error.toString(),
            bytesTransferred: transferred,
          );
          _sessions[session.tabId] = failed;
          _emitSession(failed);
        },
      );
    } catch (error) {
      await sink?.close();
      final failed = connecting.copyWith(
        status: DccSessionStatus.failed,
        error: error.toString(),
      );
      _sessions[session.tabId] = failed;
      _emitSession(failed);
    }
  }

  int? _ipToInt(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList(growable: false);
    if (parts.length != 4 || parts.any((part) => part == null)) {
      return null;
    }

    return ((parts[0]! << 24) >>> 0) + (parts[1]! << 16) + (parts[2]! << 8) + parts[3]!;
  }
}

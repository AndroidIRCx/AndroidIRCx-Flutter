import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:androidircx/core/models/dcc_session.dart';
import 'package:androidircx/dcc/services/dcc_service.dart';
import 'package:androidircx/dcc/services/dcc_socket_backend.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDccConnection implements DccSocketConnection {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sentPackets = <List<int>>[];
  var closeCount = 0;

  @override
  Stream<List<int>> get bytes => _controller.stream;

  void emit(List<int> data) {
    _controller.add(Uint8List.fromList(data));
  }

  void emitError(Object error) {
    _controller.addError(error);
  }

  Future<void> finish() => _controller.close();

  @override
  Future<void> close() async {
    closeCount += 1;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    sentPackets.add(Uint8List.fromList(data));
  }
}

class _FakeDccServer implements DccSocketServer {
  _FakeDccServer(this.address, this.port);

  final StreamController<DccSocketConnection> _controller =
      StreamController<DccSocketConnection>.broadcast();

  @override
  final String address;

  @override
  final int port;

  @override
  Stream<DccSocketConnection> get connections => _controller.stream;

  void accept(DccSocketConnection connection) {
    _controller.add(connection);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

class _FakeDccBackend implements DccSocketBackend {
  _FakeDccBackend({required this.incomingConnection});

  final DccSocketConnection incomingConnection;
  _FakeDccServer? server;

  @override
  Future<DccSocketServer> bindEphemeral() async {
    final next = _FakeDccServer('127.0.0.1', 5001);
    server = next;
    return next;
  }

  @override
  Future<DccSocketConnection> connect({
    required String host,
    required int port,
  }) async {
    return incomingConnection;
  }
}

void main() {
  test('outgoing DCC SEND streams large files and reports progress', () async {
    final connection = _FakeDccConnection();
    final backend = _FakeDccBackend(incomingConnection: connection);
    final service = DccService(backend: backend);
    final file = File.fromUri(
      Directory.systemTemp.uri.resolve('androidircx-dcc-large-test.bin'),
    );
    final payload = Uint8List.fromList(
      List<int>.generate(200000, (index) => index % 251),
    );
    await file.writeAsBytes(payload);
    final closed = service.sessions.firstWhere(
      (session) => session.status == DccSessionStatus.closed,
    );

    await service.startOutgoingSend(
      peerNick: 'alice',
      filePath: file.path,
      tabId: 'dcc::dbase::send',
      onOfferReady: (_) {},
    );
    backend.server!.accept(connection);

    final completed = await closed.timeout(const Duration(seconds: 3));
    final sentBytes = connection.sentPackets.fold<int>(
      0,
      (total, packet) => total + packet.length,
    );

    expect(connection.sentPackets.length, greaterThan(1));
    expect(sentBytes, payload.length);
    expect(completed.bytesTransferred, payload.length);

    await service.dispose();
    await file.delete();
  });

  test('incoming DCC SEND deletes partial temp file when cancelled', () async {
    final connection = _FakeDccConnection();
    final backend = _FakeDccBackend(incomingConnection: connection);
    final service = DccService(backend: backend);
    final session = DccSession(
      id: 'incoming-send-1',
      tabId: 'dcc::dbase::incoming',
      peerNick: 'alice',
      type: DccSessionType.send,
      status: DccSessionStatus.pending,
      direction: 'incoming',
      filename: 'incoming-cancel.bin',
      host: '127.0.0.1',
      port: 5001,
      size: 100,
    );
    final connected = service.sessions.firstWhere(
      (event) => event.status == DccSessionStatus.connected,
    );

    unawaited(service.accept(session));
    final active = await connected.timeout(const Duration(seconds: 3));
    final path = active.filePath!;
    connection.emit([1, 2, 3, 4]);
    await Future<void>.delayed(Duration.zero);

    expect(await File(path).exists(), isTrue);

    await service.close(active);

    expect(await File(path).exists(), isFalse);
    await service.dispose();
  });

  test('incoming DCC SEND deletes temp file on socket failure', () async {
    final connection = _FakeDccConnection();
    final backend = _FakeDccBackend(incomingConnection: connection);
    final service = DccService(backend: backend);
    final session = DccSession(
      id: 'incoming-send-2',
      tabId: 'dcc::dbase::incoming-fail',
      peerNick: 'alice',
      type: DccSessionType.send,
      status: DccSessionStatus.pending,
      direction: 'incoming',
      filename: 'incoming-fail.bin',
      host: '127.0.0.1',
      port: 5001,
      size: 100,
    );
    final connected = service.sessions.firstWhere(
      (event) => event.status == DccSessionStatus.connected,
    );
    final failed = service.sessions.firstWhere(
      (event) => event.status == DccSessionStatus.failed,
    );

    unawaited(service.accept(session));
    final active = await connected.timeout(const Duration(seconds: 3));
    final path = active.filePath!;
    connection.emit([1, 2, 3, 4]);
    await Future<void>.delayed(Duration.zero);
    connection.emitError(StateError('network failed'));

    await failed.timeout(const Duration(seconds: 3));

    expect(await File(path).exists(), isFalse);
    await service.dispose();
  });
}

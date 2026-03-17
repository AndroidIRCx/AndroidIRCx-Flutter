import 'dart:async';
import 'dart:io';

import 'dcc_socket_backend.dart';

class _IoDccSocketConnection implements DccSocketConnection {
  _IoDccSocketConnection(this._socket);

  final Socket _socket;

  @override
  Stream<List<int>> get bytes => _socket;

  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    _socket.add(data);
    await _socket.flush();
  }
}

class _IoDccSocketServer implements DccSocketServer {
  _IoDccSocketServer(this._server);

  final ServerSocket _server;

  @override
  String get address => _server.address.address;

  @override
  Stream<DccSocketConnection> get connections =>
      _server.map((socket) => _IoDccSocketConnection(socket));

  @override
  int get port => _server.port;

  @override
  Future<void> close() async {
    await _server.close();
  }
}

class _IoDccSocketBackend implements DccSocketBackend {
  @override
  Future<DccSocketServer> bindEphemeral() async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    return _IoDccSocketServer(server);
  }

  @override
  Future<DccSocketConnection> connect({
    required String host,
    required int port,
  }) async {
    final socket = await Socket.connect(host, port);
    return _IoDccSocketConnection(socket);
  }
}

DccSocketBackend createPlatformDccSocketBackend() => _IoDccSocketBackend();

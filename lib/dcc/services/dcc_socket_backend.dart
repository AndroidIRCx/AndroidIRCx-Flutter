import 'dcc_socket_backend_stub.dart'
    if (dart.library.io) 'dcc_socket_backend_io.dart';

abstract class DccSocketConnection {
  Stream<List<int>> get bytes;

  Future<void> sendBytes(List<int> data);

  Future<void> close();
}

abstract class DccSocketServer {
  Stream<DccSocketConnection> get connections;

  int get port;

  String get address;

  Future<void> close();
}

abstract class DccSocketBackend {
  Future<DccSocketConnection> connect({
    required String host,
    required int port,
  });

  Future<DccSocketServer> bindEphemeral();
}

DccSocketBackend createDccSocketBackend() => createPlatformDccSocketBackend();

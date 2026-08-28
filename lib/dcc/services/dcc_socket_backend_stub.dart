import 'dcc_socket_backend.dart';

class _UnsupportedDccSocketBackend implements DccSocketBackend {
  @override
  Future<DccSocketServer> bindEphemeral() {
    throw UnsupportedError('DCC sockets are only supported on IO platforms.');
  }

  @override
  Future<DccSocketConnection> connect({
    required String host,
    required int port,
  }) {
    throw UnsupportedError('DCC sockets are only supported on IO platforms.');
  }
}

DccSocketBackend createPlatformDccSocketBackend() =>
    _UnsupportedDccSocketBackend();

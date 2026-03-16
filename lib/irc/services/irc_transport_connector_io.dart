import 'dart:convert';
import 'dart:io';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/services/irc_transport.dart';

Future<IrcTransport> connectDefaultTransport(NetworkConfig network) {
  return SocketIrcTransport.connect(network);
}

class SocketIrcTransport implements IrcTransport {
  SocketIrcTransport._(this._socket)
      : lines = _socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((line) => line.isNotEmpty)
            .asBroadcastStream();

  final Socket _socket;

  @override
  final Stream<String> lines;

  static Future<SocketIrcTransport> connect(NetworkConfig network) async {
    final socket = network.useTls
        ? await SecureSocket.connect(network.host, network.port)
        : await Socket.connect(network.host, network.port);
    return SocketIrcTransport._(socket);
  }

  @override
  Future<void> close() async {
    _socket.destroy();
  }

  @override
  Future<void> sendLine(String line) async {
    _socket.write('$line\r\n');
    await _socket.flush();
  }
}

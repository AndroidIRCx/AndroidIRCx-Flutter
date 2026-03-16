import 'dart:async';
import 'dart:convert';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<IrcTransport> connectDefaultTransport(NetworkConfig network) {
  return WebIrcTransport.connect(network);
}

class WebIrcTransport implements IrcTransport {
  WebIrcTransport._(this._socket)
      : _lineController = StreamController<String>.broadcast() {
    _messageSubscription = _socket.stream.listen((data) {
      if (data is String) {
        _buffer += data;
        _drainBuffer();
      }
    }, onDone: () {
      _lineController.close();
    });
  }

  final WebSocketChannel _socket;
  final StreamController<String> _lineController;
  String _buffer = '';
  late final StreamSubscription<dynamic> _messageSubscription;

  @override
  Stream<String> get lines => _lineController.stream;

  static Future<WebIrcTransport> connect(NetworkConfig network) async {
    final url = buildWebSocketUri(network).toString();
    try {
      final socket = WebSocketChannel.connect(Uri.parse(url));
      await socket.ready;
      return WebIrcTransport._(socket);
    } catch (error) {
      throw UnsupportedError('Web IRC requires a working WebSocket endpoint at $url: $error');
    }
  }

  @override
  Future<void> close() async {
    await _messageSubscription.cancel();
    await _socket.sink.close();
    if (!_lineController.isClosed) {
      await _lineController.close();
    }
  }

  @override
  Future<void> sendLine(String line) async {
    _socket.sink.add('$line\r\n');
  }

  void _drainBuffer() {
    final content = _buffer;
    final lines = const LineSplitter().convert(content);
    final endsWithNewline = content.endsWith('\n') || content.endsWith('\r');

    _buffer = '';
    final trailing = endsWithNewline ? '' : (lines.isEmpty ? content : lines.removeLast());
    for (final line in lines.where((line) => line.isNotEmpty)) {
      _lineController.add(line);
    }
    if (trailing.isNotEmpty) {
      _buffer = trailing;
    }
  }
}

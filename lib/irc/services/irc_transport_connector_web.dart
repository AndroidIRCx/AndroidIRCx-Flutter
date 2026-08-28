import 'dart:async';
import 'dart:convert';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/security/certificate_store.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<IrcTransport> connectDefaultTransport(
  NetworkConfig network, {
  ClientCertificate? clientCertificate,
}) {
  return WebIrcTransport.connect(network);
}

class WebIrcTransport implements IrcTransport {
  WebIrcTransport._(this._incoming, this._send, this._onClose)
    : _lineController = StreamController<String>.broadcast() {
    _messageSubscription = _incoming.listen(
      (data) {
        for (final line in framesFromMessage(data)) {
          _lineController.add(line);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_lineController.isClosed) {
          _lineController.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!_lineController.isClosed) {
          _lineController.close();
        }
      },
    );
  }

  final Stream<dynamic> _incoming;
  final void Function(String data) _send;
  final Future<void> Function() _onClose;
  final StreamController<String> _lineController;
  late final StreamSubscription<dynamic> _messageSubscription;

  @override
  Stream<String> get lines => _lineController.stream;

  static Future<WebIrcTransport> connect(NetworkConfig network) async {
    final url = buildWebSocketUri(network).toString();
    try {
      final socket = WebSocketChannel.connect(
        Uri.parse(url),
        protocols: const ['text.ircv3.net', 'binary.ircv3.net'],
      );
      await socket.ready;
      return WebIrcTransport._(
        socket.stream,
        (data) => socket.sink.add(data),
        () => socket.sink.close(),
      );
    } catch (error) {
      throw UnsupportedError(
        'Web IRC requires a working WebSocket endpoint at $url: $error',
      );
    }
  }

  /// Test seam that drives the transport from an in-memory frame stream so
  /// framing behavior can be verified without a live WebSocket endpoint.
  factory WebIrcTransport.forTesting({
    required Stream<dynamic> incoming,
    void Function(String data)? onSend,
    Future<void> Function()? onClose,
  }) {
    return WebIrcTransport._(
      incoming,
      onSend ?? (_) {},
      onClose ?? () async {},
    );
  }

  @override
  Future<void> close() async {
    await _messageSubscription.cancel();
    await _onClose();
    if (!_lineController.isClosed) {
      await _lineController.close();
    }
  }

  @override
  Future<void> sendLine(String line) async {
    _send('$line\r\n');
  }

  /// Decodes a single incoming WebSocket message into zero or more IRC lines.
  ///
  /// Per the IRCv3 WebSocket sub-protocol a WebSocket message carries exactly
  /// one IRC message and the trailing CRLF is optional, so framing must not be
  /// buffered across frames: a frame boundary is a message boundary. Both the
  /// `text.ircv3.net` (String) and `binary.ircv3.net` (byte) sub-protocols are
  /// accepted, and a non-compliant server that packs several CRLF-separated
  /// lines into one frame is still split correctly. Empty/blank frames yield no
  /// lines.
  static List<String> framesFromMessage(Object? data) {
    final String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      text = utf8.decode(data, allowMalformed: true);
    } else {
      return const <String>[];
    }
    return const LineSplitter()
        .convert(text)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }
}

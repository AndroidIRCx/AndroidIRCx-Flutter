import 'dart:io';
import 'dart:typed_data';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/services/irc_transport_connector_io.dart';
import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Socket IRC transport SOCKS5 connector', () {
    test('uses SOCKS5 remote DNS and authenticated proxy handshake', () async {
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final handled = _handleSocks5Client(proxy);

      final transport = await SocketIrcTransport.connect(
        NetworkConfig(
          id: 'proxied',
          name: 'Proxied',
          host: 'irc.target.test',
          port: 6667,
          nickname: 'tester',
          useTls: false,
          proxyType: IrcProxyType.socks5,
          proxyHost: InternetAddress.loopbackIPv4.address,
          proxyPort: proxy.port,
          proxyUsername: 'user',
          proxyPassword: 'pass',
        ),
      );

      expect(await transport.lines.first, ':server NOTICE * :proxied');
      await transport.sendLine('PING proxy');
      await handled;
      await transport.close();
      await proxy.close();
    });
  });
}

Future<void> _handleSocks5Client(ServerSocket proxy) async {
  final socket = await proxy.first;
  final queue = StreamQueue<Uint8List>(socket);
  final reader = _QueueByteReader(queue);

  final greeting = await reader.readExactly(4);
  expect(greeting, [0x05, 0x02, 0x00, 0x02]);
  socket.add([0x05, 0x02]);
  await socket.flush();

  final authHeader = await reader.readExactly(2);
  expect(authHeader, [0x01, 0x04]);
  expect(String.fromCharCodes(await reader.readExactly(4)), 'user');
  final passwordLength = (await reader.readExactly(1)).first;
  expect(passwordLength, 4);
  expect(
    String.fromCharCodes(await reader.readExactly(passwordLength)),
    'pass',
  );
  socket.add([0x01, 0x00]);
  await socket.flush();

  final requestHeader = await reader.readExactly(5);
  expect(requestHeader.sublist(0, 4), [0x05, 0x01, 0x00, 0x03]);
  final host = String.fromCharCodes(await reader.readExactly(requestHeader[4]));
  final portBytes = await reader.readExactly(2);
  final port = (portBytes[0] << 8) + portBytes[1];
  expect(host, 'irc.target.test');
  expect(port, 6667);
  socket.add([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0, 0]);
  socket.write(':server NOTICE * :proxied\r\n');
  await socket.flush();

  expect(
    String.fromCharCodes(await reader.readExactly('PING proxy\r\n'.length)),
    'PING proxy\r\n',
  );
  await queue.cancel();
  socket.destroy();
}

class _QueueByteReader {
  _QueueByteReader(this._queue);

  final StreamQueue<Uint8List> _queue;
  final List<int> _buffer = <int>[];

  Future<List<int>> readExactly(int count) async {
    while (_buffer.length < count) {
      _buffer.addAll(await _queue.next);
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:androidircx/irc/services/irc_transport_connector_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IRCv3 WebSocket framing', () {
    test(
      'decodes a single text frame without a trailing CRLF into one line',
      () {
        expect(WebIrcTransport.framesFromMessage('PING :abc'), ['PING :abc']);
      },
    );

    test('strips an optional trailing CRLF from a text frame', () {
      expect(WebIrcTransport.framesFromMessage('PING :abc\r\n'), ['PING :abc']);
    });

    test('decodes a binary (byte) frame as UTF-8', () {
      final bytes = Uint8List.fromList(
        utf8.encode(':nick!u@h PRIVMSG #c :héllo\r\n'),
      );
      expect(WebIrcTransport.framesFromMessage(bytes), [
        ':nick!u@h PRIVMSG #c :héllo',
      ]);
    });

    test('splits a non-compliant frame that packs multiple CRLF lines', () {
      expect(
        WebIrcTransport.framesFromMessage(
          'CAP * LS :multi-prefix\r\nPING :x\r\n',
        ),
        ['CAP * LS :multi-prefix', 'PING :x'],
      );
    });

    test('ignores empty frames and blank lines', () {
      expect(WebIrcTransport.framesFromMessage(''), isEmpty);
      expect(WebIrcTransport.framesFromMessage('\r\n'), isEmpty);
      expect(WebIrcTransport.framesFromMessage(42), isEmpty);
    });

    test('emits exactly one IRC line per compliant CRLF-less frame', () async {
      final incoming = StreamController<dynamic>();
      final transport = WebIrcTransport.forTesting(incoming: incoming.stream);
      final received = <String>[];
      final subscription = transport.lines.listen(received.add);

      incoming.add('PING :1');
      incoming.add('PING :2');
      incoming.add('PING :3\r\n');
      await Future<void>.delayed(Duration.zero);

      // Regression guard: the previous buffered splitter concatenated
      // CRLF-less frames and never emitted them.
      expect(received, ['PING :1', 'PING :2', 'PING :3']);

      await subscription.cancel();
      await transport.close();
      await incoming.close();
    });

    test(
      'sendLine terminates each outgoing message with a single CRLF',
      () async {
        final incoming = StreamController<dynamic>.broadcast();
        final sent = <String>[];
        final transport = WebIrcTransport.forTesting(
          incoming: incoming.stream,
          onSend: sent.add,
        );

        await transport.sendLine('NICK tester');
        await transport.sendLine('USER a 0 * :real');

        expect(sent, ['NICK tester\r\n', 'USER a 0 * :real\r\n']);

        await transport.close();
        await incoming.close();
      },
    );

    test('closes the line stream when the socket is done', () async {
      final incoming = StreamController<dynamic>();
      final transport = WebIrcTransport.forTesting(incoming: incoming.stream);
      final done = expectLater(transport.lines.toList(), completion(isEmpty));

      await incoming.close();
      await done;
    });
  });
}

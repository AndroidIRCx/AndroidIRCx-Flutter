import 'dart:convert';
import 'dart:io';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/encoding/irc_encoding.dart';
import 'package:androidircx/irc/services/irc_transport_connector_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeIrcEncoding', () {
    test('normalizes case and whitespace', () {
      expect(normalizeIrcEncoding(' Windows-1250 '), 'windows-1250');
      expect(normalizeIrcEncoding('UTF-8'), 'utf-8');
    });

    test('falls back to utf-8 for unknown or empty labels', () {
      expect(normalizeIrcEncoding('shift_jis'), 'utf-8');
      expect(normalizeIrcEncoding(''), 'utf-8');
      expect(normalizeIrcEncoding(null), 'utf-8');
    });

    test('display name resolves for supported labels', () {
      expect(ircEncodingDisplayName('windows-1251'), 'Cyrillic (Windows-1251)');
      expect(ircEncodingDisplayName('bogus'), 'UTF-8 (Unicode)');
    });
  });

  group('decodeIrcLine', () {
    test('decodes utf-8 by default and tolerates malformed bytes', () {
      expect(decodeIrcLine(utf8.encode('Žčć šđ')), 'Žčć šđ');
      // Lone 0xE8 is invalid UTF-8; must not throw.
      expect(decodeIrcLine(<int>[0x61, 0xE8, 0x62]), contains('a'));
    });

    test('decodes windows-1250 line bytes', () {
      // 'čađ' in windows-1250: č=0xE8 a=0x61 đ=0xF0
      final decoded = decodeIrcLine(<int>[
        0xE8,
        0x61,
        0xF0,
      ], encoding: 'windows-1250');
      expect(decoded, 'čađ');
    });

    test('decodes windows-1251 cyrillic line bytes', () {
      // 'Жао' in windows-1251: Ж=0xC6 а=0xE0 о=0xEE
      final decoded = decodeIrcLine(<int>[
        0xC6,
        0xE0,
        0xEE,
      ], encoding: 'windows-1251');
      expect(decoded, 'Жао');
    });

    test('utf8Fallback decodes valid UTF-8 as UTF-8', () {
      final utf8Bytes = utf8.encode('šđž');
      final decoded = decodeIrcLine(
        utf8Bytes,
        encoding: 'windows-1250',
        utf8Fallback: true,
      );
      expect(decoded, 'šđž');
    });

    test('utf8Fallback falls back to legacy for invalid UTF-8', () {
      final decoded = decodeIrcLine(
        <int>[0xE8, 0x61, 0xF0],
        encoding: 'windows-1250',
        utf8Fallback: true,
      );
      expect(decoded, 'čađ');
    });
  });

  group('encodeIrcLine', () {
    test('returns null for utf-8 (caller uses the string path)', () {
      expect(encodeIrcLine('PRIVMSG #a :hi'), isNull);
      expect(encodeIrcLine('PRIVMSG #a :hi', encoding: 'utf-8'), isNull);
    });

    test('returns null when utf8Fallback prefers sending UTF-8', () {
      expect(
        encodeIrcLine('hi', encoding: 'windows-1250', utf8Fallback: true),
        isNull,
      );
    });

    test('encodes legacy charsets to legacy bytes', () {
      expect(encodeIrcLine('čađ', encoding: 'windows-1250'), <int>[
        0xE8,
        0x61,
        0xF0,
      ]);
      expect(encodeIrcLine('Жао', encoding: 'windows-1251'), <int>[
        0xC6,
        0xE0,
        0xEE,
      ]);
    });

    test('round-trips a legacy encode/decode', () {
      const original = 'Šta ima, đače?';
      final bytes = encodeIrcLine(original, encoding: 'windows-1250')!;
      expect(decodeIrcLine(bytes, encoding: 'windows-1250'), original);
    });
  });

  group('IrcByteLineSplitter', () {
    test('splits CRLF and LF lines and strips the CR', () {
      final splitter = IrcByteLineSplitter();
      final lines = splitter.addChunk(utf8.encode('a\r\nb\nc'));
      expect(lines, [utf8.encode('a'), utf8.encode('b')]);
      expect(splitter.addChunk(utf8.encode('\r\n')), [utf8.encode('c')]);
    });

    test('keeps multi-byte characters intact across chunk boundaries', () {
      final splitter = IrcByteLineSplitter();
      final bytes = utf8.encode('PRIVMSG #x :šđž\r\n');
      // Feed one byte at a time so the UTF-8 sequences straddle chunks.
      final lines = <List<int>>[];
      for (final byte in bytes) {
        lines.addAll(splitter.addChunk(<int>[byte]));
      }
      expect(lines, hasLength(1));
      expect(utf8.decode(lines.single), 'PRIVMSG #x :šđž');
    });

    test('buffers partial lines until the newline arrives', () {
      final splitter = IrcByteLineSplitter();
      expect(splitter.addChunk(utf8.encode('PING :tok')), isEmpty);
      expect(splitter.addChunk(utf8.encode('en\r\nNOTICE')), [
        utf8.encode('PING :token'),
      ]);
    });
  });

  group('NetworkConfig encoding fields', () {
    test('defaults to utf-8 without fallback', () {
      const network = NetworkConfig(
        id: 'n1',
        name: 'Net',
        host: 'irc.example.org',
        port: 6697,
        nickname: 'nick',
      );
      expect(network.encoding, 'utf-8');
      expect(network.encodingUtf8Fallback, isFalse);
    });

    test('round-trips through JSON', () {
      const network = NetworkConfig(
        id: 'n1',
        name: 'Net',
        host: 'irc.example.org',
        port: 6697,
        nickname: 'nick',
        encoding: 'windows-1250',
        encodingUtf8Fallback: true,
      );
      final restored = NetworkConfig.fromJson(network.toJson());
      expect(restored.encoding, 'windows-1250');
      expect(restored.encodingUtf8Fallback, isTrue);
    });

    test('missing JSON fields keep utf-8 defaults', () {
      final restored = NetworkConfig.fromJson(<String, Object?>{
        'id': 'n1',
        'name': 'Net',
        'host': 'irc.example.org',
        'port': 6697,
        'nickname': 'nick',
      });
      expect(restored.encoding, 'utf-8');
      expect(restored.encodingUtf8Fallback, isFalse);
    });
  });

  group('SocketIrcTransport encoding', () {
    test('decodes incoming legacy bytes and encodes outgoing lines', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close());

      final serverReceived = <int>[];
      final serverDone = server.first.then((client) async {
        // 'čao\r\n' in windows-1250.
        client.add(<int>[0xE8, 0x61, 0x6F, 0x0D, 0x0A]);
        await client.flush();
        await for (final chunk in client) {
          serverReceived.addAll(chunk);
          if (serverReceived.contains(0x0A)) {
            break;
          }
        }
        client.destroy();
      });

      final network = NetworkConfig(
        id: 'n1',
        name: 'Net',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        nickname: 'nick',
        useTls: false,
        encoding: 'windows-1250',
      );

      final transport = await SocketIrcTransport.connect(network);
      addTearDown(() async => transport.close());

      final firstLine = transport.lines.first;
      await transport.sendLine('PRIVMSG #x :čao');
      expect(await firstLine, 'čao');

      await serverDone;
      // Outgoing 'č' must be one windows-1250 byte (0xE8), not UTF-8.
      expect(serverReceived, <int>[
        ...ascii.encode('PRIVMSG #x :'),
        0xE8,
        0x61,
        0x6F,
        0x0D,
        0x0A,
      ]);
    });
  });
}

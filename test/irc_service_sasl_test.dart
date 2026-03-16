import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller = StreamController<String>.broadcast();
  final List<String> sentLines = <String>[];

  @override
  Stream<String> get lines => _controller.stream;

  void emit(String line) {
    _controller.add(line);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> sendLine(String line) async {
    sentLines.add(line);
  }
}

void main() {
  test('starts CAP negotiation and SASL PLAIN when configured', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        saslAccount: 'alice',
        saslPassword: 'secret',
      ),
    );

    expect(transport.sentLines, containsAllInOrder(['CAP LS 302', 'NICK AndroidIRCX']));

    transport.emit(':server CAP * LS :multi-prefix sasl');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('CAP REQ :sasl'));

    transport.emit(':server CAP * ACK :sasl');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('AUTHENTICATE PLAIN'));

    transport.emit('AUTHENTICATE +');
    await Future<void>.delayed(Duration.zero);
    expect(
      transport.sentLines.any((line) => line.startsWith('AUTHENTICATE ') && line != 'AUTHENTICATE PLAIN'),
      isTrue,
    );

    transport.emit(':server 903 AndroidIRCX :SASL authentication successful');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('CAP END'));

    service.dispose();
  });

  test('retries with alt nick and numbered suffix when nick is in use', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
    );

    expect(transport.sentLines, contains('NICK AndroidIRCX'));

    transport.emit(':server 433 * AndroidIRCX :Nickname is already in use');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('NICK AndroidIRCX_'));

    transport.emit(':server 433 * AndroidIRCX_ :Nickname is already in use');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('NICK AndroidIRCX_1'));

    service.dispose();
  });
}

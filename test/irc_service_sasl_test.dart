import 'dart:async';
import 'dart:convert';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/sasl/scram_sha256_session.dart';
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
  test('buildWebSocketUri uses root slash when websocket path is empty', () {
    final uri = buildWebSocketUri(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.dbase.in.rs',
        port: 6697,
        nickname: 'AndroidIRCX',
        webSocketPort: 16697,
      ),
    );

    expect(uri.toString(), 'wss://irc.dbase.in.rs:16697/');
  });

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

    transport.emit(':server CAP * LS :multi-prefix sasl message-tags server-time echo-message');
    await Future<void>.delayed(Duration.zero);
    expect(
      transport.sentLines,
      contains('CAP REQ :sasl echo-message message-tags server-time'),
    );

    transport.emit(':server CAP * ACK :sasl echo-message message-tags server-time');
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

  test('starts SCRAM-SHA-256 authentication when configured', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
      scramNonceGenerator: () => 'fixedNonce',
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
        saslMechanism: SaslMechanism.scramSha256,
      ),
    );

    transport.emit(':server CAP * LS :multi-prefix sasl');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':server CAP * ACK :sasl');
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('AUTHENTICATE SCRAM-SHA-256'));

    transport.emit('AUTHENTICATE +');
    await Future<void>.delayed(Duration.zero);
    final clientFirstLine = transport.sentLines.last;
    expect(clientFirstLine, startsWith('AUTHENTICATE '));
    final clientFirst =
        utf8.decode(base64.decode(clientFirstLine.substring('AUTHENTICATE '.length)));
    expect(clientFirst, 'n,,n=alice,r=fixedNonce');

    final verifier = ScramSha256Session(
      username: 'alice',
      password: 'secret',
      nonceGenerator: () => 'fixedNonce',
    );
    verifier.createClientFirstMessage();
    verifier.createClientFinalMessage('r=fixedNonceServer,s=c2FsdHlTYWx0,i=4096');

    transport.emit(
      'AUTHENTICATE ${base64.encode(utf8.encode('r=fixedNonceServer,s=c2FsdHlTYWx0,i=4096'))}',
    );
    await Future<void>.delayed(Duration.zero);
    final clientFinalLine = transport.sentLines.last;
    final clientFinal =
        utf8.decode(base64.decode(clientFinalLine.substring('AUTHENTICATE '.length)));
    expect(clientFinal, startsWith('c=biws,r=fixedNonceServer,p='));

    transport.emit(
      'AUTHENTICATE ${base64.encode(utf8.encode('v=${verifier.expectedServerSignature}'))}',
    );
    await Future<void>.delayed(Duration.zero);

    transport.emit(':server 903 AndroidIRCX :SASL authentication successful');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('CAP END'));

    service.dispose();
  });

  test('starts EXTERNAL authentication when configured', () async {
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
        saslMechanism: SaslMechanism.external,
      ),
    );

    transport.emit(':server CAP * LS :multi-prefix sasl');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':server CAP * ACK :sasl');
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('AUTHENTICATE EXTERNAL'));

    transport.emit('AUTHENTICATE +');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('AUTHENTICATE +'));

    transport.emit(':server 903 AndroidIRCX :SASL authentication successful');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('CAP END'));

    service.dispose();
  });

  test('tracks CAP NEW and DEL updates after registration', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final rawEvents = <String>[];
    final subscription = service.rawEvents.listen(rawEvents.add);

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      ),
    );

    transport.emit(':server CAP * NEW :draft/labeled-response echo-message');
    await Future<void>.delayed(Duration.zero);
    expect(service.availableCapabilities, contains('draft/labeled-response'));
    expect(service.availableCapabilities, contains('echo-message'));

    transport.emit(':server CAP * DEL :echo-message');
    await Future<void>.delayed(Duration.zero);
    expect(service.availableCapabilities, isNot(contains('echo-message')));
    expect(
      rawEvents.any((event) => event.contains('CAP NEW')),
      isTrue,
    );
    expect(
      rawEvents.any((event) => event.contains('CAP DEL')),
      isTrue,
    );

    await subscription.cancel();
    service.dispose();
  });

  test('sendRawLabeled prefixes label when capability is enabled', () async {
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
      ),
    );

    transport.emit(':server CAP * ACK :labeled-response');
    await Future<void>.delayed(Duration.zero);
    final label = await service.sendRawLabeled('WHOIS alice alice');

    expect(label, isNotEmpty);
    expect(
      transport.sentLines.any((line) => line.startsWith('@label=$label WHOIS alice alice')),
      isTrue,
    );

    service.dispose();
  });

  test('resolves labeled response when matching label returns', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final matches = <({String label, String command, IrcMessageFrame frame})>[];
    final subscription = service.labeledResponses.listen(matches.add);

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      ),
    );

    transport.emit(':server CAP * ACK :labeled-response');
    await Future<void>.delayed(Duration.zero);
    final label = await service.sendRawLabeled('WHOIS alice alice');
    transport.emit('@label=$label :server 318 AndroidIRCX alice :End of /WHOIS list.');
    await Future<void>.delayed(Duration.zero);

    expect(matches, hasLength(1));
    expect(matches.single.label, label);
    expect(matches.single.command, 'WHOIS alice alice');
    expect(matches.single.frame.command, '318');

    await subscription.cancel();
    service.dispose();
  });

  test('sendChatHistory requires chathistory capability', () async {
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
      ),
    );

    expect(
      await service.sendChatHistory(target: '#room', limit: 25),
      isFalse,
    );

    transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);

    expect(
      await service.sendChatHistory(
        target: '#room',
        subcommand: 'BEFORE',
        reference: 'msgid-1',
        limit: 25,
      ),
      isTrue,
    );
    expect(
      transport.sentLines.any((line) => line.contains('CHATHISTORY BEFORE #room msgid-1 25')),
      isTrue,
    );

    service.dispose();
  });
}

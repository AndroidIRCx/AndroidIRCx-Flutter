import 'dart:async';
import 'dart:convert';

import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/sasl/scram_sha256_session.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final List<String> sentLines = <String>[];
  int closeCount = 0;

  @override
  Stream<String> get lines => _controller.stream;

  void emit(String line) {
    _controller.add(line);
  }

  void emitError(Object error) {
    _controller.addError(error);
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  @override
  Future<void> sendLine(String line) async {
    sentLines.add(line);
  }
}

void main() {
  test('connect while connecting does not open duplicate transport', () async {
    var connectorCalls = 0;
    final connectorGate = Completer<IrcTransport>();
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) {
        connectorCalls += 1;
        return connectorGate.future;
      },
    );
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.example.test',
      port: 6697,
      nickname: 'AndroidIRCX',
    );

    final firstConnect = service.connect(network);
    final secondConnect = service.connect(network);
    expect(connectorCalls, 1);

    connectorGate.complete(transport);
    await Future.wait(<Future<void>>[firstConnect, secondConnect]);
    expect(connectorCalls, 1);
    expect(
      transport.sentLines.where((line) => line == 'NICK AndroidIRCX'),
      hasLength(1),
    );

    service.dispose();
  });

  test(
    'disconnect while connecting ignores late transport connector',
    () async {
      final connectorGate = Completer<IrcTransport>();
      final transport = _FakeTransport();
      final service = IrcService(
        transportConnector: (_) => connectorGate.future,
      );
      final states = <ConnectionSnapshot>[];
      final subscription = service.stateStream.listen(states.add);
      const network = NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      );

      final connectFuture = service.connect(network);
      await Future<void>.delayed(Duration.zero);
      await service.disconnect();
      connectorGate.complete(transport);
      await connectFuture;
      await Future<void>.delayed(Duration.zero);

      expect(transport.closeCount, 1);
      expect(transport.sentLines, isEmpty);
      expect(service.state.phase, ConnectionPhase.disconnected);
      expect(
        states.map((snapshot) => snapshot.phase),
        containsAllInOrder(<ConnectionPhase>[
          ConnectionPhase.connecting,
          ConnectionPhase.disconnecting,
          ConnectionPhase.disconnected,
        ]),
      );

      await subscription.cancel();
      service.dispose();
    },
  );

  test('registering state is not connected until welcome numeric', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final states = <ConnectionSnapshot>[];
    final subscription = service.stateStream.listen(states.add);

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      ),
    );

    expect(service.state.phase, ConnectionPhase.registering);
    expect(
      states.map((snapshot) => snapshot.phase),
      containsAllInOrder(<ConnectionPhase>[
        ConnectionPhase.connecting,
        ConnectionPhase.registering,
      ]),
    );
    expect(
      states.map((snapshot) => snapshot.phase),
      isNot(contains(ConnectionPhase.connected)),
    );

    transport.emit(':server 001 AndroidIRCX :Welcome');
    await Future<void>.delayed(Duration.zero);

    expect(service.state.phase, ConnectionPhase.connected);

    await subscription.cancel();
    service.dispose();
  });

  test('SASL flow exposes authenticating then registering states', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final states = <ConnectionSnapshot>[];
    final subscription = service.stateStream.listen(states.add);

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
    transport.emit(':server CAP * LS :sasl');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':server CAP * ACK :sasl');
    await Future<void>.delayed(Duration.zero);

    expect(service.state.phase, ConnectionPhase.authenticating);

    transport.emit(':server 903 AndroidIRCX :SASL authentication successful');
    await Future<void>.delayed(Duration.zero);

    expect(service.state.phase, ConnectionPhase.registering);
    expect(
      states.map((snapshot) => snapshot.phase),
      containsAllInOrder(<ConnectionPhase>[
        ConnectionPhase.registering,
        ConnectionPhase.authenticating,
        ConnectionPhase.registering,
      ]),
    );

    await subscription.cancel();
    service.dispose();
  });

  test('IRC ERROR frame moves service into error state', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      ),
    );
    transport.emit(':server 001 AndroidIRCX :Welcome');
    await Future<void>.delayed(Duration.zero);

    transport.emit('ERROR :Closing Link: AndroidIRCX (Ping timeout)');
    await Future<void>.delayed(Duration.zero);

    expect(service.state.phase, ConnectionPhase.error);
    expect(service.state.message, contains('Ping timeout'));
    await Future<void>.delayed(Duration.zero);
    expect(transport.closeCount, 1);

    service.dispose();
  });

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

  test(
    'joinChannel sends keyed JOIN but redacts key from raw events',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
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
      await service.joinChannel('#secret', 'opensesame');
      await Future<void>.delayed(Duration.zero);

      expect(transport.sentLines, contains('JOIN #secret opensesame'));
      expect(rawEvents, contains('>> JOIN #secret [REDACTED]'));
      expect(rawEvents.join('\n'), isNot(contains('opensesame')));

      await subscription.cancel();
      service.dispose();
    },
  );

  test('starts CAP negotiation and SASL PLAIN when configured', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

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

    expect(
      transport.sentLines,
      containsAllInOrder(['CAP LS 302', 'NICK AndroidIRCX']),
    );

    transport.emit(
      ':server CAP * LS :multi-prefix sasl message-tags server-time echo-message',
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      transport.sentLines,
      contains(
        'CAP REQ :sasl echo-message message-tags multi-prefix server-time',
      ),
    );

    transport.emit(
      ':server CAP * ACK :sasl echo-message message-tags server-time',
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('AUTHENTICATE PLAIN'));

    transport.emit('AUTHENTICATE +');
    await Future<void>.delayed(Duration.zero);
    expect(
      transport.sentLines.any(
        (line) =>
            line.startsWith('AUTHENTICATE ') && line != 'AUTHENTICATE PLAIN',
      ),
      isTrue,
    );

    transport.emit(':server 903 AndroidIRCX :SASL authentication successful');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('CAP END'));

    service.dispose();
  });

  test(
    'without SASL config registers with NICK and USER without CAP LS',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);

      await service.connect(
        const NetworkConfig(
          id: 'plain',
          name: 'Plain',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          username: 'androidircx',
          realName: 'AndroidIRCX',
        ),
      );

      expect(transport.sentLines, isNot(contains('CAP LS 302')));
      expect(
        transport.sentLines,
        containsAllInOrder(<String>[
          'NICK AndroidIRCX',
          'USER androidircx 0 * :AndroidIRCX',
        ]),
      );

      service.dispose();
    },
  );

  test('accumulates multiline CAP LS before requesting capabilities', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

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

    transport.emit(':server CAP * LS * :sasl multi-prefix');
    await Future<void>.delayed(Duration.zero);
    expect(
      transport.sentLines.where((line) => line.startsWith('CAP REQ')),
      isEmpty,
    );

    transport.emit(':server CAP * LS :server-time echo-message');
    await Future<void>.delayed(Duration.zero);
    expect(
      service.availableCapabilities,
      containsAll(<String>[
        'sasl',
        'multi-prefix',
        'server-time',
        'echo-message',
      ]),
    );
    expect(
      transport.sentLines,
      contains('CAP REQ :sasl echo-message multi-prefix server-time'),
    );

    service.dispose();
  });

  test('does not start SASL from CAP ACK unless SASL was requested', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

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

    transport.emit(':server CAP * ACK :sasl');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, isNot(contains('AUTHENTICATE PLAIN')));

    service.dispose();
  });

  test('CAP NAK logs rejected capabilities and ends CAP', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final rawEvents = <String>[];
    final subscription = service.rawEvents.listen(rawEvents.add);

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
    transport.emit(':server CAP * LS :sasl server-time');
    await Future<void>.delayed(Duration.zero);

    transport.emit(':server CAP * NAK :sasl server-time');
    await Future<void>.delayed(Duration.zero);
    expect(rawEvents.any((event) => event.contains('CAP NAK')), isTrue);
    expect(rawEvents.any((event) => event.contains('sasl')), isTrue);
    expect(transport.sentLines, contains('CAP END'));

    await subscription.cancel();
    service.dispose();
  });

  test('SASL failure numerics are visible and safely end CAP', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final rawEvents = <String>[];
    final subscription = service.rawEvents.listen(rawEvents.add);

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
    transport.emit(':server CAP * LS :sasl');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':server CAP * ACK :sasl');
    await Future<void>.delayed(Duration.zero);

    for (final numeric in <String>['904', '905', '906', '907']) {
      transport.emit(':server $numeric AndroidIRCX :SASL failed safely');
      await Future<void>.delayed(Duration.zero);
      expect(
        rawEvents.any(
          (event) =>
              event.contains('SASL authentication failed ($numeric)') &&
              event.contains('SASL failed safely'),
        ),
        isTrue,
      );
    }
    expect(transport.sentLines, contains('CAP END'));

    await subscription.cancel();
    service.dispose();
  });

  test(
    'retries with alt nick and numbered suffix when nick is in use',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);

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
    },
  );

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
    final clientFirst = utf8.decode(
      base64.decode(clientFirstLine.substring('AUTHENTICATE '.length)),
    );
    expect(clientFirst, 'n,,n=alice,r=fixedNonce');

    final verifier = ScramSha256Session(
      username: 'alice',
      password: 'secret',
      nonceGenerator: () => 'fixedNonce',
    );
    verifier.createClientFirstMessage();
    verifier.createClientFinalMessage(
      'r=fixedNonceServer,s=c2FsdHlTYWx0,i=4096',
    );

    transport.emit(
      'AUTHENTICATE ${base64.encode(utf8.encode('r=fixedNonceServer,s=c2FsdHlTYWx0,i=4096'))}',
    );
    await Future<void>.delayed(Duration.zero);
    final clientFinalLine = transport.sentLines.last;
    final clientFinal = utf8.decode(
      base64.decode(clientFinalLine.substring('AUTHENTICATE '.length)),
    );
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

  test('invalid SCRAM server-final aborts SASL safely', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
      scramNonceGenerator: () => 'fixedNonce',
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
        saslAccount: 'alice',
        saslPassword: 'secret',
        saslMechanism: SaslMechanism.scramSha256,
      ),
    );

    transport.emit(':server CAP * LS :sasl');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':server CAP * ACK :sasl');
    await Future<void>.delayed(Duration.zero);
    transport.emit('AUTHENTICATE +');
    await Future<void>.delayed(Duration.zero);
    transport.emit(
      'AUTHENTICATE ${base64.encode(utf8.encode('r=fixedNonceServer,s=c2FsdHlTYWx0,i=4096'))}',
    );
    await Future<void>.delayed(Duration.zero);

    transport.emit(
      'AUTHENTICATE ${base64.encode(utf8.encode('e=server-error'))}',
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      rawEvents.any((event) => event.contains('SCRAM verification failed')),
      isTrue,
    );
    expect(transport.sentLines, contains('AUTHENTICATE *'));
    expect(transport.sentLines, contains('CAP END'));

    await subscription.cancel();
    service.dispose();
  });

  test('starts EXTERNAL authentication when configured', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

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
    final service = IrcService(transportConnector: (_) async => transport);
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
    expect(rawEvents.any((event) => event.contains('CAP NEW')), isTrue);
    expect(rawEvents.any((event) => event.contains('CAP DEL')), isTrue);

    await subscription.cancel();
    service.dispose();
  });

  test('sendRawLabeled prefixes label when capability is enabled', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

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
      transport.sentLines.any(
        (line) => line.startsWith('@label=$label WHOIS alice alice'),
      ),
      isTrue,
    );

    service.dispose();
  });

  test('resolves labeled response when matching label returns', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
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
    transport.emit(
      '@label=$label :server 318 AndroidIRCX alice :End of /WHOIS list.',
    );
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
    final service = IrcService(transportConnector: (_) async => transport);

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      ),
    );

    expect(await service.sendChatHistory(target: '#room', limit: 25), isFalse);

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
      transport.sentLines.any(
        (line) => line.contains('CHATHISTORY BEFORE #room msgid-1 25'),
      ),
      isTrue,
    );

    service.dispose();
  });

  test('sendPrivmsg uses draft multiline when capability is enabled', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      ),
    );

    transport.emit(':server CAP * ACK :draft/multiline');
    await Future<void>.delayed(Duration.zero);

    await service.sendPrivmsg(target: '#room', text: 'one\ntwo');

    expect(
      transport.sentLines
          .where((line) => line.contains('PRIVMSG #room :one'))
          .length,
      1,
    );
    expect(
      transport.sentLines
          .where((line) => line.contains('PRIVMSG #room :two'))
          .length,
      1,
    );
    expect(
      transport.sentLines.any(
        (line) => line.startsWith('@draft/multiline-concat='),
      ),
      isTrue,
    );

    service.dispose();
  });

  test('sendTyping and sendReaction use tagmsg commands', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      ),
    );

    transport.emit(':server CAP * ACK :typing draft/typing');
    await Future<void>.delayed(Duration.zero);

    expect(await service.sendTyping(target: '#room', status: 'active'), isTrue);
    await service.sendReaction(
      target: '#room',
      msgid: 'abc123',
      emoji: ':thumbsup:',
    );

    expect(
      transport.sentLines.any((line) => line == '@+typing=active TAGMSG #room'),
      isTrue,
    );
    expect(
      transport.sentLines.any(
        (line) => line == '@+draft/react=abc123\\::thumbsup: TAGMSG #room',
      ),
      isTrue,
    );

    service.dispose();
  });

  test('sendSetName requires setname capability', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);

    await service.connect(
      const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      ),
    );

    expect(await service.sendSetName('New Realname'), isFalse);

    transport.emit(':server CAP * ACK :setname');
    await Future<void>.delayed(Duration.zero);

    expect(await service.sendSetName('New Realname'), isTrue);
    expect(transport.sentLines, contains('SETNAME :New Realname'));

    service.dispose();
  });
}

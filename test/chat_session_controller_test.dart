import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('routes SASL/auth numerics into server messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
        saslAccount: 'alice',
        saslPassword: 'secret',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 900 AndroidIRCX alice!ident@example :You are now logged in as alice');
    transport.emit(':server 903 AndroidIRCX :SASL authentication successful');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('logged in as alice'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('SASL authentication successful'),
      ),
      isTrue,
    );

    controller.dispose();
  });
}

import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/data/user_list_entry.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final List<String> sentLines = <String>[];

  @override
  Stream<String> get lines => _controller.stream;

  void emit(String line) => _controller.add(line);

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  Future<void> sendLine(String line) async => sentLines.add(line);
}

Future<(ChatSessionController, _FakeTransport)> _connected() async {
  final transport = _FakeTransport();
  final service = IrcService(transportConnector: (_) async => transport);
  final controller = ChatSessionController(
    network: const NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.example.test',
      port: 6697,
      nickname: 'AndroidIRCX',
    ),
    ircService: service,
  );
  await controller.start();
  transport.emit(':server 001 AndroidIRCX :Welcome');
  await Future<void>.delayed(Duration.zero);
  return (controller, transport);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('auto-voices a matching user when we hold op', () async {
    final (controller, transport) = await _connected();
    // Join and become op via NAMES prefix.
    transport.emit(':AndroidIRCX!u@h JOIN #flutter');
    transport.emit(':server 353 AndroidIRCX = #flutter :@AndroidIRCX');
    transport.emit(':server 366 AndroidIRCX #flutter :End of NAMES');
    await Future<void>.delayed(Duration.zero);

    await controller.addAutoModeEntry(
      const UserListEntry(type: UserListType.autoVoice, mask: 'bob'),
    );

    transport.sentLines.clear();
    transport.emit(':bob!id@host JOIN #flutter');
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('MODE #flutter +v bob'));
    controller.dispose();
  });

  test('does not set mode when we lack privilege', () async {
    final (controller, transport) = await _connected();
    transport.emit(':AndroidIRCX!u@h JOIN #flutter');
    transport.emit(':server 353 AndroidIRCX = #flutter :AndroidIRCX');
    transport.emit(':server 366 AndroidIRCX #flutter :End of NAMES');
    await Future<void>.delayed(Duration.zero);

    await controller.addAutoModeEntry(
      const UserListEntry(type: UserListType.autoVoice, mask: 'bob'),
    );

    transport.sentLines.clear();
    transport.emit(':bob!id@host JOIN #flutter');
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.sentLines.where((l) => l.startsWith('MODE')),
      isEmpty,
    );
    controller.dispose();
  });

  test('auto-ops take priority and honor channel scope', () async {
    final (controller, transport) = await _connected();
    transport.emit(':AndroidIRCX!u@h JOIN #ops');
    transport.emit(':server 353 AndroidIRCX = #ops :@AndroidIRCX');
    transport.emit(':server 366 AndroidIRCX #ops :End of NAMES');
    await Future<void>.delayed(Duration.zero);

    await controller.addAutoModeEntry(
      const UserListEntry(
        type: UserListType.autoOp,
        mask: 'carol!*@*',
        channels: ['#ops'],
      ),
    );

    // Wrong channel: no auto-op.
    transport.emit(':AndroidIRCX!u@h JOIN #other');
    transport.emit(':server 353 AndroidIRCX = #other :@AndroidIRCX');
    transport.emit(':server 366 AndroidIRCX #other :End of NAMES');
    await Future<void>.delayed(Duration.zero);
    transport.sentLines.clear();
    transport.emit(':carol!id@host JOIN #other');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines.where((l) => l.startsWith('MODE')), isEmpty);

    // Right channel: auto-op.
    transport.emit(':carol!id@host JOIN #ops');
    await Future<void>.delayed(Duration.zero);
    expect(transport.sentLines, contains('MODE #ops +o carol'));

    controller.dispose();
  });
}

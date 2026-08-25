import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/presentation/chat_screen.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  @override
  Stream<String> get lines => _controller.stream;

  final sentLines = <String>[];

  void emit(String line) => _controller.add(line);

  @override
  Future<void> sendLine(String line) async {
    sentLines.add(line);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('message channel and nick tokens run chat actions', (
    tester,
  ) async {
    final transports = <_FakeTransport>[];
    final service = IrcService(
      transportConnector: (_) async {
        final t = _FakeTransport();
        transports.add(t);
        return t;
      },
    );
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

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();
    final transport = transports.single;
    transport.emit(':server 001 AndroidIRCX :Welcome');
    transport.emit(':AndroidIRCX!u@h JOIN #room');
    transport.emit(':server 353 AndroidIRCX = #room :@AndroidIRCX alice bob');
    transport.emit(':server 366 AndroidIRCX #room :End of NAMES');
    transport.emit(':alice!id@host PRIVMSG #room :hello bob join #dart');
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
    controller.selectTab(roomTab.id);
    await tester.pump();

    expect(controller.activeTab.name, '#room');
    expect(
      controller
          .messagesForTab(controller.activeTabId)
          .any((message) => message.content.contains('#dart')),
      isTrue,
    );

    await tester.tap(_richTextContaining('bob'));
    await tester.pump();
    expect(
      controller.tabs.any(
        (tab) => tab.type.name == 'query' && tab.name == 'bob',
      ),
      isTrue,
    );

    controller.selectTab(roomTab.id);
    await tester.pump();
    await tester.tap(_richTextContaining('#dart'));
    await tester.pump();
    expect(transport.sentLines, contains('JOIN #dart'));

    controller.dispose();
  });
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(text),
    description: 'RichText containing "$text"',
  );
}

import 'dart:async';

import 'package:androidircx/app/app.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/in_memory_network_repository.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/features/chat/presentation/chat_screen.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/connections/presentation/network_list_screen.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> sendLine(String line) async {}

  void emit(String line) {
    _controller.add(line);
  }
}

void main() {
  testWidgets('shows seeded network on bootstrap', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AndroidIrcxApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('AndroidIRCX'), findsOneWidget);
    expect(find.text('DBase'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('shows active sessions and auto-connect labels in network list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
      autoConnect: true,
    );
    final controller = NetworkListController(
      repository: InMemoryNetworkRepository(const [network]),
    );
    final registry = SessionRegistry();

    await controller.load();
    registry.obtainSession(network);

    await tester.pumpWidget(
      MaterialApp(
        home: NetworkListScreen(
          controller: controller,
          sessionRegistry: registry,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Active sessions'), findsOneWidget);
    expect(find.text('1 live'), findsOneWidget);
    expect(find.text('Disconnect all'), findsOneWidget);
    expect(find.text('Auto connect enabled'), findsOneWidget);
    expect(find.text('Open session'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Active nick: AndroidIRCX'), findsOneWidget);
    expect(find.text('Status: Idle'), findsOneWidget);
    expect(find.textContaining('Activity:'), findsNothing);

    registry.dispose();
    controller.dispose();
  });

  testWidgets('shows IRC services quick actions on the server tab', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(
        transportConnector: (_) async => transport,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('NickServ HELP'), findsOneWidget);
    expect(find.text('ChanServ HELP'), findsOneWidget);
    expect(find.text('MemoServ HELP'), findsOneWidget);
    await tester.tap(find.text('NickServ HELP'));
    await tester.pump();
    expect(find.text('NickServ'), findsWidgets);

    controller.dispose();
  });

  testWidgets('shows server playback actions in history tools for chat tabs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(
        transportConnector: (_) async => transport,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: controller),
      ),
    );
    await tester.pump();

    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :chathistory labeled-response');
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('History tools'));
    await tester.pumpAndSettle();

    expect(find.text('Server playback'), findsOneWidget);
    expect(find.text('Recent 25'), findsOneWidget);
    expect(find.text('Recent 100'), findsOneWidget);
    expect(find.text('Older 50'), findsOneWidget);
    expect(find.text('Newer 50'), findsOneWidget);
    expect(find.text('Around latest'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('toggles inline message search from the chat header', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(
        transportConnector: (_) async => transport,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: controller),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Search messages'));
    await tester.pump();
    expect(find.text('Search current tab'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'nickserv');
    await tester.pump();
    expect(find.text('0 matches'), findsOneWidget);

    await tester.tap(find.byTooltip('Close message search'));
    await tester.pump();
    expect(find.text('Search current tab'), findsNothing);

    controller.dispose();
  });

  testWidgets('shows message attachment cards and long-press actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(
        transportConnector: (_) async => transport,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: controller),
      ),
    );
    await tester.pump();

    transport.emit(':alice!user@example PRIVMSG AndroidIRCX :see https://example.com/file.pdf');
    await tester.pump();

    expect(find.text('Link'), findsOneWidget);
    expect(find.textContaining('https://example.com/file.pdf'), findsWidgets);

    await tester.longPress(find.textContaining('https://example.com/file.pdf').first);
    await tester.pumpAndSettle();

    expect(find.text('Copy clean text'), findsOneWidget);
    expect(find.text('Copy first link'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('fills composer from message quote and reply actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    final transport = _FakeTransport();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(
        transportConnector: (_) async => transport,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: controller),
      ),
    );
    await tester.pump();

    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':alice!user@example PRIVMSG #room :Hello there');
    await tester.pump();

    await tester.longPress(find.textContaining('Hello there').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quote in composer'));
    await tester.pumpAndSettle();
    expect(find.text('> Hello there'), findsOneWidget);

    await tester.longPress(find.textContaining('Hello there').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply with nick'));
    await tester.pumpAndSettle();
    expect(find.text('> Hello there alice: '), findsOneWidget);

    controller.dispose();
  });
}

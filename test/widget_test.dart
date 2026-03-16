import 'dart:async';

import 'package:androidircx/app/app.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/in_memory_network_repository.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/features/chat/presentation/chat_screen.dart';
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
}

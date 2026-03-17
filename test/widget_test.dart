import 'dart:async';
import 'dart:typed_data';

import 'package:androidircx/app/app.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/in_memory_network_repository.dart';
import 'package:androidircx/dcc/services/dcc_service.dart';
import 'package:androidircx/dcc/services/dcc_socket_backend.dart';
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
  final List<String> sentLines = <String>[];

  @override
  Stream<String> get lines => _controller.stream;

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> sendLine(String line) async {
    sentLines.add(line);
  }

  void emit(String line) {
    _controller.add(line);
  }
}

class _FakeDccConnection implements DccSocketConnection {
  final StreamController<List<int>> _controller = StreamController<List<int>>.broadcast();
  final List<List<int>> sentPackets = <List<int>>[];

  @override
  Stream<List<int>> get bytes => _controller.stream;

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> sendBytes(List<int> data) async {
    sentPackets.add(Uint8List.fromList(data));
  }
}

class _FakeDccServer implements DccSocketServer {
  _FakeDccServer(this.connection);

  final DccSocketConnection connection;

  @override
  String get address => '127.0.0.1';

  @override
  Stream<DccSocketConnection> get connections => Stream<DccSocketConnection>.value(connection);

  @override
  int get port => 5001;

  @override
  Future<void> close() async {}
}

class _FakeDccBackend implements DccSocketBackend {
  final _FakeDccConnection connection = _FakeDccConnection();

  @override
  Future<DccSocketServer> bindEphemeral() async => _FakeDccServer(connection);

  @override
  Future<DccSocketConnection> connect({
    required String host,
    required int port,
  }) async => connection;
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

  testWidgets('shows rich nick details in the channel user drawer', (tester) async {
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

    transport.emit(':alice!ident@example JOIN #room aliceAccount :Alice Example');
    transport.emit(':server 353 AndroidIRCX = #room :@alice!ident@example');
    transport.emit(':alice!ident@example AWAY :coffee');
    await tester.pump();
    await tester.pump();
    controller.selectTab(controller.tabs.firstWhere((tab) => tab.name == '#room').id);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.textContaining('account: aliceAccount'), findsWidgets);
    expect(find.textContaining('away: coffee'), findsOneWidget);

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
    final dccBackend = _FakeDccBackend();
    final controller = ChatSessionController(
      network: network,
      ircService: IrcService(
        transportConnector: (_) async => transport,
      ),
      dccService: DccService(backend: dccBackend),
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

  testWidgets('shows pending reply bar and sends tagged reply flow', (
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
    transport.emit('@msgid=seed-1 :alice!user@example PRIVMSG #room :Original text');
    await tester.pump();

    await tester.longPress(find.textContaining('Original text').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply to message'));
    await tester.pumpAndSettle();

    expect(find.text('Replying to alice'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Reply body');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(
      transport.sentLines,
      contains('@+draft/reply=seed-1 PRIVMSG #room :Reply body'),
    );

    controller.dispose();
  });

  testWidgets('shows delete message action and sends redact command', (
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
    transport.emit(':server CAP * ACK :draft/message-redaction');
    transport.emit('@msgid=seed-redact :alice!user@example PRIVMSG #room :Delete this');
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.textContaining('Delete this').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete message'), findsOneWidget);

    await tester.ensureVisible(find.text('Delete message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete message'));
    await tester.pump();

    expect(transport.sentLines, contains('REDACT #room seed-redact'));

    controller.dispose();
  });

  testWidgets('shows typing indicator and reaction chips from TAGMSG state', (
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
    transport.emit('@msgid=react-ui-1 :alice!user@example PRIVMSG #room :Hello');
    transport.emit('@+draft/react=react-ui-1\\::thumbsup: :bob!user@example TAGMSG #room');
    transport.emit('@+typing=active :alice!user@example TAGMSG #room');
    await tester.pump();
    await tester.pump();

    expect(find.textContaining(':thumbsup: 1'), findsOneWidget);
    expect(find.text('alice is typing…'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('shows dcc session banner and actions for incoming dcc tabs', (
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

    transport.emit(':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC CHAT chat 127001 5001\u0001');
    await tester.pump();
    await tester.pump();

    expect(find.text('DCC CHAT session'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsNothing);
    expect(find.text('Close'), findsOneWidget);

    controller.dispose();
  });
}

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

Future<ChatSessionController> _connectedController(
  List<_FakeTransport> transports,
) async {
  const network = NetworkConfig(
    id: 'dbase',
    name: 'DBase',
    host: 'irc.example.test',
    port: 6697,
    nickname: 'AndroidIRCX',
  );
  final service = IrcService(
    transportConnector: (_) async {
      final transport = _FakeTransport();
      transports.add(transport);
      return transport;
    },
  );
  return ChatSessionController(network: network, ircService: service);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('chat message list stays visible in short landscape', (
    tester,
  ) async {
    final transports = <_FakeTransport>[];
    final controller = await _connectedController(transports);

    // Landscape phone with the soft keyboard open (large bottom viewInsets).
    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();
    final transport = transports.single;
    transport.emit(':server 001 AndroidIRCX :Welcome');
    for (var i = 0; i < 20; i++) {
      transport.emit(':bob!bob@host NOTICE AndroidIRCX :message number $i');
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The message list keeps real height and renders messages; no overflow.
    expect(tester.takeException(), isNull);
    final listSize = tester.getSize(find.byType(ListView).first);
    expect(
      listSize.height,
      greaterThan(40),
      reason: 'message list collapsed to ${listSize.height}px in landscape',
    );
    expect(find.textContaining('message number'), findsWidgets);

    controller.dispose();
  });

  testWidgets('chat message list stays visible on the server tab', (
    tester,
  ) async {
    // Server tab shows the tall _ServiceQuickActions panel; it must not crush
    // the message list in a short viewport.
    final transports = <_FakeTransport>[];
    final controller = await _connectedController(transports);

    tester.view.physicalSize = const Size(2280, 1080);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: 620);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });

    await tester.pumpWidget(
      MaterialApp(home: ChatScreen(controller: controller)),
    );
    await tester.pump();
    transports.single.emit(':server 001 AndroidIRCX :Welcome');
    transports.single
        .emit(':server NOTICE AndroidIRCX :server message on the tab');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    final listSize = tester.getSize(find.byType(ListView).first);
    expect(listSize.height, greaterThan(20));

    controller.dispose();
  });
}

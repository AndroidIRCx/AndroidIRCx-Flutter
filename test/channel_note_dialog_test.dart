import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/data/channel_notes_repository.dart';
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

  void emit(String line) => _controller.add(line);

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  Future<void> sendLine(String line) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('long-press channel tab saves a per-channel note', (
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
    final notes = ChannelNotesRepository(
      prefsLoader: SharedPreferences.getInstance,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: controller, channelNotesRepository: notes),
      ),
    );
    await tester.pump();
    transports.single.emit(':server 001 AndroidIRCX :Welcome');
    transports.single.emit(':AndroidIRCX!u@h JOIN #flutter');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Open the navigation drawer that lists the tabs.
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    // Long-press the channel tab tile.
    await tester.longPress(find.widgetWithText(ListTile, '#flutter').last);
    await tester.pumpAndSettle();

    expect(find.text('Note for #flutter'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'ops: alice');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await notes.getNote('dbase', '#flutter'), 'ops: alice');

    // Unmount before disposing so pending snackbar animations don't touch the
    // disposed controller.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

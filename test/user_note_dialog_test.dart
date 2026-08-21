import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/data/user_notes_repository.dart';
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

  testWidgets('add a note for a nick from the channel user actions', (
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
    final notes = UserNotesRepository(
      prefsLoader: SharedPreferences.getInstance,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(controller: controller, userNotesRepository: notes),
      ),
    );
    await tester.pump();
    final t = transports.single;
    t.emit(':server 001 AndroidIRCX :Welcome');
    t.emit(':AndroidIRCX!u@h JOIN #flutter');
    t.emit(':server 353 AndroidIRCX = #flutter :AndroidIRCX bob');
    t.emit(':server 366 AndroidIRCX #flutter :End of NAMES');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openEndDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'bob').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();

    expect(find.text('Note for bob'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'met in #flutter');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await notes.getNote('dbase', 'bob'), 'met in #flutter');

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

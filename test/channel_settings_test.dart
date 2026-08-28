import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/in_memory_network_repository.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/data/channel_notes_repository.dart';
import 'package:androidircx/features/chat/presentation/channel_settings_screen.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
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
  testWidgets('channel settings edits auto-join and note', (tester) async {
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
      ircService: IrcService(transportConnector: (_) async => transport),
    );
    final repository = InMemoryNetworkRepository([network]);
    final networkController = NetworkListController(repository: repository);

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server 332 AndroidIRCX #room :Welcome to the room');
    transport.emit(':alice!user@example PRIVMSG #room :hi all');
    // Flush the stream microtasks inside the fake-async test zone.
    await tester.idle();

    final tab = controller.tabs.firstWhere((item) => item.name == '#room');

    await tester.pumpWidget(
      MaterialApp(
        home: ChannelSettingsScreen(
          controller: controller,
          tab: tab,
          networkController: networkController,
          notesRepository: ChannelNotesRepository(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Topic and recent log are shown.
    expect(find.text('Welcome to the room'), findsOneWidget);
    expect(find.textContaining('hi all'), findsWidgets);

    // Toggle auto-join and check the stored network config.
    await tester.tap(find.byKey(const Key('channel-settings-auto-join')));
    await tester.pumpAndSettle();
    var saved = (await repository.loadNetworks()).single;
    expect(saved.autoJoinChannels, contains('#room'));

    // Save a note and read it back through the repository.
    await tester.enterText(
      find.byKey(const Key('channel-settings-note')),
      'ops meeting every friday',
    );
    await tester.tap(find.byKey(const Key('channel-settings-save-note')));
    await tester.pumpAndSettle();
    expect(
      await ChannelNotesRepository().getNote('dbase', '#room'),
      'ops meeting every friday',
    );

    // Toggle auto-join back off.
    await tester.tap(find.byKey(const Key('channel-settings-auto-join')));
    await tester.pumpAndSettle();
    saved = (await repository.loadNetworks()).single;
    expect(saved.autoJoinChannels, isNot(contains('#room')));

    controller.dispose();
    networkController.dispose();
  });
}

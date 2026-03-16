import 'package:androidircx/app/app.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/in_memory_network_repository.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/connections/presentation/network_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    expect(find.text('Auto connect enabled'), findsOneWidget);
    expect(find.text('Open session'), findsOneWidget);
    expect(find.text('Active nick: AndroidIRCX'), findsOneWidget);

    registry.dispose();
    controller.dispose();
  });
}

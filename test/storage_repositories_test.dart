import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/shared_prefs_network_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:androidircx/features/chat/data/chat_session_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('shared prefs repositories', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('network repository seeds default network', () async {
      final repository = SharedPrefsNetworkRepository();

      final networks = await repository.loadNetworks();

      expect(networks, hasLength(1));
      expect(networks.first.name, 'DBase');
    });

    test('network repository saves and loads network', () async {
      final repository = SharedPrefsNetworkRepository();

      await repository.saveNetwork(
        const NetworkConfig(
          id: 'testnet',
          name: 'TestNet',
          host: 'irc.test.net',
          port: 6667,
          nickname: 'tester',
          useTls: false,
        ),
      );

      final networks = await repository.loadNetworks();

      expect(networks.any((item) => item.id == 'testnet'), isTrue);
    });

    test('settings repository saves and loads showRawEvents', () async {
      final repository = SharedPrefsSettingsRepository();

      await repository.saveSettings(const AppSettings(showRawEvents: false));
      final settings = await repository.loadSettings();

      expect(settings.showRawEvents, isFalse);
    });

    test('chat session persistence saves tabs and history', () async {
      final persistence = ChatSessionPersistence();
      const tab = ChatTab(
        id: 'channel::dbase::#flutter',
        name: '#flutter',
        type: ChatTabType.channel,
        networkId: 'dbase',
      );
      final message = IrcMessage(
        id: '1',
        tabId: tab.id,
        sender: 'nick',
        content: 'hello',
        timestamp: DateTime(2026, 3, 16, 12, 0),
      );

      await persistence.save(
        networkId: 'dbase',
        tabs: const [tab],
        messagesByTab: {
          tab.id: [message],
        },
        activeTabId: tab.id,
      );

      final snapshot = await persistence.load('dbase');

      expect(snapshot, isNotNull);
      expect(snapshot!.tabs.single.name, '#flutter');
      expect(snapshot.activeTabId, tab.id);
      expect(snapshot.messagesByTab[tab.id]!.single.content, 'hello');
    });
  });
}

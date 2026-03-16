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
          altNickname: 'tester_',
          useTls: false,
          saslMechanism: SaslMechanism.scramSha256,
          autoConnect: true,
        ),
      );

      final networks = await repository.loadNetworks();

      expect(networks.any((item) => item.id == 'testnet'), isTrue);
      final saved = networks.firstWhere((item) => item.id == 'testnet');
      expect(saved.autoConnect, isTrue);
      expect(saved.altNickname, 'tester_');
      expect(saved.saslMechanism, SaslMechanism.scramSha256);
    });

    test('network repository persists EXTERNAL SASL mechanism', () async {
      final repository = SharedPrefsNetworkRepository();

      await repository.saveNetwork(
        const NetworkConfig(
          id: 'certnet',
          name: 'CertNet',
          host: 'irc.cert.net',
          port: 6697,
          nickname: 'tester',
          altNickname: 'tester_',
          saslMechanism: SaslMechanism.external,
        ),
      );

      final saved = (await repository.loadNetworks())
          .firstWhere((item) => item.id == 'certnet');

      expect(saved.saslMechanism, SaslMechanism.external);
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

    test('chat session persistence restores growable message lists', () async {
      final persistence = ChatSessionPersistence();
      const tab = ChatTab(
        id: 'server::dbase',
        name: 'DBase',
        type: ChatTabType.server,
        networkId: 'dbase',
      );
      final message = IrcMessage(
        id: '1',
        tabId: tab.id,
        sender: '*',
        content: 'connected',
        timestamp: DateTime(2026, 3, 16, 12, 0),
        kind: IrcMessageKind.system,
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
      final restored = snapshot!.messagesByTab[tab.id]!;

      restored.add(
        IrcMessage(
          id: '2',
          tabId: tab.id,
          sender: '*',
          content: 'raw line',
          timestamp: DateTime(2026, 3, 16, 12, 1),
          kind: IrcMessageKind.raw,
        ),
      );

      expect(restored, hasLength(2));
    });
  });
}

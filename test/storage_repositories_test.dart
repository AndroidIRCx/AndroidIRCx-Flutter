import 'dart:convert';

import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/security/secret_redaction.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/storage/network_secret_keys.dart';
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
          webSocketPort: 16667,
          webSocketPath: '/irc',
          saslMechanism: SaslMechanism.scramSha256,
          autoConnect: true,
          autoJoinChannels: ['#androidircx', '#flutter'],
          profileLabel: 'Main profile',
          profileGroup: 'General',
        ),
      );

      final networks = await repository.loadNetworks();

      expect(networks.any((item) => item.id == 'testnet'), isTrue);
      final saved = networks.firstWhere((item) => item.id == 'testnet');
      expect(saved.autoConnect, isTrue);
      expect(saved.altNickname, 'tester_');
      expect(saved.webSocketPort, 16667);
      expect(saved.webSocketPath, '/irc');
      expect(saved.saslMechanism, SaslMechanism.scramSha256);
      expect(saved.autoJoinChannels, ['#androidircx', '#flutter']);
      expect(saved.profileLabel, 'Main profile');
      expect(saved.profileGroup, 'General');
    });

    test('network config backfills absent auto-join and profile fields', () {
      final saved = NetworkConfig.fromJson({
        'id': 'legacy',
        'name': 'LegacyNet',
        'host': 'irc.legacy.test',
        'port': 6667,
        'nickname': 'tester',
      });

      expect(saved.autoJoinChannels, isEmpty);
      expect(saved.profileLabel, isNull);
      expect(saved.profileGroup, isNull);
    });

    test('network config sanitizes auto-join channel lists', () {
      final saved = NetworkConfig.fromJson({
        'id': 'channels',
        'name': 'ChannelsNet',
        'host': 'irc.channels.test',
        'port': 6667,
        'nickname': 'tester',
        'autoJoinChannels': [' #one ', '', 42, '#two'],
        'profileLabel': '  Work  ',
        'profileGroup': ' ',
      });

      expect(saved.autoJoinChannels, ['#one', '#two']);
      expect(saved.profileLabel, 'Work');
      expect(saved.profileGroup, isNull);
    });

    test('network config sanitizes and redacts auto-join channel keys', () {
      final saved = NetworkConfig.fromJson({
        'id': 'keyed-channels',
        'name': 'KeyedChannelsNet',
        'host': 'irc.channels.test',
        'port': 6667,
        'nickname': 'tester',
        'autoJoinChannelKeys': {
          ' secret ': ' opensesame ',
          '#empty': ' ',
          '#bad': 42,
        },
      });

      expect(saved.autoJoinChannelKeys, {'#secret': 'opensesame'});
      expect(saved.toJson()['autoJoinChannelKeys'], {'#secret': 'opensesame'});
      expect(saved.toRedactedJson()['autoJoinChannelKeys'], '[REDACTED]');
      expect(saved.toString(), isNot(contains('opensesame')));
    });

    test(
      'network config redacts classified secrets in public representations',
      () {
        const config = NetworkConfig(
          id: 'secret-net',
          name: 'SecretNet',
          host: 'irc.secret.test',
          port: 6697,
          nickname: 'tester',
          password: 'server-pass-value',
          saslAccount: 'sasl-account',
          saslPassword: 'sasl-pass-value',
        );

        final redacted = config.toRedactedJson();
        final redactedText = jsonEncode(redacted);
        final debugText = config.toString();

        expect(config.toJson()['password'], 'server-pass-value');
        expect(config.toJson()['saslPassword'], 'sasl-pass-value');
        expect(redacted['password'], '[REDACTED]');
        expect(redacted['saslPassword'], '[REDACTED]');
        expect(redacted['saslAccount'], 'sasl-account');
        expect(redactedText, isNot(contains('server-pass-value')));
        expect(redactedText, isNot(contains('sasl-pass-value')));
        expect(debugText, isNot(contains('server-pass-value')));
        expect(debugText, isNot(contains('sasl-pass-value')));
        expect(debugText, contains('[REDACTED]'));
      },
    );

    test(
      'redaction covers future token certificate and private key fields',
      () {
        final redacted = redactNetworkSecrets({
          'name': 'SecretNet',
          'saslAccount': 'sasl-account',
          'serverPassword': 'server-pass-value',
          'authToken': 'auth-token-value',
          'clientPrivateKey': 'private-key-value',
          'clientCertificate': 'client-cert-value',
          'certificateFingerprint': 'public-fingerprint-value',
        });

        expect(redacted['name'], 'SecretNet');
        expect(redacted['saslAccount'], 'sasl-account');
        expect(redacted['serverPassword'], '[REDACTED]');
        expect(redacted['authToken'], '[REDACTED]');
        expect(redacted['clientPrivateKey'], '[REDACTED]');
        expect(redacted['clientCertificate'], '[REDACTED]');
        expect(redacted['certificateFingerprint'], 'public-fingerprint-value');
        expect(jsonEncode(redacted), isNot(contains('server-pass-value')));
        expect(jsonEncode(redacted), isNot(contains('auth-token-value')));
        expect(jsonEncode(redacted), isNot(contains('private-key-value')));
        expect(jsonEncode(redacted), isNot(contains('client-cert-value')));
      },
    );

    test('network config leaves absent or empty secrets unredacted', () {
      const config = NetworkConfig(
        id: 'empty-secret-net',
        name: 'EmptySecretNet',
        host: 'irc.empty-secret.test',
        port: 6667,
        nickname: 'tester',
        password: '',
      );

      final redacted = config.toRedactedJson();

      expect(redacted['password'], '');
      expect(redacted['saslPassword'], isNull);
    });

    test(
      'network repository raw fallback persists secrets in shared prefs',
      () async {
        final repository = SharedPrefsNetworkRepository();

        await repository.saveNetwork(
          const NetworkConfig(
            id: 'secret-net',
            name: 'SecretNet',
            host: 'irc.secret.test',
            port: 6697,
            nickname: 'tester',
            password: 'server-pass-value',
            saslAccount: 'sasl-account',
            saslPassword: 'sasl-pass-value',
          ),
        );

        final saved = (await repository.loadNetworks()).firstWhere(
          (item) => item.id == 'secret-net',
        );

        expect(repository.storesSecretsInRawJson, isTrue);
        expect(saved.password, 'server-pass-value');
        expect(saved.saslPassword, 'sasl-pass-value');
        expect(saved.toString(), isNot(contains('server-pass-value')));
        expect(saved.toString(), isNot(contains('sasl-pass-value')));
      },
    );

    test(
      'network repository can split secrets to SecretStorage and public JSON',
      () async {
        final storage = InMemorySecretStorage();
        final repository = SharedPrefsNetworkRepository(secretStorage: storage);

        await repository.saveNetwork(
          const NetworkConfig(
            id: 'secret-net',
            name: 'SecretNet',
            host: 'irc.secret.test',
            port: 6697,
            nickname: 'tester',
            password: 'server-pass-value',
            saslAccount: 'sasl-account',
            saslPassword: 'sasl-pass-value',
            autoJoinChannels: ['#secret'],
            autoJoinChannelKeys: {'#secret': 'channel-key-value'},
            profileLabel: 'Secure profile',
            profileGroup: 'Ops',
          ),
        );

        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('androidircx.networks')!;
        final decoded = jsonDecode(raw) as List<dynamic>;
        final savedJson = decoded.cast<Map<String, Object?>>().firstWhere(
          (item) => item['id'] == 'secret-net',
        );

        expect(repository.storesSecretsInRawJson, isFalse);
        expect(raw, isNot(contains('server-pass-value')));
        expect(raw, isNot(contains('sasl-pass-value')));
        expect(raw, isNot(contains('channel-key-value')));
        expect(savedJson['password'], isNull);
        expect(savedJson['saslPassword'], isNull);
        expect(savedJson['autoJoinChannelKeys'], isNull);
        expect(
          await storage.getSecret('androidircx.network.secret-net.password'),
          'server-pass-value',
        );
        expect(
          await storage.getSecret(
            'androidircx.network.secret-net.saslPassword',
          ),
          'sasl-pass-value',
        );
        expect(
          await storage.getSecret(
            'androidircx.network.secret-net.autoJoinChannelKeys',
          ),
          '{"#secret":"channel-key-value"}',
        );

        final saved = (await repository.loadNetworks()).firstWhere(
          (item) => item.id == 'secret-net',
        );
        expect(saved.password, 'server-pass-value');
        expect(saved.saslPassword, 'sasl-pass-value');
        expect(saved.profileLabel, 'Secure profile');
        expect(saved.profileGroup, 'Ops');
      },
    );

    test('network repository deletes split network secrets', () async {
      final storage = InMemorySecretStorage();
      final repository = SharedPrefsNetworkRepository(secretStorage: storage);

      await repository.saveNetwork(
        const NetworkConfig(
          id: 'delete-secret-net',
          name: 'DeleteSecretNet',
          host: 'irc.delete-secret.test',
          port: 6697,
          nickname: 'tester',
          password: 'server-pass-value',
          saslPassword: 'sasl-pass-value',
          autoJoinChannelKeys: {'#secret': 'channel-key-value'},
        ),
      );

      await repository.deleteNetwork('delete-secret-net');

      expect(
        await storage.getSecret(
          'androidircx.network.delete-secret-net.password',
        ),
        isNull,
      );
      expect(
        await storage.getSecret(
          'androidircx.network.delete-secret-net.saslPassword',
        ),
        isNull,
      );
      expect(
        await storage.getSecret(
          'androidircx.network.delete-secret-net.autoJoinChannelKeys',
        ),
        isNull,
      );
      expect(
        (await repository.loadNetworks()).any(
          (item) => item.id == 'delete-secret-net',
        ),
        isFalse,
      );
    });

    test(
      'network repository migrates legacy raw JSON secrets on load',
      () async {
        SharedPreferences.setMockInitialValues({
          'androidircx.networks': jsonEncode([
            {
              'id': 'legacy-secret-net',
              'name': 'LegacySecretNet',
              'host': 'irc.legacy-secret.test',
              'port': 6697,
              'nickname': 'tester',
              'password': 'legacy-server-pass-value',
              'saslAccount': 'sasl-account',
              'saslPassword': 'legacy-sasl-pass-value',
            },
          ]),
        });
        final storage = InMemorySecretStorage();
        final repository = SharedPrefsNetworkRepository(secretStorage: storage);

        final saved = (await repository.loadNetworks()).single;

        expect(saved.password, 'legacy-server-pass-value');
        expect(saved.saslPassword, 'legacy-sasl-pass-value');
        expect(
          await storage.getSecret(
            'androidircx.network.legacy-secret-net.password',
          ),
          'legacy-server-pass-value',
        );
        expect(
          await storage.getSecret(
            'androidircx.network.legacy-secret-net.saslPassword',
          ),
          'legacy-sasl-pass-value',
        );

        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('androidircx.networks')!;
        final decoded = jsonDecode(raw) as List<dynamic>;
        final migratedJson = decoded.cast<Map<String, Object?>>().single;
        expect(raw, isNot(contains('legacy-server-pass-value')));
        expect(raw, isNot(contains('legacy-sasl-pass-value')));
        expect(migratedJson['password'], isNull);
        expect(migratedJson['saslPassword'], isNull);
      },
    );

    test(
      'network secret migration keys are stable and redact planned writes',
      () {
        const config = NetworkConfig(
          id: 'secret-net',
          name: 'SecretNet',
          host: 'irc.secret.test',
          port: 6697,
          nickname: 'tester',
          password: 'server-pass-value',
          saslAccount: 'sasl-account',
          saslPassword: 'sasl-pass-value',
        );

        final plannedSecrets = networkSecretMigrationValues(config);
        final redactedPlan = redactNetworkSecretMigrationValues(plannedSecrets);

        expect(
          plannedSecrets.keys,
          containsAll(<String>[
            'androidircx.network.secret-net.password',
            'androidircx.network.secret-net.saslPassword',
          ]),
        );
        expect(
          plannedSecrets['androidircx.network.secret-net.password'],
          'server-pass-value',
        );
        expect(
          plannedSecrets['androidircx.network.secret-net.saslPassword'],
          'sasl-pass-value',
        );
        expect(
          redactedPlan['androidircx.network.secret-net.password'],
          '[REDACTED]',
        );
        expect(
          redactedPlan['androidircx.network.secret-net.saslPassword'],
          '[REDACTED]',
        );
        expect(jsonEncode(redactedPlan), isNot(contains('server-pass-value')));
        expect(jsonEncode(redactedPlan), isNot(contains('sasl-pass-value')));
      },
    );

    test(
      'in-memory secret storage supports future network secret migration flow',
      () async {
        final storage = InMemorySecretStorage();
        const config = NetworkConfig(
          id: 'secret-net',
          name: 'SecretNet',
          host: 'irc.secret.test',
          port: 6697,
          nickname: 'tester',
          password: 'server-pass-value',
          saslPassword: 'sasl-pass-value',
        );

        final plannedSecrets = networkSecretMigrationValues(config);
        for (final entry in plannedSecrets.entries) {
          await storage.setSecret(entry.key, entry.value);
        }

        expect(
          await storage.getSecret('androidircx.network.secret-net.password'),
          'server-pass-value',
        );
        expect(
          await storage.getSecret(
            'androidircx.network.secret-net.saslPassword',
          ),
          'sasl-pass-value',
        );
        expect(
          await storage.getAllSecretKeys(),
          plannedSecrets.keys.toList()..sort(),
        );

        await storage.setSecret('androidircx.network.secret-net.password', '');
        expect(
          await storage.getSecret('androidircx.network.secret-net.password'),
          isNull,
        );

        final status = await storage.getStatus();
        expect(status.isSecure, isFalse);
        expect(status.backend, SecretStorageBackend.inMemory);
        expect(status.warning, isNotNull);
      },
    );

    test('platform secret storage reports secure backend', () async {
      final status = await FlutterSecureSecretStorage().getStatus();

      expect(status.isSecure, isTrue);
      expect(status.isFallback, isFalse);
      expect(status.backend, SecretStorageBackend.platformSecureStorage);
      expect(status.warning, isNull);
    });

    test('shared prefs network repository declares raw fallback behavior', () {
      expect(
        SharedPrefsNetworkRepository.rawJsonFallbackStoresNetworkSecrets,
        isTrue,
      );
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

      final saved = (await repository.loadNetworks()).firstWhere(
        (item) => item.id == 'certnet',
      );

      expect(saved.saslMechanism, SaslMechanism.external);
    });

    test('network repository backfills DBase websocket port', () async {
      SharedPreferences.setMockInitialValues({
        'androidircx.networks': jsonEncode([
          {
            'id': 'dbase',
            'name': 'DBase',
            'host': 'irc.dbase.in.rs',
            'port': 6697,
            'nickname': 'AndroidIRCX',
            'altNickname': 'AndroidIRCX_',
            'username': 'androidircx',
            'realName': 'AndroidIRCX',
            'useTls': true,
            'saslMechanism': 'plain',
            'autoConnect': false,
          },
        ]),
      });
      final repository = SharedPrefsNetworkRepository();

      final saved = (await repository.loadNetworks()).single;

      expect(saved.webSocketPort, 16697);
    });

    test('settings repository saves and loads chat display settings', () async {
      final repository = SharedPrefsSettingsRepository();

      await repository.saveSettings(
        const AppSettings(
          showRawEvents: false,
          noticeRouting: NoticeRoutingMode.notice,
          showHeaderSearchButton: false,
          showAttachmentPreviews: false,
        ),
      );
      final settings = await repository.loadSettings();

      expect(settings.showRawEvents, isFalse);
      expect(settings.noticeRouting, NoticeRoutingMode.notice);
      expect(settings.showHeaderSearchButton, isFalse);
      expect(settings.showAttachmentPreviews, isFalse);
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
        tags: const <String, String?>{'time': '2026-03-16T12:00:00.000Z'},
        attachments: const [
          IrcMessageAttachment(
            type: IrcMessageAttachmentType.image,
            label: 'Image',
            uri: 'https://example.test/a.png',
          ),
        ],
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
      expect(snapshot.messagesByTab[tab.id]!.single.attachments, hasLength(1));
      expect(
        snapshot.messagesByTab[tab.id]!.single.attachments.single.uri,
        'https://example.test/a.png',
      );
      expect(
        snapshot.messagesByTab[tab.id]!.single.tags['time'],
        '2026-03-16T12:00:00.000Z',
      );
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

    test(
      'chat session persistence applies retention and msgid dedupe',
      () async {
        final persistence = ChatSessionPersistence(maxMessagesPerTab: 2);
        const tab = ChatTab(
          id: 'channel::dbase::#flutter',
          name: '#flutter',
          type: ChatTabType.channel,
          networkId: 'dbase',
        );
        final messages = [
          IrcMessage(
            id: '1',
            tabId: tab.id,
            sender: 'alice',
            content: 'old',
            timestamp: DateTime(2026, 3, 16, 12),
            tags: const {'msgid': 'dupe'},
          ),
          IrcMessage(
            id: '2',
            tabId: tab.id,
            sender: 'alice',
            content: 'duplicate',
            timestamp: DateTime(2026, 3, 16, 12, 1),
            tags: const {'msgid': 'dupe'},
          ),
          IrcMessage(
            id: '3',
            tabId: tab.id,
            sender: 'bob',
            content: 'newer',
            timestamp: DateTime(2026, 3, 16, 12, 2),
            tags: const {'msgid': 'newer'},
          ),
        ];

        await persistence.save(
          networkId: 'dbase',
          tabs: const [tab],
          messagesByTab: {tab.id: messages},
          activeTabId: tab.id,
        );

        final snapshot = await persistence.load('dbase');
        final restored = snapshot!.messagesByTab[tab.id]!;

        expect(restored.map((message) => message.content), ['old', 'newer']);
      },
    );
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/dcc_session.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/dcc/services/dcc_service.dart';
import 'package:androidircx/dcc/services/dcc_socket_backend.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/data/chat_session_persistence.dart';
import 'package:androidircx/features/chat/data/message_history_repository.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final List<String> sentLines = <String>[];
  int closeCount = 0;

  @override
  Stream<String> get lines => _controller.stream;

  void emit(String line) {
    _controller.add(line);
  }

  void emitError(Object error) {
    _controller.addError(error);
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  @override
  Future<void> sendLine(String line) async {
    sentLines.add(line);
  }
}

class _FakeDccConnection implements DccSocketConnection {
  final StreamController<List<int>> _controller =
      StreamController<List<int>>.broadcast();
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

  void emitBytes(List<int> data) {
    _controller.add(Uint8List.fromList(data));
  }

  Future<void> finish() => _controller.close();
}

class _FakeDccServer implements DccSocketServer {
  _FakeDccServer(this.connection);

  final DccSocketConnection connection;

  @override
  String get address => '127.0.0.1';

  @override
  Stream<DccSocketConnection> get connections =>
      Stream<DccSocketConnection>.value(connection);

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

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('reconnect lifecycle', () {
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.example.test',
      port: 6697,
      nickname: 'AndroidIRCX',
    );

    ChatSessionController controllerFor(IrcService service) {
      return ChatSessionController(
        network: network,
        ircService: service,
        reconnectBaseDelay: const Duration(milliseconds: 1),
        reconnectMaxDelay: const Duration(milliseconds: 4),
        reconnectJitterFactor: 0,
        maxReconnectAttempts: 2,
      );
    }

    test('manual disconnect cancels pending reconnect', () async {
      final transports = <_FakeTransport>[];
      final service = IrcService(
        transportConnector: (_) async {
          final transport = _FakeTransport();
          transports.add(transport);
          return transport;
        },
      );
      final controller = controllerFor(service);

      await controller.start();
      transports.single.emit(':server 001 AndroidIRCX :Welcome');
      await Future<void>.delayed(Duration.zero);
      await transports.single.close();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isReconnectScheduled, isTrue);
      expect(controller.connection.phase, ConnectionPhase.reconnecting);

      await controller.disconnect();
      expect(controller.isReconnectScheduled, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(transports, hasLength(1));

      controller.dispose();
    });

    test('dispose cancels reconnect timer and subscriptions', () async {
      final transports = <_FakeTransport>[];
      final service = IrcService(
        transportConnector: (_) async {
          final transport = _FakeTransport();
          transports.add(transport);
          return transport;
        },
      );
      final controller = controllerFor(service);

      await controller.start();
      transports.single.emit(':server 001 AndroidIRCX :Welcome');
      await Future<void>.delayed(Duration.zero);
      await transports.single.close();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isReconnectScheduled, isTrue);

      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(transports, hasLength(1));
      expect(transports.single.closeCount, greaterThanOrEqualTo(1));
    });

    test('error schedules bounded reconnect attempts', () async {
      var attempts = 0;
      final service = IrcService(
        transportConnector: (_) async {
          attempts += 1;
          throw StateError('socket failed');
        },
      );
      final controller = controllerFor(service);

      await controller.start();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isReconnectScheduled, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts, 3); // initial + two bounded reconnect attempts.
      expect(controller.isReconnectScheduled, isFalse);

      controller.dispose();
    });

    test('successful reconnect resets attempt count', () async {
      final transports = <_FakeTransport>[];
      final service = IrcService(
        transportConnector: (_) async {
          final transport = _FakeTransport();
          transports.add(transport);
          return transport;
        },
      );
      final controller = controllerFor(service);

      await controller.start();
      transports[0].emit(':server 001 AndroidIRCX :Welcome');
      await Future<void>.delayed(Duration.zero);
      await transports[0].close();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(transports, hasLength(2));

      transports[1].emit(':server 001 AndroidIRCX :Welcome back');
      await Future<void>.delayed(Duration.zero);
      expect(controller.isReconnectScheduled, isFalse);
      await transports[1].close();
      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingReconnectDelay, const Duration(milliseconds: 1));

      controller.dispose();
    });

    test('socket stream error enters reconnecting state', () async {
      final transports = <_FakeTransport>[];
      final service = IrcService(
        transportConnector: (_) async {
          final transport = _FakeTransport();
          transports.add(transport);
          return transport;
        },
      );
      final controller = controllerFor(service);

      await controller.start();
      transports.single.emit(':server 001 AndroidIRCX :Welcome');
      await Future<void>.delayed(Duration.zero);

      transports.single.emitError(StateError('socket read failed'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.connection.phase, ConnectionPhase.reconnecting);
      expect(controller.connection.message, contains('Reconnecting'));
      expect(controller.isReconnectScheduled, isTrue);

      controller.dispose();
    });

    test('network availability pauses and resumes reconnects once', () async {
      final transports = <_FakeTransport>[];
      final service = IrcService(
        transportConnector: (_) async {
          final transport = _FakeTransport();
          transports.add(transport);
          return transport;
        },
      );
      final controller = controllerFor(service);

      await controller.start();
      transports.single.emit(':server 001 AndroidIRCX :Welcome');
      await Future<void>.delayed(Duration.zero);

      await controller.handleNetworkAvailabilityChanged(false);
      await Future<void>.delayed(Duration.zero);

      expect(controller.connection.phase, ConnectionPhase.disconnected);
      expect(controller.isReconnectScheduled, isFalse);
      expect(transports.single.closeCount, 1);
      expect(
        controller
            .messagesForTab(controller.activeTabId)
            .any((message) => message.content.contains('reconnect is paused')),
        isTrue,
      );

      await Future<void>.delayed(const Duration(milliseconds: 6));
      expect(transports, hasLength(1));

      await controller.handleNetworkAvailabilityChanged(true);
      await Future<void>.delayed(Duration.zero);

      expect(transports, hasLength(2));
      expect(controller.isReconnectScheduled, isFalse);

      await controller.handleNetworkAvailabilityChanged(true);
      await Future<void>.delayed(Duration.zero);

      expect(transports, hasLength(2));

      controller.dispose();
    });

    test(
      'IRC ERROR enters reconnecting state without waiting for socket close',
      () async {
        final transports = <_FakeTransport>[];
        final service = IrcService(
          transportConnector: (_) async {
            final transport = _FakeTransport();
            transports.add(transport);
            return transport;
          },
        );
        final controller = controllerFor(service);

        await controller.start();
        transports.single.emit(':server 001 AndroidIRCX :Welcome');
        await Future<void>.delayed(Duration.zero);

        transports.single.emit(
          'ERROR :Closing Link: AndroidIRCX (Ping timeout)',
        );
        await Future<void>.delayed(Duration.zero);

        expect(controller.connection.phase, ConnectionPhase.reconnecting);
        expect(controller.isReconnectScheduled, isTrue);
        expect(
          controller
              .messagesForTab(controller.activeTabId)
              .any((message) => message.content.contains('Ping timeout')),
          isTrue,
        );

        controller.dispose();
      },
    );

    test('reconnect delay applies bounded jitter', () async {
      final service = IrcService(
        transportConnector: (_) async => throw StateError('socket failed'),
      );
      final controller = ChatSessionController(
        network: network,
        ircService: service,
        reconnectBaseDelay: const Duration(milliseconds: 100),
        reconnectMaxDelay: const Duration(milliseconds: 500),
        reconnectJitterFactor: 0.5,
        reconnectJitterSampler: () => 1,
        maxReconnectAttempts: 1,
      );

      await controller.start();
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.pendingReconnectDelay,
        const Duration(milliseconds: 150),
      );
      expect(controller.connection.phase, ConnectionPhase.reconnecting);
      expect(controller.connection.message, contains('150ms'));

      controller.dispose();
    });
  });

  test(
    'app lifecycle pause flushes message history without reconnecting',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      const network = NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
      );
      final controller = ChatSessionController(
        network: network,
        ircService: service,
        reconnectJitterFactor: 0,
      );

      await controller.start();
      transport.emit(':server 001 AndroidIRCX :Welcome');
      await Future<void>.delayed(Duration.zero);
      transport.emit(':Alice!a@example PRIVMSG AndroidIRCX :hello from pause');
      await Future<void>.delayed(Duration.zero);

      await controller.handleAppLifecycleState(AppLifecycleState.paused);

      final snapshot = await ChatSessionPersistence().load(network.id);
      expect(snapshot, isNotNull);
      expect(
        snapshot!.messagesByTab.values
            .expand((messages) => messages)
            .any((message) => message.content == 'hello from pause'),
        isTrue,
      );
      expect(controller.connection.phase, ConnectionPhase.connected);
      expect(controller.isReconnectScheduled, isFalse);

      controller.dispose();
    },
  );

  test('routes SASL/auth numerics into server messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
        saslAccount: 'alice',
        saslPassword: 'secret',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      ':server 900 AndroidIRCX alice!ident@example :You are now logged in as alice',
    );
    transport.emit(':server 903 AndroidIRCX :SASL authentication successful');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('logged in as alice'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('SASL authentication successful'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('auto-joins configured channels once after MOTD ends', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        autoJoinChannels: ['#androidircx', 'flutter', '#androidircx'],
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    await Future<void>.delayed(Duration.zero);
    expect(
      transport.sentLines.where((line) => line.startsWith('JOIN ')),
      isEmpty,
    );

    transport.emit(':server 376 AndroidIRCX :End of /MOTD command.');
    transport.emit(':server 376 AndroidIRCX :End of /MOTD command again.');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.sentLines.where((line) => line == 'JOIN #androidircx'),
      hasLength(1),
    );
    expect(
      transport.sentLines.where((line) => line == 'JOIN #flutter'),
      hasLength(1),
    );
    expect(
      controller.tabs.any(
        (tab) => tab.type == ChatTabType.channel && tab.name == '#androidircx',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('auto-joins configured channels after no-MOTD numeric', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        autoJoinChannels: ['#nomotd'],
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    transport.emit(':server 422 AndroidIRCX :MOTD File is missing');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('JOIN #nomotd'));

    controller.dispose();
  });

  test(
    'sends NickServ fallback before keyed auto-join when SASL is unavailable',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          saslAccount: 'alice',
          saslPassword: 'secret',
          serviceAuthFallback: ServiceAuthFallback.nickServ,
          autoJoinChannels: ['#secret'],
          autoJoinChannelKeys: {'#secret': 'opensesame'},
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':server CAP * LS :server-time');
      await Future<void>.delayed(Duration.zero);
      transport.emit(':server 001 AndroidIRCX :Welcome');
      await Future<void>.delayed(Duration.zero);
      transport.emit(':server 376 AndroidIRCX :End of /MOTD command.');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final identifyIndex = transport.sentLines.indexOf(
        'PRIVMSG NickServ :IDENTIFY alice secret',
      );
      final joinIndex = transport.sentLines.indexOf('JOIN #secret opensesame');

      expect(identifyIndex, isNonNegative);
      expect(joinIndex, isNonNegative);
      expect(identifyIndex, lessThan(joinIndex));
      expect(
        controller.activeMessages.map((message) => message.content).join('\n'),
        isNot(contains('alice secret')),
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('IDENTIFY alice [REDACTED]'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('auto-joins keyed channels without duplicating case variants', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        autoJoinChannels: ['secret', '#SECRET', '#public'],
        autoJoinChannelKeys: {'#secret': 'opensesame'},
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    transport.emit(':server 376 AndroidIRCX :End of /MOTD command.');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.sentLines.where((line) => line == 'JOIN #secret opensesame'),
      hasLength(1),
    );
    expect(
      transport.sentLines.where((line) => line == 'JOIN #public'),
      hasLength(1),
    );
    expect(
      transport.sentLines.where((line) => line.startsWith('JOIN #SECRET')),
      isEmpty,
    );

    controller.dispose();
  });

  test('suggests composer nick and channel completions', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    await controller.joinChannel(
      const JoinChannelRequest(channel: '#androidircx'),
    );
    transport.emit(':server 353 AndroidIRCX = #room :@alice bob carol');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.name == '#room').id,
    );

    final nickSuggestions = controller.autocompleteSuggestionsForComposer(
      'hello al',
    );
    expect(nickSuggestions.map((item) => item.text), contains('alice'));
    expect(
      controller.applyComposerAutocompleteSuggestion(
        'hello al there',
        nickSuggestions.firstWhere((item) => item.text == 'alice'),
      ),
      'hello alice there',
    );

    final channelSuggestions = controller.autocompleteSuggestionsForComposer(
      '/msg #and',
    );
    expect(
      channelSuggestions.map((item) => item.text),
      contains('#androidircx'),
    );
    expect(
      controller.applyComposerAutocompleteSuggestion(
        '/msg #and hello',
        channelSuggestions.firstWhere((item) => item.text == '#androidircx'),
      ),
      '/msg #androidircx hello',
    );

    expect(controller.autocompleteSuggestionsForComposer('/n'), isEmpty);

    controller.dispose();
  });

  test(
    'tracks unread counts for inactive tabs and clears on selection',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':alice!user@example PRIVMSG #room :one');
      await Future<void>.delayed(Duration.zero);
      transport.emit(':bob!user@example PRIVMSG #room :two');
      await Future<void>.delayed(Duration.zero);

      var roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      expect(roomTab.hasActivity, isTrue);
      expect(roomTab.unreadCount, 2);

      controller.selectTab(roomTab.id);
      roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      expect(roomTab.hasActivity, isFalse);
      expect(roomTab.unreadCount, 0);

      controller.dispose();
    },
  );

  test('sends IRC service commands through private messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/ns identify secret');
    await controller.handleComposerSubmit('/cs op #androidircx AndroidIRCX');

    expect(transport.sentLines, contains('PRIVMSG NickServ :identify secret'));
    expect(
      transport.sentLines,
      contains('PRIVMSG ChanServ :op #androidircx AndroidIRCX'),
    );
    expect(
      controller.tabs.any(
        (tab) => tab.type.name == 'query' && tab.name == 'NickServ',
      ),
      isTrue,
    );
    await controller.handleComposerSubmit('/ms send AndroidIRCX hello');
    await controller.handleComposerSubmit('/bs botlist');

    expect(
      transport.sentLines,
      contains('PRIVMSG MemoServ :send AndroidIRCX hello'),
    );
    expect(transport.sentLines, contains('PRIVMSG BotServ :botlist'));
    expect(controller.activeTab.name, 'BotServ');
    expect(
      controller.activeMessages.any(
        (message) =>
            message.sender == 'AndroidIRCX' && message.content == 'botlist',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'routes incoming IRC service notices and messages into service tabs',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(
        ':NickServ!service@services NOTICE AndroidIRCX :This nickname is registered.',
      );
      transport.emit(
        ':MemoServ!service@services PRIVMSG AndroidIRCX :You have 2 new memos.',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.tabs.any(
          (tab) => tab.type.name == 'query' && tab.name == 'NickServ',
        ),
        isTrue,
      );
      expect(
        controller.tabs.any(
          (tab) => tab.type.name == 'query' && tab.name == 'MemoServ',
        ),
        isTrue,
      );

      controller.selectTab(
        controller.tabs
            .firstWhere(
              (tab) => tab.type.name == 'query' && tab.name == 'NickServ',
            )
            .id,
      );
      expect(
        controller.activeMessages.any(
          (message) =>
              message.sender == 'NickServ' &&
              message.content.contains('registered'),
        ),
        isTrue,
      );

      controller.selectTab(
        controller.tabs
            .firstWhere(
              (tab) => tab.type.name == 'query' && tab.name == 'MemoServ',
            )
            .id,
      );
      expect(
        controller.activeMessages.any(
          (message) =>
              message.sender == 'MemoServ' &&
              message.content.contains('2 new memos'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('tracks outgoing notice commands in the matching tab', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit(
      '/notice NickServ STATUS AndroidIRCX',
    );

    expect(
      transport.sentLines,
      contains('NOTICE NickServ :STATUS AndroidIRCX'),
    );
    expect(controller.activeTab.name, 'NickServ');
    expect(
      controller.activeMessages.any(
        (message) =>
            message.isOwn &&
            message.sender == 'AndroidIRCX' &&
            message.content == 'STATUS AndroidIRCX',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'sends reply-tagged messages through privmsg when reply target is provided',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      await controller.handleComposerSubmit('reply body', replyTo: 'msg-123');

      expect(
        transport.sentLines,
        contains('@+draft/reply=msg-123 PRIVMSG #room :reply body'),
      );

      controller.dispose();
    },
  );

  test(
    'routes incoming notices to a dedicated notice tab when configured',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
        settingsRepository: _FakeSettingsRepository(
          const AppSettings(noticeRouting: NoticeRoutingMode.notice),
        ),
      );

      await controller.start();
      transport.emit(
        ':services.example NOTICE AndroidIRCX :Maintenance tonight',
      );
      await Future<void>.delayed(Duration.zero);

      final noticeTab = controller.tabs.firstWhere(
        (tab) => tab.type.name == 'notice',
      );
      controller.selectTab(noticeTab.id);
      expect(
        controller.activeMessages.any(
          (message) => message.content == 'Maintenance tonight',
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('routes incoming notices to the active tab when configured', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(noticeRouting: NoticeRoutingMode.active),
      ),
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':services.example NOTICE AndroidIRCX :Maintenance tonight');
    await Future<void>.delayed(Duration.zero);

    expect(controller.activeTab.name, '#room');
    expect(
      controller.activeMessages.any(
        (message) => message.content == 'Maintenance tonight',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('routes incoming notices to a private query when configured', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(noticeRouting: NoticeRoutingMode.private),
      ),
    );

    await controller.start();
    transport.emit(
      ':NickServ!service@example NOTICE AndroidIRCX :Identify now',
    );
    await Future<void>.delayed(Duration.zero);

    final queryTab = controller.tabs.firstWhere(
      (tab) => tab.type.name == 'query',
    );
    controller.selectTab(queryTab.id);
    expect(queryTab.name, 'NickServ');
    expect(
      controller.activeMessages.any(
        (message) => message.content == 'Identify now',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('uses server-time tag as message timestamp and stores tags', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      '@time=2026-03-17T10:11:12.000Z;+draft/source=test :alice!user@example PRIVMSG #room :hello',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs
          .firstWhere(
            (tab) => tab.type.name == 'channel' && tab.name == '#room',
          )
          .id,
    );
    final message = controller.activeMessages.last;
    expect(
      message.timestamp.toUtc(),
      DateTime.parse('2026-03-17T10:11:12.000Z'),
    );
    expect(message.tags['+draft/source'], 'test');

    controller.dispose();
  });

  test('routes self echo direct messages into the target query tab', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    transport.emit(':server CAP * ACK :echo-message message-tags server-time');
    transport.emit(':AndroidIRCX!me@example PRIVMSG alice :hello from echo');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs
          .firstWhere((tab) => tab.type.name == 'query' && tab.name == 'alice')
          .id,
    );
    expect(
      controller.activeMessages.any(
        (message) =>
            message.isOwn &&
            message.sender == 'AndroidIRCX' &&
            message.content == 'hello from echo',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('filters and exports current tab history', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':alice!user@example PRIVMSG #room :hello flutter');
    transport.emit(':bob!user@example NOTICE #room :system notice');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs
          .firstWhere(
            (tab) => tab.type.name == 'channel' && tab.name == '#room',
          )
          .id,
    );
    final chatOnly = controller.messagesForTab(
      controller.activeTabId,
      query: 'flutter',
      kinds: const <IrcMessageKind>{IrcMessageKind.chat},
    );
    final export = controller.exportTabHistory(
      controller.activeTabId,
      query: 'flutter',
    );

    expect(chatOnly, hasLength(1));
    expect(chatOnly.single.content, 'hello flutter');
    expect(export, contains('hello flutter'));
    expect(export, isNot(contains('system notice')));

    controller.dispose();
  });

  test('stores media urls as structured message attachments', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      ':alice!user@example PRIVMSG #room :Look \u0002https://example.test/manual.pdf\u0002',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs
          .firstWhere(
            (tab) => tab.type.name == 'channel' && tab.name == '#room',
          )
          .id,
    );
    final message = controller.activeMessages.singleWhere(
      (item) => item.content.contains('manual.pdf'),
    );
    final export = controller.exportTabHistory(controller.activeTabId);

    expect(message.kind, IrcMessageKind.media);
    expect(message.attachments.single.type, IrcMessageAttachmentType.file);
    expect(message.attachments.single.uri, 'https://example.test/manual.pdf');
    expect(export, contains('Look https://example.test/manual.pdf'));
    expect(export, isNot(contains('\u0002')));

    controller.dispose();
  });

  test('renders draft intent action as an action message', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      '@draft/intent=ACTION :alice!user@example PRIVMSG #room :waves',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs
          .firstWhere(
            (tab) => tab.type.name == 'channel' && tab.name == '#room',
          )
          .id,
    );
    expect(
      controller.activeMessages.any((message) => message.content == '• waves'),
      isTrue,
    );

    controller.dispose();
  });

  test('deduplicates messages with the same msgid', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      '@msgid=abc123 :alice!user@example PRIVMSG #room :hello once',
    );
    transport.emit(
      '@msgid=abc123 :alice!user@example PRIVMSG #room :hello once',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs
          .firstWhere(
            (tab) => tab.type.name == 'channel' && tab.name == '#room',
          )
          .id,
    );
    expect(
      controller.activeMessages.where(
        (message) => message.content == 'hello once',
      ),
      hasLength(1),
    );

    controller.dispose();
  });

  test('deduplicates persisted msgid after controller restart', () async {
    final firstTransport = _FakeTransport();
    final firstService = IrcService(
      transportConnector: (_) async => firstTransport,
    );
    final firstController = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: firstService,
    );

    await firstController.start();
    firstTransport.emit(
      '@msgid=replay-1 :alice!user@example PRIVMSG #room :from history',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await firstController.flushState();
    firstController.dispose();

    final secondTransport = _FakeTransport();
    final secondService = IrcService(
      transportConnector: (_) async => secondTransport,
    );
    final secondController = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: secondService,
    );

    await secondController.start();
    secondTransport.emit(
      '@batch=hist;msgid=replay-1 :alice!user@example PRIVMSG #room :from history',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final roomTab = secondController.tabs.firstWhere(
      (tab) => tab.type == ChatTabType.channel && tab.name == '#room',
    );
    final messages = secondController.messagesForTab(roomTab.id);

    expect(
      messages.where((message) => message.tags['msgid'] == 'replay-1'),
      hasLength(1),
    );

    secondController.dispose();
  });

  test('tracks batch start and end with message count', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server BATCH +batch-1 chathistory #room');
    transport.emit(
      '@batch=batch-1;msgid=1 :alice!user@example PRIVMSG #room :first history',
    );
    transport.emit(':server BATCH -batch-1');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'server').id,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('BATCH start: chathistory #room'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('Playback batch completed: 1 messages'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'shows playback batch summary and labeled response match in server tab',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':server CAP * ACK :labeled-response');
      await Future<void>.delayed(Duration.zero);
      final label = await service.sendRawLabeled('WHOIS alice alice');
      transport.emit(':server BATCH +batch-2 znc.in/playback #room');
      transport.emit(
        '@batch=batch-2;msgid=2 :alice!user@example PRIVMSG #room :older line',
      );
      transport.emit(':server BATCH -batch-2');
      transport.emit(
        '@label=$label :server 318 AndroidIRCX alice :End of /WHOIS list.',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.type.name == 'server').id,
      );
      expect(
        controller.activeMessages.any(
          (message) =>
              message.content.contains('Playback batch completed: 1 messages'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains(
            'Labeled response matched: WHOIS alice alice',
          ),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('requests chathistory for the active channel when supported', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);

    await controller.handleComposerSubmit('/chathistory 25');

    expect(
      transport.sentLines.any(
        (line) => line.contains('CHATHISTORY LATEST #room * 25'),
      ),
      isTrue,
    );
    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'server').id,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains(
          'Requested CHATHISTORY LATEST for #room (*, 25 messages).',
        ),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('requests chathistory between and targets subcommands', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);

    await controller.handleComposerSubmit('/chathistory between first last 40');
    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type == ChatTabType.server).id,
    );
    await controller.handleComposerSubmit(
      '/chathistory targets 2026-08-20T10:00:00.000Z 2026-08-20T11:00:00.000Z 10',
    );

    expect(
      transport.sentLines.any(
        (line) => line.contains(
          'CHATHISTORY BETWEEN #room msgid=first msgid=last 40',
        ),
      ),
      isTrue,
    );
    expect(
      transport.sentLines.any(
        (line) => line.contains(
          'CHATHISTORY TARGETS timestamp=2026-08-20T10:00:00.000Z timestamp=2026-08-20T11:00:00.000Z 10',
        ),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Requested CHATHISTORY TARGETS'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'uses latest known msgid for /chathistory before when omitted',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit('@msgid=abc123 :alice!user@example PRIVMSG #room :hello');
      transport.emit(':server CAP * ACK :chathistory labeled-response');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      await controller.handleComposerSubmit('/chathistory before 20');

      expect(
        transport.sentLines.any(
          (line) => line.contains('CHATHISTORY BEFORE #room msgid=abc123 20'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('marks playback messages from chathistory batch', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server BATCH +hist chathistory #room');
    transport.emit(
      '@batch=hist;msgid=1 :alice!user@example PRIVMSG #room :older line',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs
          .firstWhere(
            (tab) => tab.type.name == 'channel' && tab.name == '#room',
          )
          .id,
    );
    expect(controller.activeMessages.single.isPlayback, isTrue);

    controller.dispose();
  });

  test(
    'requests recent history for the active tab through controller API',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(':server CAP * ACK :chathistory labeled-response');
      await Future<void>.delayed(Duration.zero);

      expect(await controller.requestRecentHistory(limit: 25), isTrue);
      expect(
        transport.sentLines.any(
          (line) => line.contains('CHATHISTORY LATEST #room * 25'),
        ),
        isTrue,
      );

      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.type.name == 'server').id,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains(
            'Requested recent history for #room (25 messages).',
          ),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test(
    'auto-requests channel history after end of names when supported',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
      transport.emit(':AndroidIRCX!user@example JOIN #room');
      transport.emit(':server 366 AndroidIRCX #room :End of /NAMES list.');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        transport.sentLines
            .where((line) => line.contains('CHATHISTORY LATEST #room * 50'))
            .length,
        1,
      );

      controller.dispose();
    },
  );

  test('auto-history is only requested once per join burst', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server CAP * ACK :chathistory labeled-response');
    transport.emit(':AndroidIRCX!user@example JOIN #room');
    transport.emit(':server 366 AndroidIRCX #room :End of /NAMES list.');
    transport.emit(':server 366 AndroidIRCX #room :End of /NAMES list.');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.sentLines
          .where((line) => line.contains('CHATHISTORY LATEST #room * 50'))
          .length,
      1,
    );

    controller.dispose();
  });

  test(
    'does not auto-request channel history when capability is missing',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':AndroidIRCX!user@example JOIN #room');
      transport.emit(':server 366 AndroidIRCX #room :End of /NAMES list.');
      await Future<void>.delayed(Duration.zero);

      expect(
        transport.sentLines.any(
          (line) => line.contains('CHATHISTORY LATEST #room'),
        ),
        isFalse,
      );

      controller.dispose();
    },
  );

  test(
    'sends read marker when selecting a non-server tab and capability is enabled',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(':server CAP * ACK :draft/read-marker');
      transport.emit(
        '@msgid=msg-1;time=2026-08-20T10:11:12.123Z :alice!user@example PRIVMSG #room :hello',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.name == '#room').id,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        transport.sentLines,
        contains('MARKREAD #room timestamp=2026-08-20T10:11:12.123Z'),
      );

      controller.dispose();
    },
  );

  test(
    'tracks incoming read markers with IRCv3 timestamp and star values',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(
        ':server MARKREAD #room timestamp=2026-08-20T10:11:12.123Z',
      );
      await Future<void>.delayed(Duration.zero);
      final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      controller.selectTab(roomTab.id);

      expect(
        controller.activeReadMarker,
        DateTime.parse('2026-08-20T10:11:12.123Z'),
      );

      transport.emit(':server MARKREAD #room *');
      await Future<void>.delayed(Duration.zero);

      expect(controller.activeReadMarker, isNull);
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('no read marker for #room'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('redacts a message in-place when a REDACT command arrives', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(
      '@msgid=gone-1 :alice!user@example PRIVMSG #room :soon deleted',
    );
    transport.emit(':mod!user@example REDACT #room gone-1');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.name == '#room').id,
    );
    expect(
      controller.activeMessages.any(
        (message) =>
            message.tags['msgid'] == 'gone-1' &&
            message.tags['redacted'] == 'true' &&
            message.content == '[message deleted]',
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('deleted a message'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'sends redact command for message actions when capability is enabled',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(':server CAP * ACK :draft/message-redaction');
      transport.emit(
        '@msgid=del-1 :alice!user@example PRIVMSG #room :delete me',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final targetMessage = controller
          .messagesForTab(
            controller.tabs.firstWhere((tab) => tab.name == '#room').id,
          )
          .firstWhere((message) => message.tags['msgid'] == 'del-1');
      expect(await controller.redactMessage(targetMessage), isTrue);

      expect(transport.sentLines, contains('REDACT #room del-1'));

      controller.dispose();
    },
  );

  test('assembles draft multiline messages into a single chat entry', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(
      '@draft/multiline-concat=batch-1;msgid=multi-1 :alice!user@example PRIVMSG #room :first line',
    );
    transport.emit(
      '@draft/multiline-concat=;msgid=multi-1 :alice!user@example PRIVMSG #room :second line',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.name == '#room').id,
    );
    final assembled = controller.activeMessages.firstWhere(
      (message) => message.tags['msgid'] == 'multi-1',
    );
    expect(assembled.content, 'first line\nsecond line');

    controller.dispose();
  });

  test('tracks incoming typing indicators from TAGMSG', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit('@+typing=active :alice!user@example TAGMSG #room');
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.name == '#room').id,
    );
    expect(controller.activeTypingUsers, contains('alice'));

    transport.emit('@+typing=done :alice!user@example TAGMSG #room');
    await Future<void>.delayed(Duration.zero);
    expect(controller.activeTypingUsers, isEmpty);

    controller.dispose();
  });

  test('records reactions from TAGMSG react tags', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit('@msgid=react-1 :alice!user@example PRIVMSG #room :Hello');
    transport.emit(
      '@+draft/react=react-1\\::thumbsup: :bob!user@example TAGMSG #room',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final message = controller
        .messagesForTab(
          controller.tabs.firstWhere((tab) => tab.name == '#room').id,
        )
        .firstWhere((item) => item.tags['msgid'] == 'react-1');
    expect(
      controller.reactionsForMessage(message),
      containsPair(':thumbsup:', 1),
    );

    controller.dispose();
  });

  test('handles account away host and setname user-state frames', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':alice!user@example ACCOUNT aliceAccount');
    transport.emit(':alice!user@example AWAY :be right back');
    transport.emit(':alice!ident@example CHGHOST ident new.host.example');
    transport.emit(':alice!ident@example SETNAME :Alice Realname');
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'server').id,
    );
    expect(
      controller.activeMessages.any(
        (m) => m.content.contains('logged in as aliceAccount'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (m) => m.content.contains('is now away: be right back'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (m) => m.content.contains('changed host to new.host.example'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (m) => m.content.contains('changed realname to: Alice Realname'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'supports setname command from composer when capability is enabled',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':server CAP * ACK :setname');
      await Future<void>.delayed(Duration.zero);

      await controller.handleComposerSubmit('/setname AndroidIRCx Flutter');

      expect(transport.sentLines, contains('SETNAME :AndroidIRCx Flutter'));
      controller.dispose();
    },
  );

  test('formats DCC CTCP requests into readable system messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC SEND "movie.mkv" 127001 5000 42\u0001',
    );
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type == ChatTabType.dcc).id,
    );
    expect(
      controller.activeMessages.any(
        (m) => m.content.contains('DCC SEND offer from alice: movie.mkv'),
      ),
      isTrue,
    );
    final message = controller.activeMessages.firstWhere(
      (m) => m.content.contains('DCC SEND offer from alice: movie.mkv'),
    );
    expect(message.kind, IrcMessageKind.dcc);
    expect(message.attachments.single.type, IrcMessageAttachmentType.dccSend);
    expect(message.attachments.single.fileName, 'movie.mkv');
    expect(message.attachments.single.peerNick, 'alice');

    controller.dispose();
  });

  test('creates a dedicated DCC tab for incoming offers', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final dccBackend = _FakeDccBackend();
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      dccService: DccService(backend: dccBackend),
    );

    await controller.start();
    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC CHAT chat 127001 5001\u0001',
    );
    await Future<void>.delayed(Duration.zero);

    final dccTab = controller.tabs.firstWhere(
      (tab) => tab.type == ChatTabType.dcc,
    );
    expect(dccTab.name, 'DCC CHAT alice');
    controller.selectTab(dccTab.id);
    expect(
      controller.activeMessages.any(
        (m) => m.content.contains('DCC CHAT request from alice'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('accepting dcc chat enables local dcc chat composer flow', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final dccBackend = _FakeDccBackend();
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      dccService: DccService(backend: dccBackend),
    );

    await controller.start();
    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC CHAT chat 127001 5001\u0001',
    );
    await Future<void>.delayed(Duration.zero);

    final dccTab = controller.tabs.firstWhere(
      (tab) => tab.type == ChatTabType.dcc,
    );
    controller.selectTab(dccTab.id);
    await controller.acceptActiveDccSession();
    await controller.handleComposerSubmit('Hello over DCC');

    expect(
      controller.activeMessages.any(
        (m) => m.content == 'Hello over DCC' && m.isOwn,
      ),
      isTrue,
    );
    expect(
      transport.sentLines.any((line) => line.contains('PRIVMSG DCC CHAT')),
      isFalse,
    );

    controller.dispose();
  });

  test('dcc send tabs reject composer messages with a clear error', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC SEND "movie.mkv" 127001 5000 42\u0001',
    );
    await Future<void>.delayed(Duration.zero);

    final dccTab = controller.tabs.firstWhere(
      (tab) => tab.type == ChatTabType.dcc,
    );
    controller.selectTab(dccTab.id);
    await controller.handleComposerSubmit('this should fail');

    expect(
      controller.activeMessages.any(
        (m) => m.content.contains('DCC SEND tabs do not support chat messages'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('accepts incoming dcc send and records transfer completion', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final dccBackend = _FakeDccBackend();
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      dccService: DccService(backend: dccBackend),
    );

    await controller.start();
    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC SEND "movie.mkv" 127001 5000 42\u0001',
    );
    await Future<void>.delayed(Duration.zero);

    final dccTab = controller.tabs.firstWhere(
      (tab) => tab.type == ChatTabType.dcc,
    );
    controller.selectTab(dccTab.id);
    await controller.acceptActiveDccSession();
    dccBackend.connection.emitBytes([1, 2, 3, 4]);
    await Future<void>.delayed(Duration.zero);
    await dccBackend.connection.finish();
    // Wait for the transfer to fully settle (status + file write + log line).
    // A short fixed poll was flaky on slow CI runners, so wait up to ~3s for
    // the actual completion condition instead of a handful of 1ms ticks.
    for (var i = 0; i < 300; i += 1) {
      final session = controller.activeDccSession;
      final finished = controller.activeMessages.any(
        (message) => message.content.contains('DCC SEND finished'),
      );
      if (session?.status == DccSessionStatus.closed &&
          session?.bytesTransferred == 4 &&
          finished) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('DCC SEND accept requested'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('DCC SEND finished'),
      ),
      isTrue,
    );
    expect(controller.activeDccSession!.bytesTransferred, 4);

    final filePath = controller.activeDccSession!.filePath;
    if (filePath != null) {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    controller.dispose();
  });

  test('accepts reverse dcc send by replying with listener details', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final dccBackend = _FakeDccBackend();
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      dccService: DccService(backend: dccBackend),
    );

    await controller.start();
    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC SEND "reverse.bin" 127001 0 42 abc123\u0001',
    );
    await Future<void>.delayed(Duration.zero);

    final dccTab = controller.tabs.firstWhere(
      (tab) => tab.type == ChatTabType.dcc,
    );
    controller.selectTab(dccTab.id);
    await controller.acceptActiveDccSession();
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.sentLines.any(
        (line) =>
            line.startsWith('PRIVMSG alice :\u0001DCC SEND "reverse.bin" ') &&
            line.endsWith(' 42 abc123\u0001'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('Reverse DCC SEND accept requested'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('not implemented'),
      ),
      isFalse,
    );

    controller.dispose();
  });

  test(
    'starts outgoing dcc chat offers and sends ctcp payload to target nick',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final dccBackend = _FakeDccBackend();
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
        dccService: DccService(backend: dccBackend),
      );

      await controller.start();
      await controller.handleComposerSubmit('/dccchat alice');
      await Future<void>.delayed(Duration.zero);

      final dccTab = controller.tabs.firstWhere(
        (tab) => tab.type == ChatTabType.dcc,
      );
      controller.selectTab(dccTab.id);

      expect(dccTab.name, 'DCC CHAT alice');
      expect(
        transport.sentLines.any(
          (line) => line.startsWith('PRIVMSG alice :\u0001DCC CHAT chat '),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('Offering DCC CHAT to alice'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test(
    'starts outgoing dcc send offers and sends ctcp payload to target nick',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final dccBackend = _FakeDccBackend();
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
        dccService: DccService(backend: dccBackend),
      );
      final file = File.fromUri(
        Directory.systemTemp.uri.resolve('androidircx-dcc-test.txt'),
      );
      await file.writeAsString('hello dcc');

      await controller.start();
      await controller.handleComposerSubmit('/dccsend alice ${file.path}');
      await Future<void>.delayed(Duration.zero);

      final dccTab = controller.tabs.firstWhere(
        (tab) => tab.type == ChatTabType.dcc,
      );
      controller.selectTab(dccTab.id);

      expect(dccTab.name, 'DCC SEND alice');
      expect(
        transport.sentLines.any(
          (line) => line.startsWith(
            'PRIVMSG alice :\u0001DCC SEND "androidircx-dcc-test.txt" ',
          ),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('Offering DCC SEND to alice'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('starts outgoing dcc send offers from selected file paths', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final dccBackend = _FakeDccBackend();
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      dccService: DccService(backend: dccBackend),
    );
    final file = File.fromUri(
      Directory.systemTemp.uri.resolve('androidircx-dcc-picker-test.txt'),
    );
    await file.writeAsString('picked file');

    await controller.start();
    await controller.sendDccFileToNick(nick: 'alice', filePath: file.path);
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.sentLines.any(
        (line) => line.startsWith(
          'PRIVMSG alice :\u0001DCC SEND "androidircx-dcc-picker-test.txt" ',
        ),
      ),
      isTrue,
    );
    expect(
      controller.tabs.any(
        (tab) => tab.type == ChatTabType.dcc && tab.name == 'DCC SEND alice',
      ),
      isTrue,
    );

    for (var attempt = 0; attempt < 20; attempt += 1) {
      if (controller.dccSessions.any(
        (session) => session.status == DccSessionStatus.closed,
      )) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    controller.dispose();
    await file.delete();
  });

  test(
    'routes invite kick and extended whois numerics into chat state',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(':server 341 AndroidIRCX bob #room');
      transport.emit(':carol!user@example INVITE AndroidIRCX :#room');
      transport.emit(':alice!user@example JOIN :#room');
      transport.emit(':carol!user@example KICK #room alice :cleanup');
      transport.emit(':server 301 AndroidIRCX bob :is away');
      transport.emit(
        ':server 671 AndroidIRCX bob :is using a secure connection',
      );
      transport.emit(':server 328 AndroidIRCX #room :https://example.com/room');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      controller.selectTab(roomTab.id);

      expect(
        controller.activeMessages.any(
          (message) =>
              message.content.contains('Invitation sent to bob for #room'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('carol invited you to #room'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) =>
              message.content.contains('alice was kicked from #room by carol'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) =>
              message.content.contains('Channel URL: https://example.com/room'),
        ),
        isTrue,
      );
      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.name == 'bob').id,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('WHOIS away: bob is away'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('secure connection'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('sends monitor ison and userhost commands from composer', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/monitor + alice,bob');
    await controller.handleComposerSubmit('/ison alice bob');
    await controller.handleComposerSubmit('/userhost alice bob');

    expect(transport.sentLines, contains('MONITOR + alice,bob'));
    expect(transport.sentLines, contains('ISON alice bob'));
    expect(transport.sentLines, contains('USERHOST alice bob'));

    controller.dispose();
  });

  test(
    'routes monitor ison and userhost numerics into server messages',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':server 303 AndroidIRCX :alice bob');
      transport.emit(':server 302 AndroidIRCX :alice=+user@host');
      transport.emit(':server 730 AndroidIRCX :alice,bob');
      transport.emit(':server 731 AndroidIRCX :carol');
      transport.emit(':server 732 AndroidIRCX :alice,bob');
      transport.emit(':server 733 AndroidIRCX :End of MONITOR list');
      transport.emit(':server 734 AndroidIRCX :Monitor list is full');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('ISON online: alice bob'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('USERHOST: alice=+user@host'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('MONITOR online: alice, bob'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('MONITOR offline: carol'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('MONITOR list: alice,bob'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('Monitor list is full'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('cycles tabs with selectNextTab/selectPreviousTab', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':a!u@h PRIVMSG #one :hi');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':b!u@h PRIVMSG #two :hi');
    await Future<void>.delayed(Duration.zero);

    final serverTab =
        controller.tabs.firstWhere((tab) => tab.type == ChatTabType.server);
    controller.selectTab(serverTab.id);
    final startId = controller.activeTabId;

    controller.selectNextTab();
    expect(controller.activeTabId, isNot(startId));
    controller.selectPreviousTab();
    expect(controller.activeTabId, startId);

    controller.dispose();
  });

  test('measures server lag from PING/PONG', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    await Future<void>.delayed(Duration.zero);
    await controller.measureLag();
    final pingLine =
        transport.sentLines.lastWhere((line) => line.startsWith('PING :LAG'));
    final token = pingLine.substring('PING :'.length);
    transport.emit(':server PONG server :$token');
    await Future<void>.delayed(Duration.zero);

    expect(controller.lag, isNotNull);
    expect(controller.lag!.inMilliseconds >= 0, isTrue);

    controller.dispose();
  });

  test('auto-rejoins a channel after being kicked', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(autoRejoinOnKick: true),
      ),
    );

    await controller.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':op!o@host KICK #room AndroidIRCX :seeya');
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('JOIN #room'));

    controller.dispose();
  });

  test('collects the server channel list from LIST numerics', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.requestChannelList();
    expect(transport.sentLines, contains('LIST'));
    transport.emit(':server 321 AndroidIRCX Channel :Users Name');
    transport.emit(':server 322 AndroidIRCX #dbase 42 :Main channel');
    transport.emit(':server 322 AndroidIRCX #flutter 7 :Dart & Flutter');
    transport.emit(':server 323 AndroidIRCX :End of /LIST');
    await Future<void>.delayed(Duration.zero);

    expect(controller.channelListing.map((entry) => entry.name),
        containsAll(<String>['#dbase', '#flutter']));
    final dbase =
        controller.channelListing.firstWhere((entry) => entry.name == '#dbase');
    expect(dbase.userCount, 42);
    expect(dbase.topic, 'Main channel');
    expect(controller.channelListInProgress, isFalse);

    controller.dispose();
  });

  test('highlights channel messages containing highlight words', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(
          highlightWords: ['flutter'],
          notificationsEnabled: true,
        ),
      ),
    );

    final received = <ForegroundUserNotification>[];
    final sub = controller.notifications.listen(received.add);
    await controller.start();
    transport.emit(':alice!u@h PRIVMSG #room :I really love flutter dev');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      received.any(
        (n) => n.channelKind == ForegroundNotificationChannelKind.highlights,
      ),
      isTrue,
    );

    await sub.cancel();
    controller.dispose();
  });

  test('suppresses notifications disabled in settings', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(
          notifyPrivateMessages: false,
          notificationsEnabled: true,
        ),
      ),
    );

    final received = <ForegroundUserNotification>[];
    final sub = controller.notifications.listen(received.add);
    await controller.start();
    transport.emit(':alice!u@h PRIVMSG AndroidIRCX :hey there');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      received.where(
        (n) => n.channelKind == ForegroundNotificationChannelKind.queries,
      ),
      isEmpty,
    );
    // The message is still delivered to the query tab, just not notified.
    expect(
      controller.tabs.any((tab) => tab.name == 'alice'),
      isTrue,
    );

    await sub.cancel();
    controller.dispose();
  });

  test('routes incoming notices to the server tab when configured', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final settingsRepository = _FakeSettingsRepository(
      const AppSettings(noticeRouting: NoticeRoutingMode.server),
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      settingsRepository: settingsRepository,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':alice!user@example NOTICE #room :server-routed');
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type == ChatTabType.server).id,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('server-routed'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'enriches channel nick details from extended-join, names and user-state updates',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(
        ':alice!ident@example JOIN #room aliceAccount :Alice Example',
      );
      transport.emit(':server 353 AndroidIRCX = #room :@alice!ident@example');
      transport.emit(':alice!ident@example AWAY :coffee');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      controller.selectTab(roomTab.id);
      final entry = controller.activeChannelUserDetails.firstWhere(
        (item) => item.nick == 'alice',
      );
      expect(entry.details, contains('account: aliceAccount'));
      expect(entry.details, contains('realname: Alice Example'));
      expect(entry.details, contains('ident@example'));
      expect(entry.details, contains('away: coffee'));

      controller.dispose();
    },
  );

  test(
    'uses account-tag and channel-context tags to update state and route messages',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(
        '@account=aliceAccount;+draft/channel-context=#room :alice!ident@example PRIVMSG AndroidIRCX :context hello',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      controller.selectTab(roomTab.id);
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('context hello'),
        ),
        isTrue,
      );
      final entry = controller.activeChannelUserDetails.firstWhere(
        (item) => item.nick == 'alice',
      );
      expect(entry.details, contains('account: aliceAccount'));
      expect(entry.details, contains('ident@example'));

      controller.dispose();
    },
  );

  test(
    'tracks dcc resume and accept control requests on matching send tabs',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final dccBackend = _FakeDccBackend();
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
        dccService: DccService(backend: dccBackend),
      );
      final file = File.fromUri(
        Directory.systemTemp.uri.resolve('androidircx-dcc-resume-test.txt'),
      );
      await file.writeAsString('resume me');

      await controller.start();
      await controller.handleComposerSubmit('/dccsend alice ${file.path}');
      await Future<void>.delayed(Duration.zero);

      final dccTab = controller.tabs.firstWhere(
        (tab) => tab.type == ChatTabType.dcc,
      );
      controller.selectTab(dccTab.id);
      transport.emit(
        ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC RESUME "androidircx-dcc-resume-test.txt" 5001 2048\u0001',
      );
      transport.emit(
        ':alice!user@example PRIVMSG AndroidIRCX :\u0001DCC ACCEPT "androidircx-dcc-resume-test.txt" 5001 2048\u0001',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('requested DCC RESUME'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('acknowledged DCC RESUME'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test(
    'sends dcc resume and accept control commands from active send tab',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final dccBackend = _FakeDccBackend();
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
        dccService: DccService(backend: dccBackend),
      );
      final file = File.fromUri(
        Directory.systemTemp.uri.resolve('androidircx-dcc-resume-command.txt'),
      );
      await file.writeAsString('resume command');

      await controller.start();
      await controller.handleComposerSubmit('/dccsend alice ${file.path}');
      await Future<void>.delayed(Duration.zero);

      final dccTab = controller.tabs.firstWhere(
        (tab) => tab.type == ChatTabType.dcc,
      );
      controller.selectTab(dccTab.id);
      await controller.handleComposerSubmit('/dccresume 512');
      await controller.handleComposerSubmit('/dccaccept 512');

      expect(
        transport.sentLines,
        contains(
          'PRIVMSG alice :\u0001DCC RESUME "androidircx-dcc-resume-command.txt" 5001 512\u0001',
        ),
      );
      expect(
        transport.sentLines,
        contains(
          'PRIVMSG alice :\u0001DCC ACCEPT "androidircx-dcc-resume-command.txt" 5001 512\u0001',
        ),
      );

      controller.dispose();
    },
  );

  test('requests older history using the oldest known msgid anchor', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit('@msgid=first-1 :alice!user@example PRIVMSG #room :older');
    transport.emit('@msgid=last-1 :bob!user@example PRIVMSG #room :newer');
    transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.requestOlderHistory(limit: 40), isTrue);
    expect(
      transport.sentLines.any(
        (line) => line.contains('CHATHISTORY BEFORE #room msgid=first-1 40'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'reports missing history anchor when requesting older history too early',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(':server CAP * ACK :chathistory labeled-response');
      await Future<void>.delayed(Duration.zero);

      expect(await controller.requestOlderHistory(limit: 50), isFalse);
      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.type.name == 'server').id,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains(
            'No history anchor is available yet for #room.',
          ),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('requests newer history using the latest known msgid anchor', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit('@msgid=first-1 :alice!user@example PRIVMSG #room :older');
    transport.emit('@msgid=last-1 :bob!user@example PRIVMSG #room :newer');
    transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.requestNewerHistory(limit: 40), isTrue);
    expect(
      transport.sentLines.any(
        (line) => line.contains('CHATHISTORY AFTER #room msgid=last-1 40'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'requests surrounding history around the latest known msgid anchor',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit('@msgid=mid-1 :alice!user@example PRIVMSG #room :hello');
      transport.emit(':server CAP * ACK :chathistory labeled-response');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(await controller.requestAroundLatestHistory(limit: 30), isTrue);
      expect(
        transport.sentLines.any(
          (line) => line.contains('CHATHISTORY AROUND #room msgid=mid-1 30'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test(
    'reports missing recent anchor when requesting newer history too early',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(':server CAP * ACK :chathistory labeled-response');
      await Future<void>.delayed(Duration.zero);

      expect(await controller.requestNewerHistory(limit: 50), isFalse);
      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.type.name == 'server').id,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains(
            'No recent history anchor is available yet for #room.',
          ),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test(
    'shows unsupported chathistory error when capability is missing',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      await controller.handleComposerSubmit('/chathistory');

      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.type.name == 'server').id,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains(
            'CHATHISTORY is not supported by this server.',
          ),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('routes CTCP requests and sends CTCP replies', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      ':alice!user@example PRIVMSG AndroidIRCX :\u0001VERSION\u0001',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.sentLines,
      contains('NOTICE alice :\u0001VERSION AndroidIRCx Flutter 1.0.0\u0001'),
    );
    controller.selectTab(
      controller.tabs
          .firstWhere((tab) => tab.type.name == 'query' && tab.name == 'alice')
          .id,
    );
    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('CTCP VERSION request from alice'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('auto-replies to the full CTCP command set over NOTICE', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();

    Future<void> emitCtcp(String body) async {
      transport.emit(
        ':alice!user@example PRIVMSG AndroidIRCX :$body',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    await emitCtcp('PING 999');
    await emitCtcp('CLIENTINFO');
    await emitCtcp('USERINFO');
    await emitCtcp('SOURCE');
    await emitCtcp('FINGER');
    await emitCtcp('TIME');

    // Every CTCP reply must go out as a NOTICE (never PRIVMSG) so it cannot
    // trigger a reply loop, and PING must echo the requester's token back.
    expect(
      transport.sentLines,
      contains('NOTICE alice :PING 999'),
    );
    expect(
      transport.sentLines,
      contains(
        'NOTICE alice :CLIENTINFO ACTION CLIENTINFO DCC FINGER PING '
        'SOURCE TIME USERINFO VERSION',
      ),
    );
    expect(
      transport.sentLines,
      contains('NOTICE alice :USERINFO AndroidIRCx Flutter user'),
    );
    expect(
      transport.sentLines,
      contains(
        'NOTICE alice :SOURCE '
        'https://github.com/AndroidIRCx/AndroidIRCx-Flutter',
      ),
    );
    expect(
      transport.sentLines,
      contains('NOTICE alice :FINGER AndroidIRCx Flutter'),
    );
    expect(
      transport.sentLines.any(
        (line) => line.startsWith('NOTICE alice :TIME ') &&
            line.endsWith(''),
      ),
      isTrue,
    );
    // A CTCP request must never be answered with a PRIVMSG.
    expect(
      transport.sentLines.any((line) => line.startsWith('PRIVMSG alice :')),
      isFalse,
    );

    controller.dispose();
  });

  test('echoes a local-only message into the active tab', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/echo hello world');

    expect(
      controller.activeMessages.any((message) => message.content == 'hello world'),
      isTrue,
    );
    // /echo must never hit the wire.
    expect(
      transport.sentLines.any((line) => line.contains('hello world')),
      isFalse,
    );

    controller.dispose();
  });

  test('shows usage for a known command via /help', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/help join');

    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('Help /join') &&
            message.content.contains('/join <channel>'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('sends /amsg and /ame to every joined channel', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':alice!user@example PRIVMSG #room :hi');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':bob!user@example PRIVMSG #other :hi');
    await Future<void>.delayed(Duration.zero);

    await controller.handleComposerSubmit('/amsg hello all');
    await controller.handleComposerSubmit('/ame waves');

    expect(transport.sentLines, contains('PRIVMSG #room :hello all'));
    expect(transport.sentLines, contains('PRIVMSG #other :hello all'));
    expect(
      transport.sentLines,
      contains('PRIVMSG #room :ACTION waves'),
    );
    expect(
      transport.sentLines,
      contains('PRIVMSG #other :ACTION waves'),
    );

    controller.dispose();
  });

  test('drops messages from ignored senders until unignored', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':spammer!x@evil.example PRIVMSG #room :before');
    await Future<void>.delayed(Duration.zero);

    await controller.handleComposerSubmit('/ignore spammer');
    transport.emit(':spammer!x@evil.example PRIVMSG #room :after');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':alice!user@host PRIVMSG #room :hi');
    await Future<void>.delayed(Duration.zero);

    final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
    controller.selectTab(roomTab.id);
    final contents =
        controller.activeMessages.map((message) => message.content).toList();
    expect(contents, contains('before'));
    expect(contents, isNot(contains('after')));
    expect(contents, contains('hi'));

    await controller.handleComposerSubmit('/unignore spammer');
    transport.emit(':spammer!x@evil.example PRIVMSG #room :again');
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(roomTab.id);
    expect(
      controller.activeMessages.any((message) => message.content == 'again'),
      isTrue,
    );

    controller.dispose();
  });

  test('ignores by host mask with wildcards', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/ignore *!*@evil.example');
    transport.emit(':troll!bar@evil.example PRIVMSG #room :spam');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':alice!user@good.example PRIVMSG #room :welcome');
    await Future<void>.delayed(Duration.zero);

    final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
    controller.selectTab(roomTab.id);
    final contents =
        controller.activeMessages.map((message) => message.content).toList();
    expect(contents, isNot(contains('spam')));
    expect(contents, contains('welcome'));

    controller.dispose();
  });

  test('resolves a known nick host via /dns', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':alice!user@host.example PRIVMSG #room :hi');
    await Future<void>.delayed(Duration.zero);
    await controller.handleComposerSubmit('/dns alice');

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('alice resolves to host.example'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('detects clones sharing a host via /clones', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':bob!x@shared.example PRIVMSG #room :hi');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':carol!y@shared.example PRIVMSG #room :yo');
    await Future<void>.delayed(Duration.zero);
    await controller.handleComposerSubmit('/clones #room');

    final contents =
        controller.activeMessages.map((message) => message.content).join('\n');
    expect(contents, contains('Clones detected in #room'));
    expect(contents, contains('shared.example'));
    expect(contents.contains('bob') && contents.contains('carol'), isTrue);

    controller.dispose();
  });

  test('announces reconnect from /reconnect', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/reconnect');

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Reconnecting to DBase'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('performs channel user actions through existing command paths', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':alice!user@example PRIVMSG #room :hi');
    await Future<void>.delayed(Duration.zero);
    final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
    controller.selectTab(roomTab.id);

    await controller.performChannelUserAction('alice', ChannelUserAction.op);
    await controller.performChannelUserAction('alice', ChannelUserAction.voice);
    await controller.performChannelUserAction('@alice', ChannelUserAction.kick);
    await controller.performChannelUserAction('alice', ChannelUserAction.ban);
    await controller.performChannelUserAction('alice', ChannelUserAction.whois);
    await controller.performChannelUserAction('alice', ChannelUserAction.query);

    expect(transport.sentLines, contains('MODE #room +o alice'));
    expect(transport.sentLines, contains('MODE #room +v alice'));
    expect(
      transport.sentLines.any((line) => line.startsWith('KICK #room alice')),
      isTrue,
    );
    expect(transport.sentLines, contains('MODE #room +b alice'));
    expect(
      transport.sentLines.any((line) => line.startsWith('WHOIS alice')),
      isTrue,
    );
    expect(
      controller.tabs.any(
        (tab) => tab.type.name == 'query' && tab.name == 'alice',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('announces bouncer compatibility on registration', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'znc',
        name: 'ZNC',
        host: 'znc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('Bouncer:') &&
            message.content.contains('ZNC'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('hides messages matching an active /filter', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':alice!u@h PRIVMSG #room :hello spam word');
    await Future<void>.delayed(Duration.zero);
    await controller.handleComposerSubmit('/filter spam');
    transport.emit(':alice!u@h PRIVMSG #room :another spam here');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':alice!u@h PRIVMSG #room :clean message');
    await Future<void>.delayed(Duration.zero);

    final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
    controller.selectTab(roomTab.id);
    final contents =
        controller.activeMessages.map((message) => message.content).toList();
    expect(contents, contains('hello spam word'));
    expect(contents, isNot(contains('another spam here')));
    expect(contents, contains('clean message'));

    controller.dispose();
  });

  test('opens and activates windows via /window', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':alice!u@h PRIVMSG #room :hi');
    await Future<void>.delayed(Duration.zero);

    await controller.handleComposerSubmit('/window bob');
    expect(controller.activeTab.name, 'bob');
    expect(controller.activeTab.type.name, 'query');

    await controller.handleComposerSubmit('/window -a #room');
    expect(controller.activeTab.name, '#room');

    controller.dispose();
  });

  test('runs a command after a delay via /timer', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/timer greet 20 1 /echo tick');
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(
      controller.activeMessages.any((message) => message.content == 'tick'),
      isTrue,
    );

    // A long timer is cancelled by /timer <name> off before it can ever fire,
    // so nothing leaks into later tests.
    await controller.handleComposerSubmit('/timer loop 3600000 1 /echo never');
    await controller.handleComposerSubmit('/timer loop off');
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Timer "loop" cancelled'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('mirrors appended messages into the history repository', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final history = InMemoryMessageHistoryRepository();
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
      historyRepository: history,
    );

    await controller.start();
    transport.emit(':alice!u@h PRIVMSG #room :hello history');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
    final stored = await history.loadTabHistory(
      networkId: 'dbase',
      tabId: roomTab.id,
    );
    expect(
      stored.any((message) => message.content == 'hello history'),
      isTrue,
    );

    controller.dispose();
  });

  test('restores tab history from the repository on restart', () async {
    SharedPreferences.setMockInitialValues({});
    final history = InMemoryMessageHistoryRepository();
    const config = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.example.test',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    final transport1 = _FakeTransport();
    final service1 = IrcService(transportConnector: (_) async => transport1);
    final controller1 = ChatSessionController(
      network: config,
      ircService: service1,
      historyRepository: history,
    );
    await controller1.start();
    transport1.emit(':alice!u@h PRIVMSG #room :first message');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    transport1.emit(':bob!u@h PRIVMSG #room :second message');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await controller1.flushState();
    controller1.dispose();

    final transport2 = _FakeTransport();
    final service2 = IrcService(transportConnector: (_) async => transport2);
    final controller2 = ChatSessionController(
      network: config,
      ircService: service2,
      historyRepository: history,
    );
    await controller2.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final roomTab = controller2.tabs.firstWhere((tab) => tab.name == '#room');
    controller2.selectTab(roomTab.id);
    final contents =
        controller2.activeMessages.map((message) => message.content).toList();
    expect(contents, contains('first message'));
    expect(contents, contains('second message'));

    controller2.dispose();
  });

  test('routes CTCP replies into the matching query tab', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      ':alice!user@example NOTICE AndroidIRCX :\u0001PING 12345\u0001',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs
          .firstWhere((tab) => tab.type.name == 'query' && tab.name == 'alice')
          .id,
    );
    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('CTCP PING reply from alice: 12345'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('sends CTCP commands from the composer', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/ctcp alice ping 999');

    expect(
      transport.sentLines,
      contains('PRIVMSG alice :\u0001PING 999\u0001'),
    );
    expect(controller.activeTab.name, 'alice');
    expect(
      controller.activeMessages.any(
        (message) => message.content == 'Sent CTCP PING: 999',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('handles CAP commands from the composer', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/cap ls');
    await controller.handleComposerSubmit('/cap req message-tags echo-message');
    await controller.handleComposerSubmit('/cap end');

    expect(transport.sentLines, contains('CAP LS 302'));
    expect(transport.sentLines, contains('CAP REQ :message-tags echo-message'));
    expect(transport.sentLines, contains('CAP END'));
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains(
          'Requested capabilities: message-tags echo-message',
        ),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Ended capability negotiation'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'shows capability status and CAP frame updates in server messages',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
          saslAccount: 'alice',
          saslPassword: 'secret',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':server CAP * LS :multi-prefix sasl message-tags');
      await Future<void>.delayed(Duration.zero);
      transport.emit(':server CAP * ACK :sasl message-tags');
      await Future<void>.delayed(Duration.zero);
      await controller.handleComposerSubmit('/cap status');

      expect(
        controller.activeMessages.any(
          (message) => message.content.contains(
            'CAP LS: multi-prefix sasl message-tags',
          ),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('CAP ACK: sasl message-tags'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('Available capabilities:'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('Enabled capabilities:'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('handles away and back commands from the composer', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/away Grabbing coffee');
    await controller.handleComposerSubmit('/back');

    expect(transport.sentLines, contains('AWAY :Grabbing coffee'));
    expect(transport.sentLines, contains('AWAY'));
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Away: Grabbing coffee'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.where(
        (message) => message.content == 'Away status cleared.',
      ),
      isNotEmpty,
    );

    controller.dispose();
  });

  test('handles list command and channel list numerics', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/list #android*');
    transport.emit(':server 321 AndroidIRCX Channel :Users Name');
    transport.emit(
      ':server 322 AndroidIRCX #androidircx 42 :AndroidIRCx official channel',
    );
    transport.emit(':server 323 AndroidIRCX :End of /LIST');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('LIST #android*'));
    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('Requested channel list for: #android*'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Channel list started.'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains(
          '#androidircx (42 users) - AndroidIRCx official channel',
        ),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('End of /LIST'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('handles server info commands and numerics', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/motd');
    await controller.handleComposerSubmit('/time');
    await controller.handleComposerSubmit('/version irc.example.test');
    await controller.handleComposerSubmit('/links *.example.test');

    transport.emit(':server 371 AndroidIRCX :- Welcome to the network');
    transport.emit(':server 374 AndroidIRCX :End of /INFO list');
    transport.emit(
      ':server 391 AndroidIRCX irc.example.test :2026-03-16 20:15:00',
    );
    transport.emit(
      ':server 351 AndroidIRCX ircd-seven-1.1 example.test :server version info',
    );
    transport.emit(':server 364 AndroidIRCX hub.example.test 1 :Example hub');
    transport.emit(':server 365 AndroidIRCX :End of /LINKS list');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('MOTD'));
    expect(transport.sentLines, contains('TIME'));
    expect(transport.sentLines, contains('VERSION irc.example.test'));
    expect(transport.sentLines, contains('LINKS *.example.test'));

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Requested MOTD.'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Welcome to the network'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('2026-03-16 20:15:00'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Server version:'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains(
          'Link: hub.example.test (1) - Example hub',
        ),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('End of /LINKS list'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('sends extended registered raw commands from composer', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(
      const JoinChannelRequest(channel: '#androidircx'),
    );
    await controller.handleComposerSubmit('/lusers');
    await controller.handleComposerSubmit('/knock #secret please');
    await controller.handleComposerSubmit('/oper opername secret');
    await controller.handleComposerSubmit('/watch +Alice');
    await controller.handleComposerSubmit('/cnotice Alice #androidircx hi');
    await controller.handleComposerSubmit('/squery NickServ identify secret');
    await controller.handleComposerSubmit('/wallops ops online');
    await controller.handleComposerSubmit('/kickban BadUser flooding');
    await controller.handleComposerSubmit('/oper onlyname');

    expect(transport.sentLines, contains('LUSERS'));
    expect(transport.sentLines, contains('KNOCK #secret :please'));
    expect(transport.sentLines, contains('OPER opername secret'));
    expect(transport.sentLines, contains('WATCH +Alice'));
    expect(transport.sentLines, contains('CNOTICE Alice #androidircx :hi'));
    expect(transport.sentLines, contains('PRIVMSG NickServ :identify secret'));
    expect(transport.sentLines, contains('WALLOPS :ops online'));
    expect(transport.sentLines, contains('MODE #androidircx +b BadUser!*@*'));
    expect(
      transport.sentLines,
      contains('KICK #androidircx BadUser :flooding'),
    );

    final serverTab = controller.tabs.firstWhere(
      (tab) => tab.type == ChatTabType.server,
    );
    expect(
      controller
          .messagesForTab(serverTab.id)
          .any((message) => message.content.contains('Usage: /oper')),
      isTrue,
    );

    controller.dispose();
  });

  test('handles channel admin commands and ban list numerics', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(
      const JoinChannelRequest(channel: '#androidircx'),
    );
    await controller.handleComposerSubmit('/op Alice');
    await controller.handleComposerSubmit('/deop Alice');
    await controller.handleComposerSubmit('/voice Bob');
    await controller.handleComposerSubmit('/devoice Bob');
    await controller.handleComposerSubmit('/ban bad!*@*');
    await controller.handleComposerSubmit('/unban bad!*@*');
    await controller.handleComposerSubmit('/banlist');

    transport.emit(
      ':server 367 AndroidIRCX #androidircx bad!*@* ChanOp 1710000000',
    );
    transport.emit(
      ':server 368 AndroidIRCX #androidircx :End of channel ban list',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('MODE #androidircx +o Alice'));
    expect(transport.sentLines, contains('MODE #androidircx -o Alice'));
    expect(transport.sentLines, contains('MODE #androidircx +v Bob'));
    expect(transport.sentLines, contains('MODE #androidircx -v Bob'));
    expect(transport.sentLines, contains('MODE #androidircx +b bad!*@*'));
    expect(transport.sentLines, contains('MODE #androidircx -b bad!*@*'));
    expect(transport.sentLines, contains('MODE #androidircx +b'));

    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('Requested ban list for #androidircx'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Ban: bad!*@* set by ChanOp'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('End of channel ban list'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('handles invite exception exception and quiet list numerics', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(
      const JoinChannelRequest(channel: '#androidircx'),
    );
    await controller.handleComposerSubmit('/invitelist');
    await controller.handleComposerSubmit('/exceptlist');
    await controller.handleComposerSubmit('/quietlist');

    transport.emit(
      ':server 346 AndroidIRCX #androidircx invite!*@* ChanOp 1710000000',
    );
    transport.emit(
      ':server 347 AndroidIRCX #androidircx :End of channel invite exception list',
    );
    transport.emit(
      ':server 348 AndroidIRCX #androidircx except!*@* ChanOp 1710000000',
    );
    transport.emit(
      ':server 349 AndroidIRCX #androidircx :End of channel exception list',
    );
    transport.emit(
      ':server 728 AndroidIRCX #androidircx quiet!*@* ChanOp 1710000000',
    );
    transport.emit(
      ':server 729 AndroidIRCX #androidircx :End of channel quiet list',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('MODE #androidircx +I'));
    expect(transport.sentLines, contains('MODE #androidircx +e'));
    expect(transport.sentLines, contains('MODE #androidircx +q'));

    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('Requested invite list for #androidircx'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains(
          'Invite exception: invite!*@* set by ChanOp',
        ),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) =>
            message.content.contains('Exception: except!*@* set by ChanOp'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Quiet: quiet!*@* set by ChanOp'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('End of channel quiet list'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('routes isupport and user status numerics into server messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      ':server 005 AndroidIRCX CHANTYPES=# PREFIX=(ov)@+ NETWORK=DBase :are supported by this server',
    );
    transport.emit(':server 221 AndroidIRCX +iw');
    transport.emit(':server 381 AndroidIRCX :You are now an IRC operator');
    transport.emit(
      ':server 396 AndroidIRCX hidden.example :is now your displayed host',
    );
    transport.emit(
      ':server 263 AndroidIRCX WHO :Server load is temporarily too heavy',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('NETWORK=DBase'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('User modes: +iw'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('You are now an IRC operator'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('displayed host'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('temporarily too heavy'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test(
    'uses PREFIX and userhost-in-names data to normalize nick list entries',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '&staff'));
      transport.emit(
        ':server 005 AndroidIRCX CHANTYPES=#& PREFIX=(qaohv)~&@%+ :supported',
      );
      transport.emit(
        ':server 353 AndroidIRCX = &staff :@alice!ident@host +bob!user@host',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final staffTab = controller.tabs.firstWhere(
        (tab) => tab.name == '&staff',
      );
      controller.selectTab(staffTab.id);
      expect(
        controller.activeChannelUsers,
        containsAll(<String>['alice', 'bob']),
      );

      controller.dispose();
    },
  );

  test(
    'updates channel mode summary and nick prefixes from MODE events',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(
        ':server 005 AndroidIRCX PREFIX=(ov)@+ CHANMODES=b,k,l,imnpst :supported',
      );
      transport.emit(':server 353 AndroidIRCX = #room :@alice +bob');
      await Future<void>.delayed(Duration.zero);
      final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      controller.selectTab(roomTab.id);

      expect(
        controller.activeChannelUserDetails
            .firstWhere((item) => item.nick == 'alice')
            .details,
        contains('mode: @'),
      );
      expect(
        controller.activeChannelUserDetails
            .firstWhere((item) => item.nick == 'bob')
            .details,
        contains('mode: +'),
      );

      transport.emit(':oper!user@example MODE #room -o+v alice alice');
      transport.emit(':oper!user@example MODE #room +m');
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.activeChannelUserDetails
            .firstWhere((item) => item.nick == 'alice')
            .details,
        contains('mode: +'),
      );
      expect(controller.activeChannelModes, '+m');

      transport.emit(':oper!user@example MODE #room -m');
      await Future<void>.delayed(Duration.zero);
      expect(controller.activeChannelModes, '');

      controller.dispose();
    },
  );

  test(
    'routes standard replies into the target channel or server tab',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(
        ':server FAIL #room INVALID_TARGET :Channel is unavailable',
      );
      transport.emit(':server WARN * RATE_LIMIT :Slow down a little');
      transport.emit(':server NOTE #room HELLO :This is a note');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      controller.selectTab(roomTab.id);
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('Channel is unavailable'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('This is a note'),
        ),
        isTrue,
      );

      controller.selectTab(
        controller.tabs.firstWhere((tab) => tab.type == ChatTabType.server).id,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('Slow down a little'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test(
    'shows invite-notify target nick when invite is not for the local user',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(':carol!user@example INVITE dave #room');
      await Future<void>.delayed(Duration.zero);

      final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      controller.selectTab(roomTab.id);
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('carol invited dave to #room'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test(
    'shows extended-join account and realname details in join messages',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      transport.emit(
        ':alice!user@example JOIN #room aliceAccount :Alice Example',
      );
      await Future<void>.delayed(Duration.zero);

      final roomTab = controller.tabs.firstWhere((tab) => tab.name == '#room');
      controller.selectTab(roomTab.id);
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('account: aliceAccount'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('realname: Alice Example'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('sends metadata and rename commands from composer', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    await controller.handleComposerSubmit(
      '/metadata #room set topic-info colorful',
    );
    await controller.handleComposerSubmit('/rename #room2 moved');

    expect(
      transport.sentLines,
      contains('METADATA #room SET topic-info :colorful'),
    );
    expect(transport.sentLines, contains('RENAME #room #room2 :moved'));

    controller.dispose();
  });

  test(
    'routes metadata numerics and channel rename into channel state',
    () async {
      final transport = _FakeTransport();
      final service = IrcService(transportConnector: (_) async => transport);
      final controller = ChatSessionController(
        network: const NetworkConfig(
          id: 'dbase',
          name: 'DBase',
          host: 'irc.example.test',
          port: 6697,
          nickname: 'AndroidIRCX',
          altNickname: 'AndroidIRCX_',
        ),
        ircService: service,
      );

      await controller.start();
      await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
      transport.emit(':server 761 AndroidIRCX #room topic-info :colorful');
      transport.emit(':server 766 AndroidIRCX #room :End of metadata');
      transport.emit(
        ':chanserv!service@example RENAME #room #room2 :migration',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final renamedTab = controller.tabs.firstWhere(
        (tab) => tab.name == '#room2',
      );
      controller.selectTab(renamedTab.id);
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('METADATA #room'),
        ),
        isTrue,
      );
      expect(
        controller.activeMessages.any(
          (message) => message.content.contains('renamed #room to #room2'),
        ),
        isTrue,
      );

      controller.dispose();
    },
  );

  test('routes away numerics into server messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(transportConnector: (_) async => transport);
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(
      ':server 306 AndroidIRCX :You have been marked as being away',
    );
    transport.emit(
      ':server 305 AndroidIRCX :You are no longer marked as being away',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('marked as being away'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('no longer marked as being away'),
      ),
      isTrue,
    );

    controller.dispose();
  });
}

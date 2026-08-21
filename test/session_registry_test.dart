import 'dart:async';

import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
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

class _RecordingForegroundConnectionService
    extends ForegroundConnectionService {
  int ensureReadyCount = 0;
  int stopCount = 0;
  final updates = <ForegroundConnectionSnapshot>[];
  final notifications = <ForegroundUserNotification>[];

  @override
  Future<void> ensureReady() async {
    ensureReadyCount += 1;
  }

  @override
  Future<void> update(ForegroundConnectionSnapshot snapshot) async {
    updates.add(snapshot);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<bool> openBatteryOptimizationSettings() async => true;

  @override
  Future<ForegroundConnectionAction?> consumePendingAction() async => null;

  @override
  Future<void> showNotification(ForegroundUserNotification notification) async {
    notifications.add(notification);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reuses existing session per network id', () {
    final registry = SessionRegistry();
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    final first = registry.obtainSession(network);
    final second = registry.obtainSession(network);

    expect(identical(first, second), isTrue);
    expect(registry.sessions, hasLength(1));

    registry.dispose();
  });

  test('closeSession removes controller from registry', () async {
    final registry = SessionRegistry();
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    registry.obtainSession(network);
    await registry.closeSession(network.id);

    expect(registry.hasSession(network.id), isFalse);
    expect(registry.sessions, isEmpty);

    registry.dispose();
  });

  test('exposes current nick for existing session', () {
    final registry = SessionRegistry();
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    registry.obtainSession(network);

    expect(registry.currentNickFor(network.id), 'AndroidIRCX');

    registry.dispose();
  });

  test('syncs foreground service from connected sessions', () async {
    final transport = _FakeTransport();
    final foregroundService = _RecordingForegroundConnectionService();
    final registry = SessionRegistry(
      foregroundService: foregroundService,
      sessionFactory: (network) => ChatSessionController(
        network: network,
        ircService: IrcService(transportConnector: (_) async => transport),
        reconnectJitterFactor: 0,
      ),
    );
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    final session = registry.obtainSession(network);
    await session.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    await Future<void>.delayed(Duration.zero);
    await registry.syncForegroundConnectionService();

    expect(foregroundService.ensureReadyCount, greaterThanOrEqualTo(1));
    expect(foregroundService.updates.last.connectedNetworkCount, 1);
    expect(foregroundService.updates.last.activeNetworkCount, 1);

    await registry.closeSession(network.id);

    expect(foregroundService.stopCount, greaterThanOrEqualTo(1));

    registry.dispose();
  });

  test('handles network availability changes for tracked sessions', () async {
    final transports = <_FakeTransport>[];
    final foregroundService = _RecordingForegroundConnectionService();
    final registry = SessionRegistry(
      foregroundService: foregroundService,
      sessionFactory: (network) => ChatSessionController(
        network: network,
        ircService: IrcService(
          transportConnector: (_) async {
            final transport = _FakeTransport();
            transports.add(transport);
            return transport;
          },
        ),
        reconnectJitterFactor: 0,
      ),
    );
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    final session = registry.obtainSession(network);
    await session.start();
    transports.single.emit(':server 001 AndroidIRCX :Welcome');
    await Future<void>.delayed(Duration.zero);
    await registry.syncForegroundConnectionService();
    final stopCountBeforeOffline = foregroundService.stopCount;

    await registry.handleNetworkAvailabilityChanged(false);
    await Future<void>.delayed(Duration.zero);

    expect(session.connection.phase, ConnectionPhase.disconnected);
    expect(transports.single.closeCount, 1);
    expect(foregroundService.stopCount, greaterThan(stopCountBeforeOffline));

    final updateCountBeforeOnline = foregroundService.updates.length;
    await registry.handleNetworkAvailabilityChanged(true);
    await Future<void>.delayed(Duration.zero);

    expect(transports, hasLength(2));
    expect(
      foregroundService.updates.length,
      greaterThan(updateCountBeforeOnline),
    );

    registry.dispose();
  });

  test('forwards user notifications from active sessions', () async {
    final transport = _FakeTransport();
    final foregroundService = _RecordingForegroundConnectionService();
    final registry = SessionRegistry(
      foregroundService: foregroundService,
      sessionFactory: (network) => ChatSessionController(
        network: network,
        ircService: IrcService(transportConnector: (_) async => transport),
        reconnectJitterFactor: 0,
        settingsRepository: const _NotificationsOnSettingsRepository(),
      ),
    );
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    final session = registry.obtainSession(network);
    await session.start();
    transport.emit(':server 001 AndroidIRCX :Welcome');
    await session.joinChannel(const JoinChannelRequest(channel: '#room'));
    await registry.handleAppLifecycleState(AppLifecycleState.paused);
    transport.emit(':alice!user@example PRIVMSG AndroidIRCX :private ping');
    transport.emit(':bob!user@example PRIVMSG #room :AndroidIRCX check this');
    transport.emit(
      ':carol!user@example PRIVMSG #room :manual https://example.test/manual.pdf',
    );
    transport.emit('ERROR :Closing Link: test failure');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      foregroundService.notifications.map(
        (notification) => notification.channelKind,
      ),
      containsAll(<ForegroundNotificationChannelKind>[
        ForegroundNotificationChannelKind.queries,
        ForegroundNotificationChannelKind.highlights,
        ForegroundNotificationChannelKind.mediaTransfers,
        ForegroundNotificationChannelKind.errors,
      ]),
    );

    registry.dispose();
  });

  test('closeAllSessions clears all tracked sessions', () async {
    final registry = SessionRegistry();
    const dbase = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    const libera = NetworkConfig(
      id: 'libera',
      name: 'Libera',
      host: 'irc.libera.chat',
      port: 6697,
      nickname: 'AndroidIRCX2',
      altNickname: 'AndroidIRCX2_',
    );

    registry.obtainSession(dbase);
    registry.obtainSession(libera);

    await registry.closeAllSessions();

    expect(registry.sessions, isEmpty);
    expect(registry.hasSession(dbase.id), isFalse);
    expect(registry.hasSession(libera.id), isFalse);

    registry.dispose();
  });

  test('lifecycle flush and single close keep networks isolated', () async {
    final registry = SessionRegistry();
    const dbase = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );
    const libera = NetworkConfig(
      id: 'libera',
      name: 'Libera',
      host: 'irc.libera.chat',
      port: 6697,
      nickname: 'AndroidIRCX2',
      altNickname: 'AndroidIRCX2_',
    );

    final dbaseSession = registry.obtainSession(dbase);
    final liberaSession = registry.obtainSession(libera);

    await registry.handleAppLifecycleState(AppLifecycleState.paused);

    expect(registry.sessions, hasLength(2));
    expect(registry.obtainSession(dbase), same(dbaseSession));
    expect(registry.obtainSession(libera), same(liberaSession));

    await registry.closeSession(dbase.id);

    expect(registry.hasSession(dbase.id), isFalse);
    expect(registry.hasSession(libera.id), isTrue);
    expect(registry.obtainSession(libera), same(liberaSession));

    registry.dispose();
  });

  test('reports zero activity count for idle session', () {
    final registry = SessionRegistry();
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    registry.obtainSession(network);

    expect(registry.activityCountFor(network.id), 0);

    registry.dispose();
  });
}

class _NotificationsOnSettingsRepository implements SettingsRepository {
  const _NotificationsOnSettingsRepository();

  @override
  Future<AppSettings> loadSettings() async =>
      const AppSettings(notificationsEnabled: true);

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

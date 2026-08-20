import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();
  final List<String> sentLines = <String>[];

  @override
  Stream<String> get lines => _controller.stream;

  void emit(String line) {
    _controller.add(line);
  }

  @override
  Future<void> close() async {
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

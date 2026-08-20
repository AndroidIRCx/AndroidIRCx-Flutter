import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/dcc_session.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defines notification channels needed by the Android service', () {
    expect(
      foregroundNotificationChannels.map((channel) => channel.id),
      containsAll(<String>[
        'irc_connection',
        'irc_highlights',
        'irc_queries',
        'irc_dcc_transfers',
        'irc_media_transfers',
        'irc_errors',
      ]),
    );
  });

  test('summarizes active connection state for foreground service payload', () {
    const snapshot = ForegroundConnectionSnapshot(
      networks: <ForegroundConnectionNetwork>[
        ForegroundConnectionNetwork(
          id: 'dbase',
          name: 'DBase',
          phase: ConnectionPhase.connected,
        ),
        ForegroundConnectionNetwork(
          id: 'libera',
          name: 'Libera',
          phase: ConnectionPhase.reconnecting,
          message: 'Reconnecting in 10s.',
        ),
        ForegroundConnectionNetwork(
          id: 'idle',
          name: 'IdleNet',
          phase: ConnectionPhase.idle,
        ),
      ],
    );

    expect(snapshot.shouldRunForegroundService, isTrue);
    expect(snapshot.activeNetworkCount, 2);
    expect(snapshot.connectedNetworkCount, 1);
    expect(snapshot.reconnectingNetworkCount, 1);
    expect(snapshot.errorNetworkCount, 0);
    expect(snapshot.toJson()['networks'], hasLength(3));
  });

  test('method channel service sends expected method calls', () async {
    const channel = MethodChannel('androidircx/foreground_connection_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'openBatteryOptimizationSettings') {
            return true;
          }
          if (call.method == 'consumePendingAction') {
            return 'disconnectAll';
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelForegroundConnectionService(channel: channel);
    await service.ensureReady();
    await service.update(
      const ForegroundConnectionSnapshot(
        networks: <ForegroundConnectionNetwork>[
          ForegroundConnectionNetwork(
            id: 'dbase',
            name: 'DBase',
            phase: ConnectionPhase.connected,
          ),
        ],
      ),
    );
    final opened = await service.openBatteryOptimizationSettings();
    final action = await service.consumePendingAction();
    await service.showNotification(
      const ForegroundUserNotification(
        id: 'note-1',
        channelKind: ForegroundNotificationChannelKind.highlights,
        networkId: 'dbase',
        tabId: 'channel::dbase::#room',
        title: 'alice mentioned you',
        body: 'alice: hello AndroidIRCX',
      ),
    );
    await service.stop();

    expect(opened, isTrue);
    expect(action, ForegroundConnectionAction.disconnectAll);
    expect(calls.map((call) => call.method), <String>[
      'ensureReady',
      'update',
      'openBatteryOptimizationSettings',
      'consumePendingAction',
      'showNotification',
      'stop',
    ]);
    final updateArguments = calls[1].arguments! as Map<Object?, Object?>;
    expect(updateArguments['activeNetworkCount'], 1);
    expect(updateArguments['connectedNetworkCount'], 1);
    final notificationArguments = calls[4].arguments! as Map<Object?, Object?>;
    expect(notificationArguments['channelId'], 'irc_highlights');
    expect(notificationArguments['title'], 'alice mentioned you');
  });

  test('serializes DCC transfer progress without private local paths', () {
    const session = DccSession(
      id: 'dcc-1',
      tabId: 'dcc::dbase::1',
      peerNick: 'alice',
      type: DccSessionType.send,
      status: DccSessionStatus.connected,
      direction: 'incoming',
      filename: 'movie.mkv',
      size: 1000,
      filePath: r'C:\Users\majst\AppData\Local\Temp\movie.mkv',
      bytesTransferred: 250,
      bytesPerSecond: 512,
      estimatedRemaining: Duration(seconds: 2),
    );
    final transfer = ForegroundTransferSnapshot.fromDccSession(
      networkId: 'dbase',
      session: session,
    );
    final snapshot = ForegroundConnectionSnapshot(
      networks: const <ForegroundConnectionNetwork>[
        ForegroundConnectionNetwork(
          id: 'dbase',
          name: 'DBase',
          phase: ConnectionPhase.connected,
        ),
      ],
      transfers: [transfer],
    );
    final json = snapshot.toJson();
    final transfers = json['transfers']! as List<Object?>;
    final payload = transfers.single! as Map<Object?, Object?>;

    expect(snapshot.activeTransferCount, 1);
    expect(payload['fileName'], 'movie.mkv');
    expect(payload['progress'], 0.25);
    expect(payload['bytesPerSecond'], 512);
    expect(payload['estimatedRemainingSeconds'], 2);
    expect(payload.values, isNot(contains(contains('AppData'))));
  });

  test('active transfers keep foreground service payload alive', () {
    const session = DccSession(
      id: 'dcc-2',
      tabId: 'dcc::dbase::2',
      peerNick: 'alice',
      type: DccSessionType.send,
      status: DccSessionStatus.connected,
      direction: 'incoming',
      filename: 'file.bin',
      bytesTransferred: 1,
    );
    final snapshot = ForegroundConnectionSnapshot(
      networks: const <ForegroundConnectionNetwork>[
        ForegroundConnectionNetwork(
          id: 'dbase',
          name: 'DBase',
          phase: ConnectionPhase.disconnected,
        ),
      ],
      transfers: [
        ForegroundTransferSnapshot.fromDccSession(
          networkId: 'dbase',
          session: session,
        ),
      ],
    );

    expect(snapshot.activeNetworkCount, 0);
    expect(snapshot.activeTransferCount, 1);
    expect(snapshot.shouldRunForegroundService, isTrue);
  });

  test('method channel update stops service for inactive snapshots', () async {
    const channel = MethodChannel('androidircx/foreground_connection_empty');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    const service = MethodChannelForegroundConnectionService(channel: channel);
    await service.update(
      const ForegroundConnectionSnapshot(
        networks: <ForegroundConnectionNetwork>[
          ForegroundConnectionNetwork(
            id: 'idle',
            name: 'IdleNet',
            phase: ConnectionPhase.idle,
          ),
        ],
      ),
    );

    expect(calls, <String>['stop']);
  });
}

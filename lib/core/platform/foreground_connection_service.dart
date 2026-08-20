import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/dcc_session.dart';
import 'package:flutter/services.dart';

enum ForegroundNotificationChannelKind {
  connection,
  highlights,
  queries,
  dccTransfers,
  mediaTransfers,
  errors,
}

enum ForegroundConnectionAction { disconnectAll }

class ForegroundNotificationChannel {
  const ForegroundNotificationChannel({
    required this.kind,
    required this.id,
    required this.name,
    required this.description,
  });

  final ForegroundNotificationChannelKind kind;
  final String id;
  final String name;
  final String description;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'id': id,
      'name': name,
      'description': description,
    };
  }
}

const foregroundNotificationChannels = <ForegroundNotificationChannel>[
  ForegroundNotificationChannel(
    kind: ForegroundNotificationChannelKind.connection,
    id: 'irc_connection',
    name: 'IRC connection',
    description: 'Persistent IRC connection status.',
  ),
  ForegroundNotificationChannel(
    kind: ForegroundNotificationChannelKind.highlights,
    id: 'irc_highlights',
    name: 'Highlights',
    description: 'Mentions, highlights, and important channel messages.',
  ),
  ForegroundNotificationChannel(
    kind: ForegroundNotificationChannelKind.queries,
    id: 'irc_queries',
    name: 'Private messages',
    description: 'Direct IRC query messages.',
  ),
  ForegroundNotificationChannel(
    kind: ForegroundNotificationChannelKind.dccTransfers,
    id: 'irc_dcc_transfers',
    name: 'DCC transfers',
    description: 'DCC chat and file transfer progress.',
  ),
  ForegroundNotificationChannel(
    kind: ForegroundNotificationChannelKind.mediaTransfers,
    id: 'irc_media_transfers',
    name: 'Media transfers',
    description: 'Media preview and download progress.',
  ),
  ForegroundNotificationChannel(
    kind: ForegroundNotificationChannelKind.errors,
    id: 'irc_errors',
    name: 'Connection errors',
    description: 'Connection failures and important protocol errors.',
  ),
];

class ForegroundConnectionNetwork {
  const ForegroundConnectionNetwork({
    required this.id,
    required this.name,
    required this.phase,
    this.message,
  });

  final String id;
  final String name;
  final ConnectionPhase phase;
  final String? message;

  bool get keepsForegroundServiceRunning {
    return switch (phase) {
      ConnectionPhase.connecting ||
      ConnectionPhase.registering ||
      ConnectionPhase.authenticating ||
      ConnectionPhase.connected ||
      ConnectionPhase.reconnecting ||
      ConnectionPhase.disconnecting => true,
      ConnectionPhase.idle ||
      ConnectionPhase.disconnected ||
      ConnectionPhase.error => false,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'phase': phase.name,
      if ((message ?? '').trim().isNotEmpty) 'message': message!.trim(),
    };
  }
}

class ForegroundConnectionSnapshot {
  const ForegroundConnectionSnapshot({
    required this.networks,
    this.transfers = const <ForegroundTransferSnapshot>[],
    this.channels = foregroundNotificationChannels,
  });

  final List<ForegroundConnectionNetwork> networks;
  final List<ForegroundTransferSnapshot> transfers;
  final List<ForegroundNotificationChannel> channels;

  int get activeNetworkCount =>
      networks.where((network) => network.keepsForegroundServiceRunning).length;

  int get connectedNetworkCount => networks
      .where((network) => network.phase == ConnectionPhase.connected)
      .length;

  int get reconnectingNetworkCount => networks
      .where((network) => network.phase == ConnectionPhase.reconnecting)
      .length;

  int get errorNetworkCount => networks
      .where((network) => network.phase == ConnectionPhase.error)
      .length;

  int get activeTransferCount =>
      transfers.where((transfer) => transfer.isActive).length;

  bool get shouldRunForegroundService => activeNetworkCount > 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'channels': channels
          .map((channel) => channel.toJson())
          .toList(growable: false),
      'networks': networks
          .map((network) => network.toJson())
          .toList(growable: false),
      'transfers': transfers
          .map((transfer) => transfer.toJson())
          .toList(growable: false),
      'activeNetworkCount': activeNetworkCount,
      'connectedNetworkCount': connectedNetworkCount,
      'reconnectingNetworkCount': reconnectingNetworkCount,
      'errorNetworkCount': errorNetworkCount,
      'activeTransferCount': activeTransferCount,
      'shouldRunForegroundService': shouldRunForegroundService,
    };
  }
}

enum ForegroundTransferKind { dcc, media }

class ForegroundTransferSnapshot {
  const ForegroundTransferSnapshot({
    required this.id,
    required this.networkId,
    required this.tabId,
    required this.kind,
    required this.status,
    required this.direction,
    this.peerNick,
    this.fileName,
    this.bytesTransferred = 0,
    this.totalBytes,
  });

  final String id;
  final String networkId;
  final String tabId;
  final ForegroundTransferKind kind;
  final String status;
  final String direction;
  final String? peerNick;
  final String? fileName;
  final int bytesTransferred;
  final int? totalBytes;

  bool get isActive {
    return switch (status) {
      'offering' || 'connecting' || 'connected' => true,
      _ => false,
    };
  }

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (bytesTransferred / total).clamp(0, 1).toDouble();
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'networkId': networkId,
      'tabId': tabId,
      'kind': kind.name,
      'status': status,
      'direction': direction,
      if ((peerNick ?? '').trim().isNotEmpty) 'peerNick': peerNick!.trim(),
      if ((fileName ?? '').trim().isNotEmpty) 'fileName': fileName!.trim(),
      'bytesTransferred': bytesTransferred,
      if (totalBytes != null) 'totalBytes': totalBytes,
      if (progress != null) 'progress': progress,
    };
  }

  factory ForegroundTransferSnapshot.fromDccSession({
    required String networkId,
    required DccSession session,
  }) {
    return ForegroundTransferSnapshot(
      id: session.id,
      networkId: networkId,
      tabId: session.tabId,
      kind: ForegroundTransferKind.dcc,
      status: session.status.name,
      direction: session.direction,
      peerNick: session.peerNick,
      fileName: session.filename,
      bytesTransferred: session.bytesTransferred,
      totalBytes: session.size,
    );
  }
}

abstract class ForegroundConnectionService {
  const ForegroundConnectionService();

  Future<void> ensureReady();

  Future<void> update(ForegroundConnectionSnapshot snapshot);

  Future<void> stop();

  Future<bool> openBatteryOptimizationSettings();

  Future<ForegroundConnectionAction?> consumePendingAction();
}

class NoopForegroundConnectionService extends ForegroundConnectionService {
  const NoopForegroundConnectionService();

  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> update(ForegroundConnectionSnapshot snapshot) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<bool> openBatteryOptimizationSettings() async => false;

  @override
  Future<ForegroundConnectionAction?> consumePendingAction() async => null;
}

class MethodChannelForegroundConnectionService
    extends ForegroundConnectionService {
  const MethodChannelForegroundConnectionService({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel;

  static const _channelName = 'androidircx/foreground_connection_service';

  final MethodChannel _channel;

  @override
  Future<void> ensureReady() {
    return _invokeOptional<void>('ensureReady', <String, Object?>{
      'channels': foregroundNotificationChannels
          .map((channel) => channel.toJson())
          .toList(growable: false),
    });
  }

  @override
  Future<void> update(ForegroundConnectionSnapshot snapshot) {
    if (!snapshot.shouldRunForegroundService) {
      return stop();
    }
    return _invokeOptional<void>('update', snapshot.toJson());
  }

  @override
  Future<void> stop() {
    return _invokeOptional<void>('stop');
  }

  @override
  Future<bool> openBatteryOptimizationSettings() async {
    return await _invokeOptional<bool>('openBatteryOptimizationSettings') ??
        false;
  }

  @override
  Future<ForegroundConnectionAction?> consumePendingAction() async {
    final rawAction = await _invokeOptional<String>('consumePendingAction');
    return switch (rawAction) {
      'disconnectAll' => ForegroundConnectionAction.disconnectAll,
      _ => null,
    };
  }

  Future<T?> _invokeOptional<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }
}

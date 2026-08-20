import 'dart:async';

import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

typedef ChatSessionControllerFactory =
    ChatSessionController Function(NetworkConfig network);

class SessionRegistry extends ChangeNotifier {
  SessionRegistry({
    ForegroundConnectionService foregroundService =
        const NoopForegroundConnectionService(),
    ChatSessionControllerFactory? sessionFactory,
  }) : _foregroundService = foregroundService,
       _sessionFactory =
           sessionFactory ??
           ((network) => ChatSessionController(network: network));

  final Map<String, ChatSessionController> _sessions = {};
  final Map<String, VoidCallback> _listeners = {};
  final Map<String, StreamSubscription<ForegroundUserNotification>>
  _notificationSubscriptions = {};
  final ForegroundConnectionService _foregroundService;
  final ChatSessionControllerFactory _sessionFactory;
  bool _isAppInForeground = true;

  List<ChatSessionController> get sessions =>
      List<ChatSessionController>.unmodifiable(_sessions.values);

  bool hasSession(String networkId) => _sessions.containsKey(networkId);

  ChatSessionController obtainSession(NetworkConfig network) {
    final existing = _sessions[network.id];
    if (existing != null) {
      return existing;
    }

    final controller = _sessionFactory(network);
    void listener() {
      notifyListeners();
      unawaited(syncForegroundConnectionService());
    }

    controller.addListener(listener);
    _listeners[network.id] = listener;
    _notificationSubscriptions[network.id] = controller.notifications.listen((
      notification,
    ) {
      final activeSession = _sessions[network.id];
      if (_isAppInForeground &&
          activeSession != null &&
          activeSession.activeTabId == notification.tabId) {
        return;
      }
      unawaited(_showUserNotification(notification));
    });
    _sessions[network.id] = controller;
    notifyListeners();
    unawaited(syncForegroundConnectionService());
    return controller;
  }

  ConnectionSnapshot connectionFor(String networkId) {
    return _sessions[networkId]?.connection ??
        const ConnectionSnapshot(networkId: '', phase: ConnectionPhase.idle);
  }

  String? currentNickFor(String networkId) {
    return _sessions[networkId]?.currentNick;
  }

  int activityCountFor(String networkId) {
    return _sessions[networkId]?.activityCount ?? 0;
  }

  Future<void> closeSession(String networkId) async {
    final controller = _sessions.remove(networkId);
    final listener = _listeners.remove(networkId);
    final notificationSubscription = _notificationSubscriptions.remove(
      networkId,
    );
    if (controller == null) {
      return;
    }

    if (listener != null) {
      controller.removeListener(listener);
    }
    await notificationSubscription?.cancel();
    await controller.disconnect();
    controller.dispose();
    notifyListeners();
    await syncForegroundConnectionService();
  }

  Future<void> closeAllSessions() async {
    final networkIds = _sessions.keys.toList(growable: false);
    for (final networkId in networkIds) {
      await closeSession(networkId);
    }
  }

  Future<void> flushAllSessions() async {
    final sessions = _sessions.values.toList(growable: false);
    await Future.wait(sessions.map((controller) => controller.flushState()));
  }

  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    _isAppInForeground = state == AppLifecycleState.resumed;
    switch (state) {
      case AppLifecycleState.resumed:
        await syncForegroundConnectionService();
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        await flushAllSessions();
        await syncForegroundConnectionService();
    }
  }

  Future<void> handleNetworkAvailabilityChanged(bool isOnline) async {
    final sessions = _sessions.values.toList(growable: false);
    await Future.wait(
      sessions.map(
        (controller) => controller.handleNetworkAvailabilityChanged(isOnline),
      ),
    );
    await syncForegroundConnectionService();
  }

  Future<void> syncForegroundConnectionService() async {
    final snapshot = _foregroundSnapshot();
    if (!snapshot.shouldRunForegroundService) {
      await _foregroundService.stop();
      return;
    }

    await _foregroundService.ensureReady();
    await _foregroundService.update(snapshot);
  }

  Future<void> _showUserNotification(
    ForegroundUserNotification notification,
  ) async {
    await _foregroundService.ensureReady();
    await _foregroundService.showNotification(notification);
  }

  ForegroundConnectionSnapshot _foregroundSnapshot() {
    return ForegroundConnectionSnapshot(
      networks: _sessions.values
          .map(
            (controller) => ForegroundConnectionNetwork(
              id: controller.network.id,
              name: controller.network.name,
              phase: controller.connection.phase,
              message: controller.connection.message,
            ),
          )
          .toList(growable: false),
      transfers: _sessions.values
          .expand(
            (controller) => controller.dccSessions.map(
              (session) => ForegroundTransferSnapshot.fromDccSession(
                networkId: controller.network.id,
                session: session,
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  void dispose() {
    for (final entry in _sessions.entries) {
      final listener = _listeners[entry.key];
      if (listener != null) {
        entry.value.removeListener(listener);
      }
      unawaited(_notificationSubscriptions[entry.key]?.cancel());
      entry.value.dispose();
    }
    _sessions.clear();
    _listeners.clear();
    _notificationSubscriptions.clear();
    unawaited(_foregroundService.stop());
    super.dispose();
  }
}

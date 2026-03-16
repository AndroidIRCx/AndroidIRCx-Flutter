import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:flutter/foundation.dart';

class SessionRegistry extends ChangeNotifier {
  final Map<String, ChatSessionController> _sessions = {};
  final Map<String, VoidCallback> _listeners = {};

  List<ChatSessionController> get sessions =>
      List<ChatSessionController>.unmodifiable(_sessions.values);

  bool hasSession(String networkId) => _sessions.containsKey(networkId);

  ChatSessionController obtainSession(NetworkConfig network) {
    final existing = _sessions[network.id];
    if (existing != null) {
      return existing;
    }

    final controller = ChatSessionController(network: network);
    void listener() => notifyListeners();
    controller.addListener(listener);
    _listeners[network.id] = listener;
    _sessions[network.id] = controller;
    notifyListeners();
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
    if (controller == null) {
      return;
    }

    if (listener != null) {
      controller.removeListener(listener);
    }
    await controller.disconnect();
    controller.dispose();
    notifyListeners();
  }

  Future<void> closeAllSessions() async {
    final networkIds = _sessions.keys.toList(growable: false);
    for (final networkId in networkIds) {
      await closeSession(networkId);
    }
  }

  @override
  void dispose() {
    for (final entry in _sessions.entries) {
      final listener = _listeners[entry.key];
      if (listener != null) {
        entry.value.removeListener(listener);
      }
      entry.value.dispose();
    }
    _sessions.clear();
    _listeners.clear();
    super.dispose();
  }
}

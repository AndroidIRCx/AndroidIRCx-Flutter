enum ConnectionPhase {
  idle,
  connecting,
  registering,
  authenticating,
  connected,
  reconnecting,
  disconnecting,
  disconnected,
  error,
}

class ConnectionSnapshot {
  const ConnectionSnapshot({
    required this.networkId,
    required this.phase,
    this.message,
  });

  final String networkId;
  final ConnectionPhase phase;
  final String? message;

  ConnectionSnapshot copyWith({
    String? networkId,
    ConnectionPhase? phase,
    String? message,
  }) {
    return ConnectionSnapshot(
      networkId: networkId ?? this.networkId,
      phase: phase ?? this.phase,
      message: message ?? this.message,
    );
  }
}

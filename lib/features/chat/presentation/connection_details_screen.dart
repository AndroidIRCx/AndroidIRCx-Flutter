import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:flutter/material.dart';

/// Per-session connection details / diagnostics panel.
class ConnectionDetailsScreen extends StatelessWidget {
  const ConnectionDetailsScreen({super.key, required this.controller});

  final ChatSessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final network = controller.network;
        final enabled = controller.enabledCapabilities.toList()..sort();
        final available = controller.availableCapabilities.toList()..sort();
        return Scaffold(
          appBar: AppBar(title: const Text('Connection details')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _row('Network', network.name),
                _row('Server', '${network.host}:${network.port}'),
                _row('Transport', network.useTls ? 'TLS' : 'Plain TCP'),
                _row('Status', _phaseLabel(controller.connection.phase)),
                if ((controller.connection.message ?? '').isNotEmpty)
                  _row('Detail', controller.connection.message!),
                _row('Nick', controller.currentNick),
                _row(
                  'Capabilities',
                  '${enabled.length} enabled / ${available.length} advertised',
                ),
                const SizedBox(height: 12),
                Text('Enabled capabilities', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                if (enabled.isEmpty)
                  const Text('None')
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final cap in enabled) Chip(label: Text(cap)),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  static String _phaseLabel(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.idle:
        return 'Idle';
      case ConnectionPhase.connecting:
        return 'Connecting';
      case ConnectionPhase.registering:
        return 'Registering';
      case ConnectionPhase.authenticating:
        return 'Authenticating';
      case ConnectionPhase.connected:
        return 'Connected';
      case ConnectionPhase.reconnecting:
        return 'Reconnecting';
      case ConnectionPhase.disconnecting:
        return 'Disconnecting';
      case ConnectionPhase.disconnected:
        return 'Disconnected';
      case ConnectionPhase.error:
        return 'Error';
    }
  }
}

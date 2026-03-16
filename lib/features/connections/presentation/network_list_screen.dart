import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:androidircx/features/chat/presentation/chat_screen.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/connections/presentation/network_form_screen.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';

class NetworkListScreen extends StatelessWidget {
  const NetworkListScreen({
    super.key,
    required this.controller,
    required this.sessionRegistry,
  });

  final NetworkListController controller;
  final SessionRegistry sessionRegistry;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, sessionRegistry]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('AndroidIRCX'),
            actions: [
              IconButton(
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.tune),
                tooltip: 'Settings',
              ),
              IconButton(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add),
                tooltip: 'Add network',
              ),
            ],
          ),
          body: SafeArea(
            child: controller.isLoading
                ? const Center(child: CircularProgressIndicator())
                : controller.networks.isEmpty
                    ? _EmptyState(onAddNetwork: () => _openForm(context))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: controller.networks.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _ActiveSessionsCard(
                              registry: sessionRegistry,
                              onOpen: (network) => _openChat(context, network),
                              onClose: sessionRegistry.closeSession,
                            );
                          }

                          final network = controller.networks[index - 1];
                          final snapshot =
                              sessionRegistry.connectionFor(network.id);
                          final currentNick =
                              sessionRegistry.currentNickFor(network.id);
                          return _NetworkCard(
                            network: network,
                            connection: snapshot,
                            hasSession: sessionRegistry.hasSession(network.id),
                            currentNick: currentNick,
                            onEdit: () => _openForm(context, initialValue: network),
                            onDelete: () async {
                              await sessionRegistry.closeSession(network.id);
                              await controller.deleteNetwork(network.id);
                            },
                            onConnect: () => _openChat(context, network),
                          );
                        },
                      ),
          ),
        );
      },
    );
  }

  Future<void> _openForm(
    BuildContext context, {
    NetworkConfig? initialValue,
  }) async {
    final result = await Navigator.of(context).push<NetworkFormResult>(
      MaterialPageRoute<NetworkFormResult>(
        builder: (_) => NetworkFormScreen(initialValue: initialValue),
      ),
    );

    if (result == null || !context.mounted) {
      return;
    }

    await controller.saveNetwork(
      name: result.name,
      host: result.host,
      port: result.port,
      nickname: result.nickname,
      altNickname: result.altNickname,
      useTls: result.useTls,
      autoConnect: result.autoConnect,
      saslMechanism: result.saslMechanism,
      saslAccount: result.saslAccount,
      saslPassword: result.saslPassword,
      networkId: initialValue?.id,
    );
  }

  Future<void> _openChat(BuildContext context, NetworkConfig network) async {
    final session = sessionRegistry.obtainSession(network);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(controller: session),
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.network,
    required this.connection,
    required this.hasSession,
    required this.currentNick,
    required this.onEdit,
    required this.onDelete,
    required this.onConnect,
  });

  final NetworkConfig network;
  final ConnectionSnapshot connection;
  final bool hasSession;
  final String? currentNick;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    network.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Edit'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${network.host}:${network.port}'),
            const SizedBox(height: 4),
            Text(
              'Nick: ${network.nickname} / ${network.altNickname ?? '${network.nickname}_'} • ${network.useTls ? 'TLS' : 'Plain TCP'}',
              style: theme.textTheme.bodySmall,
            ),
            if (network.autoConnect) ...[
              const SizedBox(height: 4),
              Text(
                'Auto connect enabled',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
            if (hasSession) ...[
              const SizedBox(height: 4),
              Text(
                'Session: ${_statusLabel(connection.phase)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if ((currentNick ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Active nick: $currentNick',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onConnect,
              icon: Icon(hasSession ? Icons.forum_outlined : Icons.wifi_tethering),
              label: Text(hasSession ? 'Open session' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.idle:
        return 'Idle';
      case ConnectionPhase.connecting:
        return 'Connecting';
      case ConnectionPhase.connected:
        return 'Connected';
      case ConnectionPhase.disconnecting:
        return 'Disconnecting';
      case ConnectionPhase.disconnected:
        return 'Disconnected';
      case ConnectionPhase.error:
        return 'Error';
    }
  }
}

class _ActiveSessionsCard extends StatelessWidget {
  const _ActiveSessionsCard({
    required this.registry,
    required this.onOpen,
    required this.onClose,
  });

  final SessionRegistry registry;
  final ValueChanged<NetworkConfig> onOpen;
  final Future<void> Function(String networkId) onClose;

  @override
  Widget build(BuildContext context) {
    final sessions = registry.sessions;
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active sessions',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final session in sessions) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _iconFor(session.connection.phase),
                  color: theme.colorScheme.primary,
                ),
                title: Text(session.network.name),
                subtitle: Text(
                  '${session.network.host}:${session.network.port} • ${_labelFor(session.connection.phase)}',
                ),
                trailing: IconButton(
                  onPressed: () => onClose(session.network.id),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close session',
                ),
                onTap: () => onOpen(session.network),
              ),
              if (session != sessions.last) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  String _labelFor(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.idle:
        return 'Idle';
      case ConnectionPhase.connecting:
        return 'Connecting';
      case ConnectionPhase.connected:
        return 'Connected';
      case ConnectionPhase.disconnecting:
        return 'Disconnecting';
      case ConnectionPhase.disconnected:
        return 'Disconnected';
      case ConnectionPhase.error:
        return 'Error';
    }
  }

  IconData _iconFor(ConnectionPhase phase) {
    switch (phase) {
      case ConnectionPhase.idle:
        return Icons.pause_circle_outline;
      case ConnectionPhase.connecting:
        return Icons.sync;
      case ConnectionPhase.connected:
        return Icons.check_circle_outline;
      case ConnectionPhase.disconnecting:
        return Icons.link_off;
      case ConnectionPhase.disconnected:
        return Icons.portable_wifi_off;
      case ConnectionPhase.error:
        return Icons.error_outline;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onAddNetwork,
  });

  final VoidCallback onAddNetwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hub_outlined,
              size: 52,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No networks configured',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sprint 1 starts with network management and IRC foundation.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAddNetwork,
              child: const Text('Add your first network'),
            ),
          ],
        ),
      ),
    );
  }
}

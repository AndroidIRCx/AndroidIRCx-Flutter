import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/presentation/chat_screen.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/connections/presentation/network_form_screen.dart';
import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';

class NetworkListScreen extends StatelessWidget {
  const NetworkListScreen({
    super.key,
    required this.controller,
  });

  final NetworkListController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
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
                        itemCount: controller.networks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final network = controller.networks[index];
                          return _NetworkCard(
                            network: network,
                            onEdit: () => _openForm(context, initialValue: network),
                            onDelete: () => controller.deleteNetwork(network.id),
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
      saslAccount: result.saslAccount,
      saslPassword: result.saslPassword,
      networkId: initialValue?.id,
    );
  }

  Future<void> _openChat(BuildContext context, NetworkConfig network) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(network: network),
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
    required this.onEdit,
    required this.onDelete,
    required this.onConnect,
  });

  final NetworkConfig network;
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
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

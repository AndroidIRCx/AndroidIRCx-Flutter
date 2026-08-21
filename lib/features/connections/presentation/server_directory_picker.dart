import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/presets/server_preset.dart';
import 'package:androidircx/core/presets/server_preset_service.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:flutter/material.dart';

/// Fetches the IRC server directory, lets the user pick a network, and saves it.
///
/// Shared by the network list and Settings so the "browse directory" action
/// behaves identically wherever it is surfaced. [presetService] is overridable
/// for tests; it defaults to the live API with an offline DBase fallback.
Future<void> showServerDirectoryPicker(
  BuildContext context,
  NetworkListController controller, {
  ServerPresetService? presetService,
}) async {
  final service = presetService ?? ServerPresetService();
  final messenger = ScaffoldMessenger.of(context);
  List<ServerPreset> presets;
  try {
    presets = await service.fetchPresetsOrFallback();
  } catch (_) {
    presets = ServerPresetService.fallbackPresets;
  }
  if (!context.mounted) {
    return;
  }

  final selected = await showModalBottomSheet<ServerPreset>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Server directory'),
              subtitle: Text('Pick a network to add'),
            ),
            const Divider(height: 1),
            for (final preset in presets)
              if (preset.preferredServer != null)
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(preset.networkName),
                  subtitle: Text(
                    '${preset.preferredServer!.hostname}:${preset.preferredServer!.port}'
                    ' • ${preset.preferredServer!.useSsl ? 'TLS' : 'Plain'}'
                    '${preset.averageUsers > 0 ? ' • ~${preset.averageUsers} users' : ''}',
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(preset),
                ),
          ],
        ),
      );
    },
  );

  if (selected == null || !context.mounted) {
    return;
  }
  final server = selected.preferredServer;
  if (server == null) {
    return;
  }

  await controller.saveNetwork(
    name: selected.networkName,
    host: server.hostname,
    port: server.port,
    nickname: 'AndroidIRCX',
    altNickname: 'AndroidIRCX_',
    useTls: server.useSsl,
    autoConnect: false,
    saslMechanism: SaslMechanism.plain,
  );
  messenger.showSnackBar(
    SnackBar(content: Text('Added ${selected.networkName}')),
  );
}

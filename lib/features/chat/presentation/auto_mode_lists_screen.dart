import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/data/user_list_entry.dart';
import 'package:flutter/material.dart';

/// Manages the automatic-mode rules (auto-op / auto-halfop / auto-voice) for the
/// active session. Operates directly on the controller so live joins and stored
/// rules stay in sync.
class AutoModeListsScreen extends StatelessWidget {
  const AutoModeListsScreen({super.key, required this.controller});

  final ChatSessionController controller;

  Future<void> _add(BuildContext context) async {
    final entry = await showDialog<UserListEntry>(
      context: context,
      builder: (_) => _AutoModeEntryDialog(network: controller.network.id),
    );
    if (entry != null) {
      await controller.addAutoModeEntry(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auto-mode lists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add rule'),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final entries = controller.autoModeEntries;
          if (entries.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    'When a matching user joins a channel where you hold the '
                    'needed privilege, the mode below is set automatically.',
                  ),
                );
              }
              final entry = entries[index - 1];
              final scope = entry.channels.isEmpty
                  ? 'all channels'
                  : entry.channels.join(', ');
              return ListTile(
                leading: Icon(_iconFor(entry.type)),
                title: Text(entry.mask),
                subtitle: Text('${entry.label} · $scope'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () => controller.removeAutoModeEntry(entry),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static IconData _iconFor(UserListType type) => switch (type) {
    UserListType.autoOp => Icons.shield_moon_outlined,
    UserListType.autoHalfOp => Icons.shield_outlined,
    UserListType.autoVoice => Icons.record_voice_over_outlined,
  };
}

extension on UserListEntry {
  String get label => type.label;
}

class _AutoModeEntryDialog extends StatefulWidget {
  const _AutoModeEntryDialog({required this.network});

  final String network;

  @override
  State<_AutoModeEntryDialog> createState() => _AutoModeEntryDialogState();
}

class _AutoModeEntryDialogState extends State<_AutoModeEntryDialog> {
  final TextEditingController _mask = TextEditingController();
  final TextEditingController _channels = TextEditingController();
  UserListType _type = UserListType.autoVoice;

  @override
  void dispose() {
    _mask.dispose();
    _channels.dispose();
    super.dispose();
  }

  void _save() {
    final mask = _mask.text.trim();
    if (mask.isEmpty) {
      return;
    }
    final channels = _channels.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    Navigator.of(context).pop(
      UserListEntry(
        type: _type,
        mask: mask,
        channels: channels,
        network: widget.network,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add auto-mode rule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<UserListType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Mode'),
            items: [
              for (final type in UserListType.values)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          TextField(
            controller: _mask,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nick or mask',
              hintText: 'alice or *!*@*.example.net',
            ),
          ),
          TextField(
            controller: _channels,
            decoration: const InputDecoration(
              labelText: 'Channels (optional)',
              hintText: '#flutter, #dart — blank = all',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rule_folder_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No auto-mode rules',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Add a rule, or use a channel user’s actions to auto-voice or '
              'auto-op them.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

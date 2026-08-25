import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/data/user_list_entry.dart';
import 'package:flutter/material.dart';

class UserListsScreen extends StatelessWidget {
  const UserListsScreen({super.key, required this.controller});

  final ChatSessionController controller;

  Future<void> _add(BuildContext context, UserListType type) async {
    final entry = await showDialog<UserListEntry>(
      context: context,
      builder: (_) => _UserListEntryDialog(
        network: controller.network.id,
        initialType: type,
      ),
    );
    if (entry != null) {
      await controller.addUserListEntry(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: UserListType.managementTypes.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('User lists'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final type in UserListType.managementTypes)
                Tab(text: type.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final type in UserListType.managementTypes)
              _UserListTypeView(
                controller: controller,
                type: type,
                onAdd: () => _add(context, type),
              ),
          ],
        ),
      ),
    );
  }
}

class _UserListTypeView extends StatelessWidget {
  const _UserListTypeView({
    required this.controller,
    required this.type,
    required this.onAdd,
  });

  final ChatSessionController controller;
  final UserListType type;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final entries = controller.userListEntriesForType(type);
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
          body: entries.isEmpty
              ? _EmptyState(type: type)
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      leading: Icon(_iconFor(type)),
                      title: Text(entry.mask),
                      subtitle: Text(_subtitle(entry)),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => controller.removeUserListEntry(entry),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  String _subtitle(UserListEntry entry) {
    final parts = <String>[
      entry.channels.isEmpty ? 'all channels' : entry.channels.join(', '),
      if (entry.network != null) 'network: ${entry.network}',
      if (entry.type == UserListType.blacklist)
        entry.effectiveBlacklistAction.label,
      if ((entry.reason ?? '').trim().isNotEmpty) 'reason: ${entry.reason}',
      if (entry.duration != null) 'duration: ${entry.duration!.inMinutes}m',
    ];
    return parts.join(' · ');
  }

  static IconData _iconFor(UserListType type) => switch (type) {
    UserListType.autoOp => Icons.shield_moon_outlined,
    UserListType.autoHalfOp => Icons.shield_outlined,
    UserListType.autoVoice => Icons.record_voice_over_outlined,
    UserListType.notify => Icons.notifications_active_outlined,
    UserListType.protectedUser => Icons.verified_user_outlined,
    UserListType.other => Icons.label_outline,
    UserListType.blacklist => Icons.gpp_bad_outlined,
  };
}

class _UserListEntryDialog extends StatefulWidget {
  const _UserListEntryDialog({
    required this.network,
    required this.initialType,
  });

  final String network;
  final UserListType initialType;

  @override
  State<_UserListEntryDialog> createState() => _UserListEntryDialogState();
}

class _UserListEntryDialogState extends State<_UserListEntryDialog> {
  final TextEditingController _mask = TextEditingController();
  final TextEditingController _channels = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _duration = TextEditingController();
  final TextEditingController _customRaw = TextEditingController();
  late UserListType _type = widget.initialType;
  BlacklistAction _blacklistAction = BlacklistAction.ignore;

  @override
  void dispose() {
    _mask.dispose();
    _channels.dispose();
    _reason.dispose();
    _duration.dispose();
    _customRaw.dispose();
    super.dispose();
  }

  void _save() {
    final mask = _mask.text.trim();
    if (mask.isEmpty) {
      return;
    }
    final channels = _channels.text
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    final durationMinutes = int.tryParse(_duration.text.trim());
    Navigator.of(context).pop(
      UserListEntry(
        type: _type,
        mask: mask,
        channels: channels,
        network: widget.network,
        blacklistAction: _type == UserListType.blacklist
            ? _blacklistAction
            : null,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        duration: durationMinutes == null || durationMinutes <= 0
            ? null
            : Duration(minutes: durationMinutes),
        customRaw: _customRaw.text.trim().isEmpty
            ? null
            : _customRaw.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user-list rule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<UserListType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'List'),
              items: [
                for (final type in UserListType.managementTypes)
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
                hintText: '#room, #ops',
              ),
            ),
            if (_type == UserListType.blacklist) ...[
              DropdownButtonFormField<BlacklistAction>(
                initialValue: _blacklistAction,
                decoration: const InputDecoration(labelText: 'Action'),
                items: [
                  for (final action in BlacklistAction.values)
                    DropdownMenuItem(value: action, child: Text(action.label)),
                ],
                onChanged: (value) => setState(
                  () => _blacklistAction = value ?? _blacklistAction,
                ),
              ),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
              TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration minutes (optional)',
                ),
              ),
              TextField(
                controller: _customRaw,
                decoration: const InputDecoration(
                  labelText: 'Custom raw template',
                  hintText: 'GLINE {hostmask} {duration} :{reason}',
                ),
              ),
            ],
          ],
        ),
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
  const _EmptyState({required this.type});

  final UserListType type;

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
              'No ${type.label.toLowerCase()} entries',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

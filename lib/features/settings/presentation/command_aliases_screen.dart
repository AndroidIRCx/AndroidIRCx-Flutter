import 'dart:async';

import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:flutter/material.dart';

/// Manage user-defined command aliases (e.g. /gm → /msg GameMaster).
/// Built-in shortcuts are listed read-only and can be shadowed.
class CommandAliasesScreen extends StatefulWidget {
  const CommandAliasesScreen({super.key, this.commandService});

  /// Overridable for tests; defaults to a fresh service over the shared
  /// alias storage.
  final CommandService? commandService;

  @override
  State<CommandAliasesScreen> createState() => _CommandAliasesScreenState();
}

class _CommandAliasesScreenState extends State<CommandAliasesScreen> {
  late final CommandService _service;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _service = widget.commandService ?? CommandService();
    unawaited(_load());
  }

  Future<void> _load() async {
    await _service.load();
    if (mounted) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _editAlias({String? alias, String? command}) async {
    final result = await showDialog<({String alias, String command})>(
      context: context,
      builder: (context) => _AliasEditDialog(alias: alias, command: command),
    );
    if (result == null || !mounted) {
      return;
    }
    final error = await _service.setAlias(result.alias, result.command);
    if (!mounted) {
      return;
    }
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {});
  }

  Future<void> _removeAlias(String alias) async {
    await _service.removeAlias(alias);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final aliases = _loaded ? _service.aliases : const <CommandAlias>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Command aliases')),
      floatingActionButton: FloatingActionButton(
        key: const Key('alias-add'),
        onPressed: () => unawaited(_editAlias()),
        tooltip: 'Add alias',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final alias in aliases)
                    ListTile(
                      key: Key('alias-row-${alias.alias}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bolt_outlined),
                      title: Text('/${alias.alias}'),
                      subtitle: Text(
                        _service.isCustomAlias(alias.alias)
                            ? alias.command
                            : '${alias.command} • built-in',
                      ),
                      onTap: () => unawaited(
                        _editAlias(alias: alias.alias, command: alias.command),
                      ),
                      trailing: _service.isCustomAlias(alias.alias)
                          ? IconButton(
                              key: Key('alias-remove-${alias.alias}'),
                              tooltip: 'Remove',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  unawaited(_removeAlias(alias.alias)),
                            )
                          : null,
                    ),
                ],
              ),
      ),
    );
  }
}

/// Owns its text controllers so they outlive the dialog's exit animation.
class _AliasEditDialog extends StatefulWidget {
  const _AliasEditDialog({this.alias, this.command});

  final String? alias;
  final String? command;

  @override
  State<_AliasEditDialog> createState() => _AliasEditDialogState();
}

class _AliasEditDialogState extends State<_AliasEditDialog> {
  late final TextEditingController _aliasController = TextEditingController(
    text: widget.alias ?? '',
  );
  late final TextEditingController _commandController = TextEditingController(
    text: widget.command ?? '',
  );

  @override
  void dispose() {
    _aliasController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.alias == null ? 'Add alias' : 'Edit alias'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('alias-name-field'),
            controller: _aliasController,
            enabled: widget.alias == null,
            decoration: const InputDecoration(
              labelText: 'Alias',
              helperText: 'One word, e.g. gm',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('alias-command-field'),
            controller: _commandController,
            decoration: const InputDecoration(
              labelText: 'Command',
              helperText: 'e.g. /msg GameMaster',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('alias-save'),
          onPressed: () => Navigator.of(context).pop((
            alias: _aliasController.text,
            command: _commandController.text,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

import 'package:androidircx/core/backup/backup_service.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/storage/identity_profile_repository.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_network_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Exports/imports non-secret app data (networks, settings, profiles) as JSON.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.service, this.settingsRepository});

  final BackupService? service;
  final SettingsRepository? settingsRepository;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupService _service;
  final _importController = TextEditingController();
  String _exported = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ??
        BackupService(
          networkRepository: SharedPrefsNetworkRepository(
            secretStorage: FlutterSecureSecretStorage(),
          ),
          settingsRepository:
              widget.settingsRepository ?? SharedPrefsSettingsRepository(),
          profileRepository: SharedPrefsIdentityProfileRepository(),
        );
  }

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final data = await _service.export();
    if (!mounted) {
      return;
    }
    setState(() {
      _exported = data;
      _busy = false;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _exported));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup copied to clipboard.')),
      );
    }
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await _service.import(_importController.text);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${result.networks} networks, ${result.profiles} profiles'
            '${result.settingsRestored ? ', settings' : ''}.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Export', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Exports networks, settings, and identity profiles. Passwords, '
              'channel keys, and certificates are never included.',
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.download),
              label: const Text('Generate backup'),
            ),
            if (_exported.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _exported,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
            ],
            const Divider(height: 32),
            Text('Restore', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Paste a backup JSON to restore it.'),
            const SizedBox(height: 8),
            TextField(
              key: const Key('backup-import-field'),
              controller: _importController,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: '{ "version": 1, ... }',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.upload),
              label: const Text('Restore'),
            ),
          ],
        ),
      ),
    );
  }
}

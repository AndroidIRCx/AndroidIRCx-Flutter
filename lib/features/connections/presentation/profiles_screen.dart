import 'package:androidircx/core/models/identity_profile.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/identity_profile_repository.dart';
import 'package:flutter/material.dart';

/// Manages reusable identity profiles (nick/realname/ident/SASL account) that
/// can be attached to a network to override its identity on connect.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key, this.repository});

  final IdentityProfileRepository? repository;

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  late final IdentityProfileRepository _repository;
  List<IdentityProfile> _profiles = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SharedPrefsIdentityProfileRepository();
    _load();
  }

  Future<void> _load() async {
    final profiles = await _repository.loadProfiles();
    if (!mounted) {
      return;
    }
    setState(() {
      _profiles = profiles;
      _isLoading = false;
    });
  }

  Future<void> _edit([IdentityProfile? existing]) async {
    final result = await showDialog<IdentityProfile>(
      context: context,
      builder: (_) => _ProfileEditorDialog(profile: existing),
    );
    if (result == null) {
      return;
    }
    await _repository.saveProfile(result);
    await _load();
  }

  Future<void> _delete(IdentityProfile profile) async {
    await _repository.deleteProfile(profile.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identity profiles'),
        actions: [
          IconButton(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            tooltip: 'Add profile',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _profiles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final profile = _profiles[index];
                  final isDefault =
                      profile.id == IdentityProfile.defaultProfileId;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(profile.name),
                      subtitle: Text(
                        'Nick: ${profile.nick}'
                        '${profile.realName == null ? '' : ' • ${profile.realName}'}'
                        '${profile.saslAccount == null ? '' : ' • SASL ${profile.saslAccount}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: isDefault
                          ? const Chip(label: Text('Default'))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _edit(profile),
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Edit',
                                ),
                                IconButton(
                                  onPressed: () => _delete(profile),
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete',
                                ),
                              ],
                            ),
                      onTap: isDefault ? null : () => _edit(profile),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({this.profile});

  final IdentityProfile? profile;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _nick;
  late final TextEditingController _altNick;
  late final TextEditingController _realName;
  late final TextEditingController _ident;
  late final TextEditingController _saslAccount;
  SaslMechanism? _saslMechanism;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile?.name ?? '');
    _nick = TextEditingController(text: profile?.nick ?? '');
    _altNick = TextEditingController(text: profile?.altNick ?? '');
    _realName = TextEditingController(text: profile?.realName ?? '');
    _ident = TextEditingController(text: profile?.ident ?? '');
    _saslAccount = TextEditingController(text: profile?.saslAccount ?? '');
    _saslMechanism = profile?.saslMechanism;
  }

  @override
  void dispose() {
    _name.dispose();
    _nick.dispose();
    _altNick.dispose();
    _realName.dispose();
    _ident.dispose();
    _saslAccount.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final nick = _nick.text.trim();
    if (name.isEmpty || nick.isEmpty) {
      return;
    }
    final existing = widget.profile;
    final id = existing?.id ??
        'profile-${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      IdentityProfile(
        id: id,
        name: name,
        nick: nick,
        altNick: _optional(_altNick.text),
        realName: _optional(_realName.text),
        ident: _optional(_ident.text),
        saslAccount: _optional(_saslAccount.text),
        saslMechanism: _saslMechanism,
        onConnectCommands: existing?.onConnectCommands ?? const <String>[],
      ),
    );
  }

  static String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.profile == null ? 'New profile' : 'Edit profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Profile name'),
            ),
            TextField(
              controller: _nick,
              decoration: const InputDecoration(labelText: 'Nick'),
            ),
            TextField(
              controller: _altNick,
              decoration: const InputDecoration(labelText: 'Alt nick'),
            ),
            TextField(
              controller: _realName,
              decoration: const InputDecoration(labelText: 'Real name'),
            ),
            TextField(
              controller: _ident,
              decoration: const InputDecoration(labelText: 'Ident / username'),
            ),
            TextField(
              controller: _saslAccount,
              decoration: const InputDecoration(labelText: 'SASL account'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SaslMechanism?>(
              initialValue: _saslMechanism,
              decoration: const InputDecoration(labelText: 'SASL mechanism'),
              items: [
                const DropdownMenuItem<SaslMechanism?>(
                  child: Text('Network default'),
                ),
                for (final mechanism in SaslMechanism.values)
                  DropdownMenuItem<SaslMechanism?>(
                    value: mechanism,
                    child: Text(mechanism.name),
                  ),
              ],
              onChanged: (value) => setState(() => _saslMechanism = value),
            ),
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

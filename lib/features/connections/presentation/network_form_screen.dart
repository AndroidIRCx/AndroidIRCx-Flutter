import 'package:androidircx/core/models/network_config.dart';
import 'package:flutter/material.dart';

class NetworkFormResult {
  const NetworkFormResult({
    required this.name,
    required this.host,
    required this.port,
    required this.nickname,
    required this.altNickname,
    required this.useTls,
    required this.autoConnect,
    required this.saslMechanism,
    this.saslAccount,
    this.saslPassword,
  });

  final String name;
  final String host;
  final int port;
  final String nickname;
  final String altNickname;
  final bool useTls;
  final bool autoConnect;
  final SaslMechanism saslMechanism;
  final String? saslAccount;
  final String? saslPassword;
}

class NetworkFormScreen extends StatefulWidget {
  const NetworkFormScreen({
    super.key,
    this.initialValue,
  });

  final NetworkConfig? initialValue;

  @override
  State<NetworkFormScreen> createState() => _NetworkFormScreenState();
}

class _NetworkFormScreenState extends State<NetworkFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _altNicknameController;
  late final TextEditingController _saslAccountController;
  late final TextEditingController _saslPasswordController;
  late bool _useTls;
  late bool _autoConnect;
  late SaslMechanism _saslMechanism;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _hostController = TextEditingController(text: initial?.host ?? '');
    _portController = TextEditingController(
      text: (initial?.port ?? 6697).toString(),
    );
    _nicknameController = TextEditingController(
      text: initial?.nickname ?? 'AndroidIRCX',
    );
    _altNicknameController = TextEditingController(
      text: initial?.altNickname ?? 'AndroidIRCX_',
    );
    _saslAccountController = TextEditingController(text: initial?.saslAccount ?? '');
    _saslPasswordController = TextEditingController(text: initial?.saslPassword ?? '');
    _useTls = initial?.useTls ?? true;
    _autoConnect = initial?.autoConnect ?? false;
    _saslMechanism = initial?.saslMechanism ?? SaslMechanism.plain;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _nicknameController.dispose();
    _altNicknameController.dispose();
    _saslAccountController.dispose();
    _saslPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialValue == null ? 'Add network' : 'Edit network'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(labelText: 'Host'),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Port is required.';
                    }

                    if (int.tryParse(value!.trim()) == null) {
                      return 'Enter a valid port.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(labelText: 'Nickname'),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _altNicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Alt nickname',
                    helperText: 'Used when the primary nick is already taken.',
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _saslAccountController,
                  decoration: const InputDecoration(
                    labelText: 'SASL account',
                    helperText: 'Optional. Enables SASL PLAIN when combined with a password.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _saslPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'SASL password',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<SaslMechanism>(
                  initialValue: _saslMechanism,
                  decoration: const InputDecoration(
                    labelText: 'SASL mechanism',
                  ),
                  items: const [
                    DropdownMenuItem<SaslMechanism>(
                      value: SaslMechanism.plain,
                      child: Text('PLAIN'),
                    ),
                    DropdownMenuItem<SaslMechanism>(
                      value: SaslMechanism.scramSha256,
                      child: Text('SCRAM-SHA-256'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _saslMechanism = value);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use TLS'),
                  subtitle: const Text('Enabled by default for modern IRC servers.'),
                  value: _useTls,
                  onChanged: (value) => setState(() => _useTls = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto connect'),
                  subtitle: const Text('Start this network automatically on app launch.'),
                  value: _autoConnect,
                  onChanged: (value) => setState(() => _autoConnect = value),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Save network'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return 'This field is required.';
    }

    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      NetworkFormResult(
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: int.parse(_portController.text.trim()),
        nickname: _nicknameController.text.trim(),
        altNickname: _altNicknameController.text.trim(),
        useTls: _useTls,
        autoConnect: _autoConnect,
        saslMechanism: _saslMechanism,
        saslAccount: _saslAccountController.text.trim(),
        saslPassword: _saslPasswordController.text,
      ),
    );
  }
}

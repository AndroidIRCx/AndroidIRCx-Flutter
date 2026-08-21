import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:androidircx/core/models/identity_profile.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/identity_profile_repository.dart';
import 'package:androidircx/dcc/services/dcc_file_picker.dart';
import 'package:androidircx/features/connections/data/pem_bundle.dart';
import 'package:flutter/material.dart';

class NetworkFormResult {
  const NetworkFormResult({
    required this.name,
    required this.host,
    required this.port,
    required this.nickname,
    required this.altNickname,
    required this.useTls,
    this.webSocketPort,
    this.webSocketPath,
    required this.autoConnect,
    required this.autoJoinChannels,
    required this.autoJoinChannelKeys,
    this.profileLabel,
    this.profileGroup,
    required this.saslMechanism,
    this.saslAccount,
    this.saslPassword,
    required this.serviceAuthFallback,
    required this.serviceAuthTarget,
    required this.proxyType,
    this.proxyHost,
    this.proxyPort,
    this.proxyUsername,
    this.proxyPassword,
    this.identityProfileId,
    this.useClientCertificate = false,
    this.clientCertificatePem,
    this.clientPrivateKeyPem,
    this.clientPkcs12Base64,
    this.clientKeyPassphrase,
  });

  final String name;
  final String host;
  final int port;
  final String nickname;
  final String altNickname;
  final bool useTls;
  final int? webSocketPort;
  final String? webSocketPath;
  final bool autoConnect;
  final List<String> autoJoinChannels;
  final Map<String, String> autoJoinChannelKeys;
  final String? profileLabel;
  final String? profileGroup;
  final SaslMechanism saslMechanism;
  final String? saslAccount;
  final String? saslPassword;
  final ServiceAuthFallback serviceAuthFallback;
  final String serviceAuthTarget;
  final IrcProxyType proxyType;
  final String? proxyHost;
  final int? proxyPort;
  final String? proxyUsername;
  final String? proxyPassword;
  final String? identityProfileId;
  final bool useClientCertificate;
  final String? clientCertificatePem;
  final String? clientPrivateKeyPem;
  final String? clientPkcs12Base64;
  final String? clientKeyPassphrase;
}

class NetworkFormScreen extends StatefulWidget {
  const NetworkFormScreen({
    super.key,
    this.initialValue,
    this.profileRepository,
    this.certificateFilePicker,
    this.certificateFileReader,
  });

  final NetworkConfig? initialValue;

  /// Source of identity profiles for the attach-profile picker; defaults to
  /// shared-prefs storage.
  final IdentityProfileRepository? profileRepository;

  /// Picks a certificate/key file to import; defaults to the native document
  /// picker. Injectable for tests.
  final DccFilePicker? certificateFilePicker;

  /// Reads the picked file's bytes; defaults to `dart:io`. Injectable for
  /// tests. PEM files decode as text; binary .p12/.pfx are kept as bytes.
  final Future<List<int>> Function(String path)? certificateFileReader;

  @override
  State<NetworkFormScreen> createState() => _NetworkFormScreenState();
}

class _NetworkFormScreenState extends State<NetworkFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _webSocketPortController;
  late final TextEditingController _webSocketPathController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _altNicknameController;
  late final TextEditingController _autoJoinChannelsController;
  late final TextEditingController _autoJoinChannelKeysController;
  late final TextEditingController _profileLabelController;
  late final TextEditingController _profileGroupController;
  late final TextEditingController _saslAccountController;
  late final TextEditingController _saslPasswordController;
  late final TextEditingController _serviceAuthTargetController;
  late final TextEditingController _proxyHostController;
  late final TextEditingController _proxyPortController;
  late final TextEditingController _proxyUsernameController;
  late final TextEditingController _proxyPasswordController;
  late bool _useTls;
  late bool _autoConnect;
  late SaslMechanism _saslMechanism;
  late ServiceAuthFallback _serviceAuthFallback;
  late IrcProxyType _proxyType;
  late final IdentityProfileRepository _profileRepository;
  List<IdentityProfile> _profiles = const [IdentityProfile.defaultProfile];
  String? _identityProfileId;
  late final TextEditingController _clientCertController;
  late final TextEditingController _clientKeyController;
  late final TextEditingController _clientKeyPassphraseController;
  late bool _useClientCertificate;
  String? _clientPkcs12Base64;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _profileRepository =
        widget.profileRepository ?? SharedPrefsIdentityProfileRepository();
    _identityProfileId = initial?.identityProfileId;
    unawaited(_loadProfiles());
    _nameController = TextEditingController(text: initial?.name ?? '');
    _hostController = TextEditingController(text: initial?.host ?? '');
    _portController = TextEditingController(
      text: (initial?.port ?? 6697).toString(),
    );
    _webSocketPortController = TextEditingController(
      text: initial?.webSocketPort?.toString() ?? '',
    );
    _webSocketPathController = TextEditingController(
      text: initial?.webSocketPath ?? '',
    );
    _nicknameController = TextEditingController(
      text: initial?.nickname ?? 'AndroidIRCX',
    );
    _altNicknameController = TextEditingController(
      text: initial?.altNickname ?? 'AndroidIRCX_',
    );
    _autoJoinChannelsController = TextEditingController(
      text: initial?.autoJoinChannels.join(', ') ?? '',
    );
    _autoJoinChannelKeysController = TextEditingController(
      text: _formatAutoJoinChannelKeys(initial?.autoJoinChannelKeys),
    );
    _profileLabelController = TextEditingController(
      text: initial?.profileLabel ?? '',
    );
    _profileGroupController = TextEditingController(
      text: initial?.profileGroup ?? '',
    );
    _saslAccountController = TextEditingController(
      text: initial?.saslAccount ?? '',
    );
    _saslPasswordController = TextEditingController(
      text: initial?.saslPassword ?? '',
    );
    _serviceAuthTargetController = TextEditingController(
      text: initial?.serviceAuthTarget ?? 'NickServ',
    );
    _proxyHostController = TextEditingController(
      text: initial?.proxyHost ?? '',
    );
    _proxyPortController = TextEditingController(
      text: initial?.proxyPort?.toString() ?? '',
    );
    _proxyUsernameController = TextEditingController(
      text: initial?.proxyUsername ?? '',
    );
    _proxyPasswordController = TextEditingController(
      text: initial?.proxyPassword ?? '',
    );
    _clientCertController = TextEditingController();
    _clientKeyController = TextEditingController();
    _clientKeyPassphraseController = TextEditingController();
    _useClientCertificate = initial?.useClientCertificate ?? false;
    _useTls = initial?.useTls ?? true;
    _autoConnect = initial?.autoConnect ?? false;
    _saslMechanism = initial?.saslMechanism ?? SaslMechanism.plain;
    _serviceAuthFallback =
        initial?.serviceAuthFallback ?? ServiceAuthFallback.disabled;
    _proxyType = initial?.proxyType ?? IrcProxyType.none;
  }

  Future<void> _loadProfiles() async {
    final profiles = await _profileRepository.loadProfiles();
    if (!mounted) {
      return;
    }
    setState(() {
      _profiles = profiles;
      if (_identityProfileId != null &&
          !profiles.any((profile) => profile.id == _identityProfileId)) {
        _identityProfileId = null;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _webSocketPortController.dispose();
    _webSocketPathController.dispose();
    _nicknameController.dispose();
    _altNicknameController.dispose();
    _autoJoinChannelsController.dispose();
    _autoJoinChannelKeysController.dispose();
    _profileLabelController.dispose();
    _profileGroupController.dispose();
    _saslAccountController.dispose();
    _saslPasswordController.dispose();
    _serviceAuthTargetController.dispose();
    _proxyHostController.dispose();
    _proxyPortController.dispose();
    _proxyUsernameController.dispose();
    _proxyPasswordController.dispose();
    _clientCertController.dispose();
    _clientKeyController.dispose();
    _clientKeyPassphraseController.dispose();
    super.dispose();
  }

  void _showFormSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importCertificateFile() async {
    final picker =
        widget.certificateFilePicker ?? const MethodChannelDccFilePicker();
    final path = await picker.pickFile();
    if (path == null || !mounted) {
      return;
    }
    List<int> bytes;
    try {
      final reader = widget.certificateFileReader ?? _defaultReadCertBytes;
      bytes = await reader(path);
    } catch (_) {
      _showFormSnack('Could not read the selected file.');
      return;
    }

    // Decode as UTF-8 to detect PEM; binary .p12/.pfx will either fail to
    // decode or contain no PEM blocks.
    String? text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = null;
    }
    final bundle = text == null ? const PemBundle() : PemBundle.parse(text);

    if (!bundle.isEmpty) {
      setState(() {
        _clientPkcs12Base64 = null;
        if (bundle.hasCertificate) {
          _clientCertController.text = bundle.certificate!;
        }
        if (bundle.hasPrivateKey) {
          _clientKeyController.text = bundle.privateKey!;
        }
      });
      final parts = <String>[
        if (bundle.hasCertificate) 'certificate',
        if (bundle.hasPrivateKey) 'private key',
      ].join(' and ');
      _showFormSnack('Imported $parts from file.');
      return;
    }

    // Binary PKCS#12 (.p12/.pfx): keep the bytes, TLS parses them natively.
    setState(() {
      _clientPkcs12Base64 = base64.encode(bytes);
      _clientCertController.clear();
      _clientKeyController.clear();
    });
    _showFormSnack(
      'Imported PKCS#12 bundle. Enter its password below if it has one.',
    );
  }

  static Future<List<int>> _defaultReadCertBytes(String path) =>
      File(path).readAsBytes();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialValue == null ? 'Add network' : 'Edit network',
        ),
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
                  controller: _webSocketPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'WebSocket port',
                    helperText:
                        'Optional. Used by Flutter Web instead of raw IRC port.',
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return null;
                    }
                    if (int.tryParse(value!.trim()) == null) {
                      return 'Enter a valid WebSocket port.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _webSocketPathController,
                  decoration: const InputDecoration(
                    labelText: 'WebSocket path',
                    helperText:
                        'Optional. Example: /irc or /websocket. Leave empty for root path.',
                  ),
                  validator: (value) {
                    final trimmed = (value ?? '').trim();
                    if (trimmed.isEmpty) {
                      return null;
                    }
                    if (!trimmed.startsWith('/')) {
                      return 'WebSocket path must start with /.';
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Client certificate (SASL EXTERNAL)'),
                  subtitle: const Text(
                    'Present a stored client cert in the TLS handshake.',
                  ),
                  value: _useClientCertificate,
                  onChanged: (value) =>
                      setState(() => _useClientCertificate = value),
                ),
                if (_useClientCertificate) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('network-form-import-cert'),
                      onPressed: () => unawaited(_importCertificateFile()),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Import from file (.pem / .p12)'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_clientPkcs12Base64 != null)
                    ListTile(
                      key: const Key('network-form-pkcs12-loaded'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('PKCS#12 bundle loaded'),
                      subtitle: const Text(
                        'The .p12/.pfx will be used for the TLS handshake.',
                      ),
                      trailing: TextButton(
                        onPressed: () =>
                            setState(() => _clientPkcs12Base64 = null),
                        child: const Text('Clear'),
                      ),
                    )
                  else ...[
                    TextFormField(
                      controller: _clientCertController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Client certificate PEM',
                        helperText:
                            'Paste or import -----BEGIN CERTIFICATE-----; leave empty to keep the stored one.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _clientKeyController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Private key PEM',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _clientKeyPassphraseController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: _clientPkcs12Base64 != null
                          ? 'PKCS#12 password (optional)'
                          : 'Private key passphrase (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<String?>(
                  initialValue: _identityProfileId,
                  decoration: const InputDecoration(
                    labelText: 'Identity profile',
                    helperText:
                        'Attach a saved identity; overrides nick/realname on connect.',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      child: Text('Use this network\'s identity'),
                    ),
                    for (final profile in _profiles)
                      if (profile.id != IdentityProfile.defaultProfileId)
                        DropdownMenuItem<String?>(
                          value: profile.id,
                          child: Text('${profile.name} (${profile.nick})'),
                        ),
                  ],
                  onChanged: (value) =>
                      setState(() => _identityProfileId = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _saslAccountController,
                  decoration: InputDecoration(
                    labelText: 'SASL account',
                    helperText: _saslMechanism == SaslMechanism.external
                        ? 'Optional. Usually not required for EXTERNAL.'
                        : 'Required for PLAIN and SCRAM-SHA-256.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _saslPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'SASL password',
                    helperText: _saslMechanism == SaslMechanism.external
                        ? 'Leave empty when client certificate auth is used.'
                        : 'Required for PLAIN and SCRAM-SHA-256.',
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
                    DropdownMenuItem<SaslMechanism>(
                      value: SaslMechanism.external,
                      child: Text('EXTERNAL'),
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
                  title: const Text('NickServ fallback'),
                  subtitle: const Text(
                    'Use SASL credentials with services when SASL is unavailable.',
                  ),
                  value: _serviceAuthFallback == ServiceAuthFallback.nickServ,
                  onChanged: (value) {
                    setState(
                      () => _serviceAuthFallback = value
                          ? ServiceAuthFallback.nickServ
                          : ServiceAuthFallback.disabled,
                    );
                  },
                ),
                if (_serviceAuthFallback == ServiceAuthFallback.nickServ) ...[
                  TextFormField(
                    key: const Key('network-form-service-auth-target'),
                    controller: _serviceAuthTargetController,
                    decoration: const InputDecoration(
                      labelText: 'Service target',
                      helperText: 'Usually NickServ.',
                    ),
                    validator: (value) {
                      if (_serviceAuthFallback ==
                              ServiceAuthFallback.nickServ &&
                          (value ?? '').trim().isEmpty) {
                        return 'Service target is required.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use TLS'),
                  subtitle: const Text(
                    'Enabled by default for modern IRC servers.',
                  ),
                  value: _useTls,
                  onChanged: (value) => setState(() => _useTls = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto connect'),
                  subtitle: const Text(
                    'Start this network automatically on app launch.',
                  ),
                  value: _autoConnect,
                  onChanged: (value) => setState(() => _autoConnect = value),
                ),
                TextFormField(
                  controller: _autoJoinChannelsController,
                  decoration: const InputDecoration(
                    labelText: 'Auto-join channels',
                    helperText:
                        'Optional comma-separated list, e.g. #androidircx, #flutter.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('network-form-auto-join-channel-keys'),
                  controller: _autoJoinChannelKeysController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Auto-join channel keys',
                    helperText:
                        'Optional one per line, e.g. #private=secret-key.',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<IrcProxyType>(
                  key: const Key('network-form-proxy-type'),
                  initialValue: _proxyType,
                  decoration: const InputDecoration(labelText: 'Proxy'),
                  items: const [
                    DropdownMenuItem<IrcProxyType>(
                      value: IrcProxyType.none,
                      child: Text('None'),
                    ),
                    DropdownMenuItem<IrcProxyType>(
                      value: IrcProxyType.socks5,
                      child: Text('SOCKS5 / Tor'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _proxyType = value);
                  },
                ),
                if (_proxyType == IrcProxyType.socks5) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('network-form-proxy-host'),
                    controller: _proxyHostController,
                    decoration: const InputDecoration(
                      labelText: 'Proxy host',
                      helperText: 'Tor default is 127.0.0.1.',
                    ),
                    validator: (value) {
                      if (_proxyType == IrcProxyType.socks5 &&
                          (value ?? '').trim().isEmpty) {
                        return 'Proxy host is required.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('network-form-proxy-port'),
                    controller: _proxyPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Proxy port',
                      helperText:
                          'Tor Browser usually uses 9150; tor daemon uses 9050.',
                    ),
                    validator: (value) {
                      if (_proxyType != IrcProxyType.socks5) {
                        return null;
                      }
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 1 || parsed > 65535) {
                        return 'Enter a valid proxy port.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('network-form-proxy-username'),
                    controller: _proxyUsernameController,
                    decoration: const InputDecoration(
                      labelText: 'Proxy username',
                      helperText: 'Optional for authenticated SOCKS5 proxies.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('network-form-proxy-password'),
                    controller: _proxyPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Proxy password',
                      helperText: 'Optional for authenticated SOCKS5 proxies.',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('network-form-profile-label'),
                  controller: _profileLabelController,
                  decoration: const InputDecoration(
                    labelText: 'Profile label',
                    helperText:
                        'Optional display label for this connection profile.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('network-form-profile-group'),
                  controller: _profileGroupController,
                  decoration: const InputDecoration(
                    labelText: 'Profile group',
                    helperText:
                        'Optional group/category, e.g. general, tech, gaming.',
                  ),
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
        webSocketPort: (_webSocketPortController.text.trim().isEmpty)
            ? null
            : int.parse(_webSocketPortController.text.trim()),
        webSocketPath: _webSocketPathController.text.trim(),
        autoConnect: _autoConnect,
        autoJoinChannels: _parseAutoJoinChannels(
          _autoJoinChannelsController.text,
        ),
        autoJoinChannelKeys: _parseAutoJoinChannelKeys(
          _autoJoinChannelKeysController.text,
        ),
        profileLabel: _optionalText(_profileLabelController.text),
        profileGroup: _optionalText(_profileGroupController.text),
        saslMechanism: _saslMechanism,
        saslAccount: _saslAccountController.text.trim(),
        saslPassword: _saslPasswordController.text,
        serviceAuthFallback: _serviceAuthFallback,
        serviceAuthTarget:
            _optionalText(_serviceAuthTargetController.text) ?? 'NickServ',
        proxyType: _proxyType,
        proxyHost: _optionalText(_proxyHostController.text),
        proxyPort: _proxyType == IrcProxyType.socks5
            ? int.parse(_proxyPortController.text.trim())
            : null,
        proxyUsername: _optionalText(_proxyUsernameController.text),
        proxyPassword: _proxyPasswordController.text,
        identityProfileId: _identityProfileId,
        useClientCertificate: _useClientCertificate,
        clientCertificatePem: _clientCertController.text,
        clientPrivateKeyPem: _clientKeyController.text,
        clientPkcs12Base64: _clientPkcs12Base64,
        clientKeyPassphrase: _clientKeyPassphraseController.text,
      ),
    );
  }

  List<String> _parseAutoJoinChannels(String value) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in value.split(',')) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final channel = trimmed.startsWith('#') ? trimmed : '#$trimmed';
      if (seen.add(channel.toLowerCase())) {
        result.add(channel);
      }
    }
    return result;
  }

  Map<String, String> _parseAutoJoinChannelKeys(String value) {
    final result = <String, String>{};
    final entries = value
        .split(RegExp(r'[\r\n,]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);

    for (final entry in entries) {
      final separatorIndex = entry.indexOf('=');
      final parts = separatorIndex == -1
          ? entry.split(RegExp(r'\s+'))
          : <String>[
              entry.substring(0, separatorIndex),
              entry.substring(separatorIndex + 1),
            ];
      if (parts.length < 2) {
        continue;
      }
      final rawChannel = parts.first.trim();
      final key = parts.skip(1).join(' ').trim();
      if (rawChannel.isEmpty || key.isEmpty) {
        continue;
      }
      final channel = rawChannel.startsWith('#') ? rawChannel : '#$rawChannel';
      result[channel] = key;
    }
    return Map<String, String>.unmodifiable(result);
  }

  String _formatAutoJoinChannelKeys(Map<String, String>? keys) {
    if (keys == null || keys.isEmpty) {
      return '';
    }
    return keys.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\n');
  }

  String? _optionalText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

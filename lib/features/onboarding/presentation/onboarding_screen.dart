import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:androidircx/features/onboarding/presentation/data_privacy_screen.dart';
import 'package:flutter/material.dart';

/// First-run wizard: welcome, privacy/consent, identity, network, channels.
///
/// On completion it creates the chosen network (unless "set up later") and
/// invokes [onCompleted], which the app uses to flip the onboarding flag and
/// enter the normal UI.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.networkRepository,
    required this.onCompleted,
  });

  final NetworkRepository networkRepository;
  final Future<void> Function() onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _NetworkMode { dbase, custom, later }

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _consentAccepted = false;
  bool _saving = false;

  final _nickname = TextEditingController(text: 'AndroidIRCX');
  final _altNick = TextEditingController(text: 'AndroidIRCX_');
  final _realName = TextEditingController(text: 'AndroidIRCX User');
  final _username = TextEditingController(text: 'androidircx');

  _NetworkMode _networkMode = _NetworkMode.dbase;
  final _customName = TextEditingController();
  final _customHost = TextEditingController();
  final _customPort = TextEditingController(text: '6697');
  bool _customTls = true;
  final _channels = TextEditingController(text: '#DBase, #AndroidIRCX');

  static const _titles = [
    'Welcome to AndroidIRCX',
    'Privacy',
    'Set up your identity',
    'Choose your network',
    'Choose your channels',
  ];

  @override
  void dispose() {
    _nickname.dispose();
    _altNick.dispose();
    _realName.dispose();
    _username.dispose();
    _customName.dispose();
    _customHost.dispose();
    _customPort.dispose();
    _channels.dispose();
    super.dispose();
  }

  bool get _canAdvance {
    switch (_step) {
      case 1:
        return _consentAccepted;
      case 2:
        return _nickname.text.trim().isNotEmpty;
      case 3:
        return _networkMode != _NetworkMode.custom ||
            (_customHost.text.trim().isNotEmpty &&
                int.tryParse(_customPort.text.trim()) != null);
      default:
        return true;
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  Future<void> _next() async {
    if (_step < _titles.length - 1) {
      setState(() => _step++);
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    if (_networkMode != _NetworkMode.later) {
      await widget.networkRepository.saveNetwork(_buildNetwork());
    }
    await widget.onCompleted();
  }

  NetworkConfig _buildNetwork() {
    final channels = _parseChannels(_channels.text);
    final nick = _nickname.text.trim().isEmpty
        ? 'AndroidIRCX'
        : _nickname.text.trim();
    final alt = _altNick.text.trim().isEmpty ? '${nick}_' : _altNick.text.trim();
    final realName = _realName.text.trim().isEmpty
        ? 'AndroidIRCX User'
        : _realName.text.trim();
    final username = _username.text.trim().isEmpty
        ? 'androidircx'
        : _username.text.trim();

    if (_networkMode == _NetworkMode.dbase) {
      return NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.dbase.in.rs',
        port: 6697,
        nickname: nick,
        altNickname: alt,
        username: username,
        realName: realName,
        useTls: true,
        autoConnect: true,
        autoJoinChannels: channels,
      );
    }

    final name = _customName.text.trim().isEmpty
        ? _customHost.text.trim()
        : _customName.text.trim();
    return NetworkConfig(
      id: name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
      name: name,
      host: _customHost.text.trim(),
      port: int.tryParse(_customPort.text.trim()) ?? 6697,
      nickname: nick,
      altNickname: alt,
      username: username,
      realName: realName,
      useTls: _customTls,
      autoConnect: true,
      autoJoinChannels: channels,
    );
  }

  static List<String> _parseChannels(String value) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in value.split(',')) {
      final trimmed = raw.trim();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _titles[_step],
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  Text(
                    '${_step + 1}/${_titles.length}',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(value: (_step + 1) / _titles.length),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStep(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _saving ? null : _back,
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: (_canAdvance && !_saving) ? _next : null,
                    child: Text(
                      _step == _titles.length - 1 ? 'Finish' : 'Next',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case 0:
        return _buildWelcome(context);
      case 1:
        return _buildPrivacy(context);
      case 2:
        return _buildIdentity(context);
      case 3:
        return _buildNetworkStep(context);
      default:
        return _buildChannels(context);
    }
  }

  Widget _buildWelcome(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.forum_outlined, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'A serious, local-first IRC client with IRCv3, DCC, media, themes, '
          'and encrypted history.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        const Text(
          'A few quick steps to set up your identity and first network.',
        ),
      ],
    );
  }

  Widget _buildPrivacy(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AndroidIRCX stores your data on this device only — no account, no '
          'cloud sync, no ads or analytics. History is encrypted behind your '
          'fingerprint/PIN and secrets live in secure storage.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const DataPrivacyScreen(),
            ),
          ),
          icon: const Icon(Icons.privacy_tip_outlined),
          label: const Text('Read data & privacy details'),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _consentAccepted,
          onChanged: (value) =>
              setState(() => _consentAccepted = value ?? false),
          title: const Text(
            'I have read and accept the privacy policy and terms.',
          ),
        ),
      ],
    );
  }

  Widget _buildIdentity(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _nickname,
          decoration: const InputDecoration(labelText: 'Nickname'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _altNick,
          decoration: const InputDecoration(labelText: 'Alternate nickname'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _realName,
          decoration: const InputDecoration(labelText: 'Real name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _username,
          decoration: const InputDecoration(labelText: 'Ident / username'),
        ),
      ],
    );
  }

  Widget _buildNetworkStep(BuildContext context) {
    return RadioGroup<_NetworkMode>(
      groupValue: _networkMode,
      onChanged: (value) =>
          setState(() => _networkMode = value ?? _networkMode),
      child: Column(
        children: [
          const RadioListTile<_NetworkMode>(
            contentPadding: EdgeInsets.zero,
            value: _NetworkMode.dbase,
            title: Text('DBase (irc.dbase.in.rs)'),
            subtitle: Text('Recommended — the AndroidIRCX home network'),
          ),
          const RadioListTile<_NetworkMode>(
            contentPadding: EdgeInsets.zero,
            value: _NetworkMode.custom,
            title: Text('Custom server'),
          ),
          if (_networkMode == _NetworkMode.custom) ...[
            TextField(
              controller: _customName,
              decoration: const InputDecoration(labelText: 'Network name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customHost,
              decoration: const InputDecoration(labelText: 'Server host'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customPort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
              onChanged: (_) => setState(() {}),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _customTls,
              onChanged: (value) => setState(() => _customTls = value),
              title: const Text('Use TLS'),
            ),
          ],
          const RadioListTile<_NetworkMode>(
            contentPadding: EdgeInsets.zero,
            value: _NetworkMode.later,
            title: Text('Set up later'),
          ),
        ],
      ),
    );
  }

  Widget _buildChannels(BuildContext context) {
    if (_networkMode == _NetworkMode.later) {
      return const Text(
        'You can add networks and channels any time from the network list.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Channels to auto-join, separated by commas.'),
        const SizedBox(height: 12),
        TextField(
          controller: _channels,
          decoration: const InputDecoration(
            labelText: 'Channels',
            hintText: '#DBase, #AndroidIRCX',
          ),
        ),
      ],
    );
  }
}

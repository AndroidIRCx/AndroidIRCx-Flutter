import 'package:androidircx/app/theme/app_theme.dart';
import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/settings/app_settings_controller.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.repository, this.settingsController});

  final SettingsRepository? repository;
  final AppSettingsController? settingsController;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _dccDownloadDirectoryController = TextEditingController();
  final _mediaDownloadDirectoryController = TextEditingController();
  final _customThemeController = TextEditingController();
  late final SettingsRepository _repository;
  AppSettingsController? _settingsController;
  AppSettings _settings = const AppSettings();
  bool _isLoading = true;
  bool _didResolveController = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SharedPrefsSettingsRepository();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didResolveController) {
      return;
    }
    _didResolveController = true;
    _settingsController =
        widget.settingsController ?? AppSettingsScope.maybeOf(context);
    final controller = _settingsController;
    if (controller == null) {
      _load();
      return;
    }
    controller.addListener(_syncFromController);
    _syncFromController();
  }

  @override
  void dispose() {
    _settingsController?.removeListener(_syncFromController);
    _dccDownloadDirectoryController.dispose();
    _mediaDownloadDirectoryController.dispose();
    _customThemeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SettingsSection(
                    title: 'Appearance',
                    children: [
                      ListTile(
                        title: const Text('Theme'),
                        subtitle: const Text('Choose the app color set.'),
                        trailing: DropdownButton<AppThemePreset>(
                          key: const Key('settings-theme-preset'),
                          value: _settings.themePreset,
                          onChanged: (value) async {
                            if (value == null) {
                              return;
                            }
                            await _saveSettings(
                              _settings.copyWith(themePreset: value),
                            );
                          },
                          items: AppThemePreset.values
                              .map(
                                (preset) => DropdownMenuItem(
                                  value: preset,
                                  child: Text(_labelForThemePreset(preset)),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      if (_settings.themePreset == AppThemePreset.custom) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: TextField(
                            key: const Key('settings-custom-theme-json'),
                            controller: _customThemeController,
                            minLines: 5,
                            maxLines: 10,
                            decoration: InputDecoration(
                              labelText: 'Custom theme JSON',
                              alignLabelWithHint: true,
                              prefixIcon: const Icon(Icons.data_object),
                              suffixIcon: IconButton(
                                onPressed: () => _saveCustomThemeJson(
                                  _customThemeController.text,
                                ),
                                icon: const Icon(Icons.save_outlined),
                                tooltip: 'Save custom theme',
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _loadCustomThemeTemplate,
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Load template'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _copyCustomThemeJson,
                                icon: const Icon(Icons.copy_outlined),
                                label: const Text('Copy JSON'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Message font size',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Slider(
                              key: const Key('settings-message-font-scale'),
                              value: _settings.messageFontScale,
                              min: 0.8,
                              max: 1.4,
                              divisions: 6,
                              label:
                                  '${(_settings.messageFontScale * 100).round()}%',
                              onChanged: (value) {
                                setState(
                                  () => _settings = _settings.copyWith(
                                    messageFontScale: value,
                                  ),
                                );
                              },
                              onChangeEnd: (value) async {
                                await _saveSettings(
                                  _settings.copyWith(messageFontScale: value),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Message density'),
                        subtitle: const Text('Control vertical spacing.'),
                        trailing: DropdownButton<MessageDensity>(
                          key: const Key('settings-message-density'),
                          value: _settings.messageDensity,
                          onChanged: (value) async {
                            if (value == null) {
                              return;
                            }
                            await _saveSettings(
                              _settings.copyWith(messageDensity: value),
                            );
                          },
                          items: MessageDensity.values
                              .map(
                                (density) => DropdownMenuItem(
                                  value: density,
                                  child: Text(_labelForDensity(density)),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('settings-monospace-messages'),
                        title: const Text('Monospace messages'),
                        subtitle: const Text(
                          'Render IRC message bodies in a fixed-width font.',
                        ),
                        value: _settings.monospaceMessages,
                        onChanged: (value) async {
                          await _saveSettings(
                            _settings.copyWith(monospaceMessages: value),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Nick colors'),
                        subtitle: const Text(
                          'Color sender names in message lists.',
                        ),
                        trailing: DropdownButton<NickColorMode>(
                          key: const Key('settings-nick-color-mode'),
                          value: _settings.nickColorMode,
                          onChanged: (value) async {
                            if (value == null) {
                              return;
                            }
                            await _saveSettings(
                              _settings.copyWith(nickColorMode: value),
                            );
                          },
                          items: NickColorMode.values
                              .map(
                                (mode) => DropdownMenuItem(
                                  value: mode,
                                  child: Text(_labelForNickColorMode(mode)),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Chat',
                    children: [
                      SwitchListTile(
                        title: const Text('Show raw IRC events'),
                        subtitle: const Text(
                          'Keep low-level IRC send/receive lines visible in the server tab.',
                        ),
                        value: _settings.showRawEvents,
                        onChanged: (value) async {
                          await _saveSettings(
                            _settings.copyWith(showRawEvents: value),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Show header search button'),
                        subtitle: const Text(
                          'Keep the inline message search toggle visible in the chat header.',
                        ),
                        value: _settings.showHeaderSearchButton,
                        onChanged: (value) async {
                          await _saveSettings(
                            _settings.copyWith(showHeaderSearchButton: value),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Show attachment previews'),
                        subtitle: const Text(
                          'Render link, file, image, and media cards below matching messages.',
                        ),
                        value: _settings.showAttachmentPreviews,
                        onChanged: (value) async {
                          await _saveSettings(
                            _settings.copyWith(showAttachmentPreviews: value),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: const Text('Notice routing'),
                        subtitle: const Text(
                          'Choose where incoming NOTICE messages should appear.',
                        ),
                        trailing: DropdownButton<NoticeRoutingMode>(
                          value: _settings.noticeRouting,
                          onChanged: (value) async {
                            if (value == null) {
                              return;
                            }
                            await _saveSettings(
                              _settings.copyWith(noticeRouting: value),
                            );
                          },
                          items: NoticeRoutingMode.values
                              .map(
                                (mode) => DropdownMenuItem(
                                  value: mode,
                                  child: Text(_labelForNoticeRouting(mode)),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Transfers',
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: TextField(
                          key: const Key('settings-dcc-download-directory'),
                          controller: _dccDownloadDirectoryController,
                          textInputAction: TextInputAction.done,
                          onSubmitted: _saveDccDownloadDirectory,
                          decoration: InputDecoration(
                            labelText: 'DCC download folder',
                            hintText: 'Default app folder',
                            prefixIcon: const Icon(Icons.folder_outlined),
                            suffixIcon: IconButton(
                              onPressed: () => _saveDccDownloadDirectory(
                                _dccDownloadDirectoryController.text,
                              ),
                              icon: const Icon(Icons.save_outlined),
                              tooltip: 'Save DCC folder',
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: TextField(
                          key: const Key('settings-media-download-directory'),
                          controller: _mediaDownloadDirectoryController,
                          textInputAction: TextInputAction.done,
                          onSubmitted: _saveMediaDownloadDirectory,
                          decoration: InputDecoration(
                            labelText: 'Media download folder',
                            hintText: 'Default app folder',
                            prefixIcon: const Icon(Icons.perm_media_outlined),
                            suffixIcon: IconButton(
                              onPressed: () => _saveMediaDownloadDirectory(
                                _mediaDownloadDirectoryController.text,
                              ),
                              icon: const Icon(Icons.save_outlined),
                              tooltip: 'Save media folder',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Help',
                    children: [
                      ListTile(
                        key: const Key('settings-help-topic'),
                        leading: const Icon(Icons.help_outline),
                        title: const Text('IRC help'),
                        subtitle: const Text(
                          'Connection, SASL, channel keys, DCC, and proxy notes.',
                        ),
                        onTap: () =>
                            _showInfoDialog(title: 'IRC help', body: _helpText),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('settings-privacy-topic'),
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('Privacy'),
                        subtitle: const Text(
                          'What stays on-device and what goes to IRC servers.',
                        ),
                        onTap: () => _showInfoDialog(
                          title: 'Privacy',
                          body: _privacyText,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('settings-support-topic'),
                        leading: const Icon(Icons.support_agent_outlined),
                        title: const Text('Support'),
                        subtitle: const Text(
                          'What to include when reporting a connection issue.',
                        ),
                        onTap: () => _showInfoDialog(
                          title: 'Support',
                          body: _supportText,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('settings-release-audit-topic'),
                        leading: const Icon(Icons.verified_outlined),
                        title: const Text('Release audit'),
                        subtitle: const Text(
                          'Package, version, permissions, and signing gates.',
                        ),
                        onTap: () => _showInfoDialog(
                          title: 'Release audit',
                          body: _releaseAuditText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _load() async {
    final settings = await _repository.loadSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _isLoading = false;
      _syncTextControllers(settings);
    });
  }

  void _syncFromController() {
    final controller = _settingsController;
    if (controller == null || !mounted) {
      return;
    }
    setState(() {
      _settings = controller.settings;
      _isLoading = controller.isLoading;
      _syncTextControllers(controller.settings);
    });
  }

  void _syncTextControllers(AppSettings settings) {
    _setControllerText(
      _dccDownloadDirectoryController,
      settings.dccDownloadDirectoryPath,
    );
    _setControllerText(
      _mediaDownloadDirectoryController,
      settings.mediaDownloadDirectoryPath,
    );
    _setControllerText(_customThemeController, settings.customThemeJson);
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.text = value;
    controller.selection = TextSelection.collapsed(offset: value.length);
  }

  Future<void> _saveSettings(AppSettings next) async {
    setState(() {
      _settings = next;
      _isLoading = false;
      _syncTextControllers(next);
    });
    final controller = _settingsController;
    if (controller != null) {
      await controller.save(next);
      return;
    }
    await _repository.saveSettings(next);
  }

  Future<void> _saveDccDownloadDirectory(String value) {
    return _saveSettings(
      _settings.copyWith(dccDownloadDirectoryPath: value.trim()),
    );
  }

  Future<void> _saveMediaDownloadDirectory(String value) {
    return _saveSettings(
      _settings.copyWith(mediaDownloadDirectoryPath: value.trim()),
    );
  }

  Future<void> _saveCustomThemeJson(String value) {
    return _saveSettings(_settings.copyWith(customThemeJson: value.trim()));
  }

  void _loadCustomThemeTemplate() {
    final template = customThemeJsonTemplate(_settings);
    setState(() {
      _customThemeController.text = template;
      _customThemeController.selection = TextSelection.collapsed(
        offset: template.length,
      );
    });
  }

  Future<void> _copyCustomThemeJson() async {
    final value = _customThemeController.text.trim().isEmpty
        ? customThemeJsonTemplate(_settings)
        : _customThemeController.text;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Theme JSON copied.')));
  }

  Future<void> _showInfoDialog({required String title, required String body}) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _labelForThemePreset(AppThemePreset preset) {
    return switch (preset) {
      AppThemePreset.light => 'Light',
      AppThemePreset.dark => 'Dark',
      AppThemePreset.ircap => 'IRCap',
      AppThemePreset.custom => 'Custom',
    };
  }

  String _labelForDensity(MessageDensity density) {
    return switch (density) {
      MessageDensity.compact => 'Compact',
      MessageDensity.comfortable => 'Comfortable',
      MessageDensity.relaxed => 'Relaxed',
    };
  }

  String _labelForNickColorMode(NickColorMode mode) {
    return switch (mode) {
      NickColorMode.none => 'Off',
      NickColorMode.soft => 'Soft',
      NickColorMode.vivid => 'Vivid',
    };
  }

  String _labelForNoticeRouting(NoticeRoutingMode mode) {
    return switch (mode) {
      NoticeRoutingMode.server => 'Server tab',
      NoticeRoutingMode.active => 'Active tab',
      NoticeRoutingMode.notice => 'Notice tab',
      NoticeRoutingMode.private => 'Private query',
    };
  }
}

const String _helpText = '''
Use TLS where the network supports it. SASL PLAIN, SCRAM-SHA-256, and EXTERNAL are negotiated through IRCv3 CAP.

NickServ fallback is only sent when SASL is configured but unavailable, rejected, or incomplete after registration. The fallback uses the SASL account and password and redacts the password from raw logs.

Auto-join channel keys are stored with other network secrets and are redacted from public JSON and raw JOIN logs.

DCC SEND and CHAT run through foreground transfer state. Reverse/passive DCC support depends on the other client and the network path.

SOCKS5 proxy mode sends the IRC host name to the proxy for remote DNS, which is required for Tor-style routing.
''';

const String _privacyText = '''
Network passwords, SASL passwords, proxy passwords, and auto-join channel keys are stored through the configured SecretStorage backend.

IRC messages are sent to the networks you connect to. DCC transfers connect directly to the peer or through reverse/passive negotiation when available.

The app does not include ads, analytics, crash reporting, WebRTC calls, scripting, or E2EE in the current release slice.
''';

const String _supportText = '''
For connection issues, include the network host, port, TLS setting, SASL mechanism, proxy setting, Android version, and the redacted raw server-tab log.

Do not send server passwords, SASL passwords, proxy passwords, channel keys, private keys, or downloaded file paths.
''';

const String _releaseAuditText = '''
Android package: com.androidircx.flutter
Version source: pubspec.yaml

Permissions: INTERNET, ACCESS_NETWORK_STATE, FOREGROUND_SERVICE, FOREGROUND_SERVICE_REMOTE_MESSAGING, POST_NOTIFICATIONS.

Release signing: android/key.properties is used when present. Local builds fall back to debug signing and are not Play Store upload artifacts.

Device smoke gates: background connection runtime, multi-network foreground service, DCC transfer lifetime, notifications, and proxy/Tor connection.
''';

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

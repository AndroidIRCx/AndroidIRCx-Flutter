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

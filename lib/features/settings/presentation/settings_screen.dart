import 'package:androidircx/app/theme/app_theme.dart';
import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/presets/server_preset_service.dart';
import 'package:androidircx/core/settings/app_settings_controller.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:androidircx/features/connections/application/network_list_controller.dart';
import 'package:androidircx/features/connections/presentation/profiles_screen.dart';
import 'package:androidircx/features/connections/presentation/server_directory_picker.dart';
import 'package:androidircx/features/onboarding/presentation/data_privacy_screen.dart';
import 'package:androidircx/features/settings/presentation/backup_screen.dart';
import 'package:androidircx/features/settings/presentation/crash_reports_screen.dart';
import 'package:androidircx/features/settings/presentation/theme_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.repository,
    this.settingsController,
    this.networkController,
    this.presetService,
    this.appLockAuthenticator,
  });

  final SettingsRepository? repository;
  final AppSettingsController? settingsController;

  /// When provided, Settings surfaces a "Server directory" action that adds a
  /// network from the online presets API.
  final NetworkListController? networkController;
  final ServerPresetService? presetService;

  /// Confirms the user can authenticate before app lock is enabled. Overridable
  /// for tests; defaults to a biometric/PIN prompt.
  final Future<bool> Function()? appLockAuthenticator;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _dccDownloadDirectoryController = TextEditingController();
  final _mediaDownloadDirectoryController = TextEditingController();
  final _customThemeController = TextEditingController();
  final _highlightWordsController = TextEditingController();
  final _awayMessageController = TextEditingController();
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
    _highlightWordsController.dispose();
    _awayMessageController.dispose();
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
                    title: 'Connections',
                    children: [
                      if (widget.networkController != null)
                        ListTile(
                          leading: const Icon(Icons.public),
                          title: const Text('Server directory'),
                          subtitle: const Text(
                            'Add a network from the online IRC server list.',
                          ),
                          onTap: () => showServerDirectoryPicker(
                            context,
                            widget.networkController!,
                            presetService: widget.presetService,
                          ),
                        ),
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: const Text('Identity profiles'),
                        subtitle: const Text(
                          'Reusable nick/realname identities to attach to networks.',
                        ),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const ProfilesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                              FilledButton.icon(
                                onPressed: _openThemeEditor,
                                icon: const Icon(Icons.palette_outlined),
                                label: const Text('Visual editor'),
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
                    title: 'Security',
                    children: [
                      SwitchListTile(
                        key: const Key('settings-app-lock'),
                        secondary: const Icon(Icons.lock_outline),
                        title: const Text('App lock'),
                        subtitle: const Text(
                          'Require fingerprint/PIN to open the app.',
                        ),
                        value: _settings.appLockEnabled,
                        onChanged: (value) => _toggleAppLock(value),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('settings-screenshot-protection'),
                        secondary: const Icon(Icons.screenshot_monitor_outlined),
                        title: const Text('Block screenshots'),
                        subtitle: const Text(
                          'Prevent screenshots and screen recording (Android).',
                        ),
                        value: _settings.screenshotProtection,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(screenshotProtection: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Notifications',
                    children: [
                      SwitchListTile(
                        key: const Key('settings-notify-highlights'),
                        title: const Text('Highlights'),
                        subtitle: const Text('Your nick or highlight words.'),
                        value: _settings.notifyHighlights,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(notifyHighlights: value),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('settings-notify-pm'),
                        title: const Text('Private messages'),
                        value: _settings.notifyPrivateMessages,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(notifyPrivateMessages: value),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('settings-notify-dcc'),
                        title: const Text('DCC offers'),
                        value: _settings.notifyDccOffers,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(notifyDccOffers: value),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('settings-notify-errors'),
                        title: const Text('Errors'),
                        value: _settings.notifyErrors,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(notifyErrors: value),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('settings-notify-sound'),
                        title: const Text('Notification sound'),
                        value: _settings.notificationSound,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(notificationSound: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Display',
                    children: [
                      SwitchListTile(
                        key: const Key('settings-hide-jpq'),
                        title: const Text('Hide join/part/quit'),
                        subtitle: const Text(
                          'Hide channel join, part, quit, and nick-change events.',
                        ),
                        value: _settings.hideJoinPartQuit,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(hideJoinPartQuit: value),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('settings-show-timestamps'),
                        title: const Text('Show timestamps'),
                        value: _settings.showTimestamps,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(showTimestamps: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Writing',
                    children: [
                      SwitchListTile(
                        key: const Key('settings-enter-to-send'),
                        title: const Text('Enter key sends'),
                        subtitle: const Text(
                          'When off, Enter inserts a newline; use the Send button.',
                        ),
                        value: _settings.enterToSend,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(enterToSend: value),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('settings-show-send-button'),
                        title: const Text('Show send button'),
                        value: _settings.showSendButton,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(showSendButton: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Highlighting',
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          key: const Key('settings-highlight-words'),
                          controller: _highlightWordsController,
                          decoration: InputDecoration(
                            labelText: 'Highlight words',
                            helperText:
                                'Comma-separated. Notify when a message '
                                'mentions your nick or any of these.',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.save_outlined),
                              onPressed: () => _saveHighlightWords(
                                _highlightWordsController.text,
                              ),
                            ),
                          ),
                          onSubmitted: _saveHighlightWords,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Away',
                    children: [
                      SwitchListTile(
                        key: const Key('settings-auto-away'),
                        title: const Text('Auto-away when idle'),
                        value: _settings.autoAwayEnabled,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(autoAwayEnabled: value),
                        ),
                      ),
                      ListTile(
                        title: const Text('Idle timeout'),
                        trailing: DropdownButton<int>(
                          key: const Key('settings-auto-away-minutes'),
                          value: _settings.autoAwayMinutes,
                          items: const [5, 10, 15, 30, 60]
                              .map(
                                (m) => DropdownMenuItem<int>(
                                  value: m,
                                  child: Text('$m min'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _saveSettings(
                                _settings.copyWith(autoAwayMinutes: value),
                              );
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          key: const Key('settings-away-message'),
                          controller: _awayMessageController,
                          decoration: InputDecoration(
                            labelText: 'Away message',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.save_outlined),
                              onPressed: () => _saveSettings(
                                _settings.copyWith(
                                  awayMessage:
                                      _awayMessageController.text.trim().isEmpty
                                      ? 'Away'
                                      : _awayMessageController.text.trim(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Message history',
                    children: [
                      ListTile(
                        title: const Text('Keep per tab'),
                        subtitle: const Text(
                          'Older encrypted messages are trimmed on load.',
                        ),
                        trailing: DropdownButton<int>(
                          key: const Key('settings-history-retention'),
                          value: _settings.historyRetentionPerTab,
                          items: const [
                            DropdownMenuItem<int>(
                              value: 1000,
                              child: Text('1000'),
                            ),
                            DropdownMenuItem<int>(
                              value: 5000,
                              child: Text('5000'),
                            ),
                            DropdownMenuItem<int>(
                              value: 20000,
                              child: Text('20000'),
                            ),
                            DropdownMenuItem<int>(
                              value: 0,
                              child: Text('Unlimited'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _saveSettings(
                                _settings.copyWith(
                                  historyRetentionPerTab: value,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Channels',
                    children: [
                      SwitchListTile(
                        key: const Key('settings-auto-rejoin'),
                        title: const Text('Auto-rejoin on kick'),
                        subtitle: const Text(
                          'Rejoin a channel automatically after being kicked.',
                        ),
                        value: _settings.autoRejoinOnKick,
                        onChanged: (value) => _saveSettings(
                          _settings.copyWith(autoRejoinOnKick: value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SettingsSection(
                    title: 'Help',
                    children: [
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
                        leading: const Icon(Icons.shield_outlined),
                        title: const Text('Data & privacy'),
                        subtitle: const Text(
                          'How your data is stored and the privacy policy.',
                        ),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const DataPrivacyScreen(),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.backup_outlined),
                        title: const Text('Backup & restore'),
                        subtitle: const Text(
                          'Export or import networks, settings, and profiles.',
                        ),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const BackupScreen(),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('settings-crash-reports'),
                        leading: const Icon(Icons.bug_report_outlined),
                        title: const Text('Crash reports'),
                        subtitle: const Text(
                          'Review and email crash reports to the AndroidIRCX team.',
                        ),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => CrashReportsScreen(),
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
    _setControllerText(
      _highlightWordsController,
      settings.highlightWords.join(', '),
    );
    _setControllerText(_awayMessageController, settings.awayMessage);
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.text = value;
    controller.selection = TextSelection.collapsed(offset: value.length);
  }

  Future<void> _openThemeEditor() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ThemeEditorScreen(
          initialJson: _settings.customThemeJson,
          onSaved: (json) => _saveSettings(
            _settings.copyWith(
              customThemeJson: json,
              themePreset: AppThemePreset.custom,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveHighlightWords(String value) async {
    final words = value
        .split(',')
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    await _saveSettings(_settings.copyWith(highlightWords: words));
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

  Future<bool> _defaultAppLockAuth() async {
    try {
      final auth = LocalAuthentication();
      final supported =
          await auth.isDeviceSupported() || await auth.canCheckBiometrics;
      if (!supported) {
        return false;
      }
      return await auth.authenticate(
        localizedReason: 'Confirm your fingerprint or PIN to enable app lock',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _toggleAppLock(bool value) async {
    // Turning off is immediate. Turning on first confirms the user can actually
    // authenticate, so enabling it can never lock them out of the app.
    if (!value) {
      await _saveSettings(_settings.copyWith(appLockEnabled: false));
      return;
    }
    final confirmed =
        await (widget.appLockAuthenticator ?? _defaultAppLockAuth)();
    if (!mounted) {
      return;
    }
    if (!confirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'App lock not enabled: could not verify fingerprint or PIN. '
            'Set up a screen lock on your device first.',
          ),
        ),
      );
      return;
    }
    await _saveSettings(_settings.copyWith(appLockEnabled: true));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('App lock enabled. It will lock when you leave the app.'),
      ),
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

const String _privacyText = '''
Network passwords, SASL passwords, proxy passwords, and auto-join channel keys are stored through the configured SecretStorage backend.

IRC messages are sent to the networks you connect to. DCC transfers connect directly to the peer or through reverse/passive negotiation when available.

The app does not include ads, analytics, crash reporting, WebRTC calls, scripting, or E2EE in the current release slice.
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

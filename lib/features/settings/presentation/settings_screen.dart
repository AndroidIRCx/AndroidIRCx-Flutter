import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repository = SharedPrefsSettingsRepository();
  final _dccDownloadDirectoryController = TextEditingController();
  final _mediaDownloadDirectoryController = TextEditingController();
  AppSettings _settings = const AppSettings();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dccDownloadDirectoryController.dispose();
    _mediaDownloadDirectoryController.dispose();
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
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Show raw IRC events'),
                          subtitle: const Text(
                            'Keep low-level IRC send/receive lines visible in the server tab.',
                          ),
                          value: _settings.showRawEvents,
                          onChanged: (value) async {
                            final next = _settings.copyWith(
                              showRawEvents: value,
                            );
                            setState(() => _settings = next);
                            await _repository.saveSettings(next);
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
                            final next = _settings.copyWith(
                              showHeaderSearchButton: value,
                            );
                            setState(() => _settings = next);
                            await _repository.saveSettings(next);
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
                            final next = _settings.copyWith(
                              showAttachmentPreviews: value,
                            );
                            setState(() => _settings = next);
                            await _repository.saveSettings(next);
                          },
                        ),
                        const Divider(height: 1),
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

                              final next = _settings.copyWith(
                                noticeRouting: value,
                              );
                              setState(() => _settings = next);
                              await _repository.saveSettings(next);
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
      _dccDownloadDirectoryController.text = settings.dccDownloadDirectoryPath;
      _mediaDownloadDirectoryController.text =
          settings.mediaDownloadDirectoryPath;
      _isLoading = false;
    });
  }

  Future<void> _saveDccDownloadDirectory(String value) async {
    final normalized = value.trim();
    final next = _settings.copyWith(dccDownloadDirectoryPath: normalized);
    setState(() {
      _settings = next;
      _dccDownloadDirectoryController.text = normalized;
      _dccDownloadDirectoryController.selection = TextSelection.collapsed(
        offset: normalized.length,
      );
    });
    await _repository.saveSettings(next);
  }

  Future<void> _saveMediaDownloadDirectory(String value) async {
    final normalized = value.trim();
    final next = _settings.copyWith(mediaDownloadDirectoryPath: normalized);
    setState(() {
      _settings = next;
      _mediaDownloadDirectoryController.text = normalized;
      _mediaDownloadDirectoryController.selection = TextSelection.collapsed(
        offset: normalized.length,
      );
    });
    await _repository.saveSettings(next);
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

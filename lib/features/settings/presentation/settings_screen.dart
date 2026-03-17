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
  AppSettings _settings = const AppSettings();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
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
                            final next = _settings.copyWith(showRawEvents: value);
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
                            final next = _settings.copyWith(showHeaderSearchButton: value);
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
                            final next = _settings.copyWith(showAttachmentPreviews: value);
                            setState(() => _settings = next);
                            await _repository.saveSettings(next);
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

                              final next = _settings.copyWith(noticeRouting: value);
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
      _isLoading = false;
    });
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

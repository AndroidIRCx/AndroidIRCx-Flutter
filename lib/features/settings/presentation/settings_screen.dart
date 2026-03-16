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
                    child: SwitchListTile(
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
}

import 'package:androidircx/core/sound/sound_service.dart';
import 'package:flutter/material.dart';

/// Per-event notification sound settings with preview playback.
class SoundSettingsScreen extends StatefulWidget {
  const SoundSettingsScreen({super.key, this.service});

  /// Overridable for tests; defaults to the app-wide [SoundScope] service.
  final SoundService? service;

  @override
  State<SoundSettingsScreen> createState() => _SoundSettingsScreenState();
}

class _SoundSettingsScreenState extends State<SoundSettingsScreen> {
  SoundService? _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final resolved = widget.service ?? SoundScope.maybeOf(context);
    if (identical(resolved, _service)) {
      return;
    }
    _service?.removeListener(_onServiceChanged);
    _service = resolved;
    _service?.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sounds')),
        body: const Center(child: Text('Sound service unavailable.')),
      );
    }
    final settings = service.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Sounds')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              key: const Key('sound-settings-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Event sounds'),
              subtitle: const Text('Play short sounds for IRC events.'),
              value: settings.enabled,
              onChanged: (value) =>
                  service.updateSettings(settings.copyWith(enabled: value)),
            ),
            if (settings.enabled) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Volume',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Slider(
                key: const Key('sound-settings-volume'),
                value: settings.masterVolume,
                divisions: 10,
                label: '${(settings.masterVolume * 100).round()}%',
                onChanged: (value) => service.updateSettings(
                  settings.copyWith(masterVolume: value),
                ),
              ),
              const Divider(),
              for (final event in SoundEvent.values)
                SwitchListTile(
                  key: Key('sound-settings-event-${event.name}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(soundEventLabels[event] ?? event.name),
                  value: settings.isEventEnabled(event),
                  onChanged: (value) =>
                      service.updateSettings(settings.withEvent(event, value)),
                  secondary: IconButton(
                    key: Key('sound-settings-preview-${event.name}'),
                    tooltip: 'Play sound',
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () => service.previewEvent(event),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

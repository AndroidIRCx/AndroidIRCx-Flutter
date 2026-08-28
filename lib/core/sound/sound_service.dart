import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Event types that can trigger a notification sound. Mirrors the previous
/// app's sound events, minus ones with no trigger in this client yet.
enum SoundEvent {
  mention,
  privateMessage,
  notice,
  join,
  kick,
  ctcp,
  disconnect,
  login,
  send,
  fail,
  ring,
}

const Map<SoundEvent, String> soundEventLabels = {
  SoundEvent.mention: 'Mention / highlight',
  SoundEvent.privateMessage: 'Private message',
  SoundEvent.notice: 'Notice',
  SoundEvent.join: 'User join',
  SoundEvent.kick: 'Kicked from channel',
  SoundEvent.ctcp: 'CTCP request',
  SoundEvent.disconnect: 'Disconnected',
  SoundEvent.login: 'Connected',
  SoundEvent.send: 'Message sent',
  SoundEvent.fail: 'Error',
  SoundEvent.ring: 'DCC offer',
};

/// Asset filename for each event (bundled under assets/sounds/).
const Map<SoundEvent, String> soundEventAssets = {
  SoundEvent.mention: 'cuac.wav',
  SoundEvent.privateMessage: 'bip.wav',
  SoundEvent.notice: 'notice.wav',
  SoundEvent.join: 'join.wav',
  SoundEvent.kick: 'kick.wav',
  SoundEvent.ctcp: 'ctcp.wav',
  SoundEvent.disconnect: 'disconnected.wav',
  SoundEvent.login: 'login.wav',
  SoundEvent.send: 'send.wav',
  SoundEvent.fail: 'fail.wav',
  SoundEvent.ring: 'ring.wav',
};

/// Events that make noise out of the box; the rest stay opt-in.
const Set<SoundEvent> _defaultEnabledEvents = {
  SoundEvent.mention,
  SoundEvent.privateMessage,
  SoundEvent.disconnect,
  SoundEvent.login,
  SoundEvent.ring,
};

class SoundSettings {
  const SoundSettings({
    this.enabled = true,
    this.masterVolume = 0.7,
    this.eventEnabled = const <SoundEvent, bool>{},
  });

  /// Global sound switch.
  final bool enabled;

  /// 0.0–1.0 volume applied to every event sound.
  final double masterVolume;

  /// Per-event overrides; events absent from the map use their default.
  final Map<SoundEvent, bool> eventEnabled;

  bool isEventEnabled(SoundEvent event) {
    return eventEnabled[event] ?? _defaultEnabledEvents.contains(event);
  }

  SoundSettings copyWith({
    bool? enabled,
    double? masterVolume,
    Map<SoundEvent, bool>? eventEnabled,
  }) {
    return SoundSettings(
      enabled: enabled ?? this.enabled,
      masterVolume: (masterVolume ?? this.masterVolume).clamp(0.0, 1.0),
      eventEnabled: eventEnabled ?? this.eventEnabled,
    );
  }

  SoundSettings withEvent(SoundEvent event, bool value) {
    return copyWith(eventEnabled: {...eventEnabled, event: value});
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'masterVolume': masterVolume,
      'events': {
        for (final entry in eventEnabled.entries) entry.key.name: entry.value,
      },
    };
  }

  factory SoundSettings.fromJson(Map<String, Object?> json) {
    final rawEvents = json['events'];
    final events = <SoundEvent, bool>{};
    if (rawEvents is Map) {
      rawEvents.forEach((key, value) {
        if (key is! String || value is! bool) {
          return;
        }
        for (final event in SoundEvent.values) {
          if (event.name == key) {
            events[event] = value;
          }
        }
      });
    }
    return SoundSettings(
      enabled: (json['enabled'] as bool?) ?? true,
      masterVolume: ((json['masterVolume'] as num?)?.toDouble() ?? 0.7).clamp(
        0.0,
        1.0,
      ),
      eventEnabled: events,
    );
  }
}

/// Playback backend; the production implementation uses `audioplayers`,
/// tests inject a fake.
abstract class SoundPlayer {
  Future<void> play(String assetPath, double volume);
}

/// Plays short event sounds per user settings; persists settings in
/// shared preferences.
class SoundService extends ChangeNotifier {
  SoundService({required SoundPlayer player, this.storageKey = 'soundSettings'})
    : _player = player;

  final SoundPlayer _player;
  final String storageKey;

  SoundSettings _settings = const SoundSettings();
  bool _loaded = false;

  SoundSettings get settings => _settings;

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        _settings = SoundSettings.fromJson(decoded);
        notifyListeners();
      }
    } catch (_) {
      // Corrupt settings fall back to defaults.
    }
  }

  Future<void> updateSettings(SoundSettings next) async {
    _settings = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(next.toJson()));
  }

  /// Plays the sound for [event] if sounds and the event are enabled.
  /// Never throws: sound failures must not break message handling.
  Future<void> playEvent(SoundEvent event) async {
    if (!_settings.enabled ||
        _settings.masterVolume <= 0 ||
        !_settings.isEventEnabled(event)) {
      return;
    }
    await _playAsset(soundEventAssets[event]!);
  }

  /// Plays [event]'s sound unconditionally (settings preview).
  Future<void> previewEvent(SoundEvent event) {
    return _playAsset(soundEventAssets[event]!);
  }

  Future<void> _playAsset(String fileName) async {
    try {
      await _player.play('sounds/$fileName', _settings.masterVolume);
    } catch (_) {
      // Missing/undecodable asset or platform audio failure: stay silent.
    }
  }
}

/// Shares one [SoundService] between chat sessions and the settings UI.
class SoundScope extends InheritedNotifier<SoundService> {
  const SoundScope({
    super.key,
    required SoundService service,
    required super.child,
  }) : super(notifier: service);

  static SoundService? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SoundScope>()?.notifier;
  }
}

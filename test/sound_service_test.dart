import 'package:androidircx/core/sound/sound_service.dart';
import 'package:androidircx/features/settings/presentation/sound_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingPlayer implements SoundPlayer {
  final List<({String asset, double volume})> played = [];

  @override
  Future<void> play(String assetPath, double volume) async {
    played.add((asset: assetPath, volume: volume));
  }
}

class _ThrowingPlayer implements SoundPlayer {
  @override
  Future<void> play(String assetPath, double volume) async {
    throw StateError('audio backend unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SoundSettings', () {
    test('defaults enable the common events only', () {
      const settings = SoundSettings();
      expect(settings.isEventEnabled(SoundEvent.mention), isTrue);
      expect(settings.isEventEnabled(SoundEvent.privateMessage), isTrue);
      expect(settings.isEventEnabled(SoundEvent.login), isTrue);
      expect(settings.isEventEnabled(SoundEvent.disconnect), isTrue);
      expect(settings.isEventEnabled(SoundEvent.ring), isTrue);
      expect(settings.isEventEnabled(SoundEvent.join), isFalse);
      expect(settings.isEventEnabled(SoundEvent.send), isFalse);
    });

    test('round-trips through JSON including event overrides', () {
      const settings = SoundSettings(enabled: false, masterVolume: 0.4);
      final overridden = settings
          .withEvent(SoundEvent.join, true)
          .withEvent(SoundEvent.mention, false);
      final restored = SoundSettings.fromJson(overridden.toJson());
      expect(restored.enabled, isFalse);
      expect(restored.masterVolume, closeTo(0.4, 0.0001));
      expect(restored.isEventEnabled(SoundEvent.join), isTrue);
      expect(restored.isEventEnabled(SoundEvent.mention), isFalse);
      // Untouched events keep their defaults.
      expect(restored.isEventEnabled(SoundEvent.privateMessage), isTrue);
    });

    test('every event has a bundled asset and a label', () {
      for (final event in SoundEvent.values) {
        expect(soundEventAssets[event], isNotNull, reason: event.name);
        expect(soundEventLabels[event], isNotNull, reason: event.name);
      }
    });
  });

  group('SoundService', () {
    test('plays enabled events at master volume', () async {
      final player = _RecordingPlayer();
      final service = SoundService(player: player);

      await service.playEvent(SoundEvent.mention);

      expect(player.played, hasLength(1));
      expect(player.played.single.asset, 'sounds/cuac.wav');
      expect(player.played.single.volume, closeTo(0.7, 0.0001));
    });

    test('skips disabled events, muted volume, and global off', () async {
      final player = _RecordingPlayer();
      final service = SoundService(player: player);

      // join is disabled by default.
      await service.playEvent(SoundEvent.join);
      expect(player.played, isEmpty);

      await service.updateSettings(service.settings.copyWith(masterVolume: 0));
      await service.playEvent(SoundEvent.mention);
      expect(player.played, isEmpty);

      await service.updateSettings(
        service.settings.copyWith(enabled: false, masterVolume: 1),
      );
      await service.playEvent(SoundEvent.mention);
      expect(player.played, isEmpty);
    });

    test('persists and reloads settings', () async {
      final service = SoundService(player: _RecordingPlayer());
      await service.updateSettings(
        service.settings
            .copyWith(masterVolume: 0.3)
            .withEvent(SoundEvent.send, true),
      );

      final reloaded = SoundService(player: _RecordingPlayer());
      await reloaded.load();
      expect(reloaded.settings.masterVolume, closeTo(0.3, 0.0001));
      expect(reloaded.settings.isEventEnabled(SoundEvent.send), isTrue);
    });

    test('player failures never propagate', () async {
      final service = SoundService(player: _ThrowingPlayer());
      await service.playEvent(SoundEvent.mention);
      await service.previewEvent(SoundEvent.mention);
    });
  });

  group('SoundSettingsScreen', () {
    testWidgets('toggles events and previews sounds', (tester) async {
      final player = _RecordingPlayer();
      final service = SoundService(player: player);

      await tester.pumpWidget(
        MaterialApp(home: SoundSettingsScreen(service: service)),
      );

      await tester.tap(find.byKey(const Key('sound-settings-preview-mention')));
      await tester.pump();
      expect(player.played, hasLength(1));

      // join defaults to off; enable it via the switch.
      await tester.scrollUntilVisible(
        find.byKey(const Key('sound-settings-event-join')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('sound-settings-event-join')));
      await tester.pumpAndSettle();
      expect(service.settings.isEventEnabled(SoundEvent.join), isTrue);

      // Global switch hides the per-event list.
      await tester.scrollUntilVisible(
        find.byKey(const Key('sound-settings-enabled')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('sound-settings-enabled')));
      await tester.pumpAndSettle();
      expect(service.settings.enabled, isFalse);
      expect(find.byKey(const Key('sound-settings-event-join')), findsNothing);
    });
  });
}

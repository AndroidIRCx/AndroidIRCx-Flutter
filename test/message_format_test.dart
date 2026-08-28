import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/features/chat/presentation/message_line_format.dart';
import 'package:androidircx/features/settings/presentation/message_format_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatIrcTimestamp', () {
    final afternoon = DateTime(2026, 1, 1, 13, 5, 9);
    final midnight = DateTime(2026, 1, 1, 0, 5, 9);
    final noon = DateTime(2026, 1, 1, 12, 5, 9);

    test('formats 24-hour patterns', () {
      expect(formatIrcTimestamp(afternoon, 'HH:mm'), '13:05');
      expect(formatIrcTimestamp(afternoon, 'HH:mm:ss'), '13:05:09');
    });

    test('formats 12-hour patterns with midnight/noon edges', () {
      expect(formatIrcTimestamp(afternoon, 'h:mm a'), '1:05 PM');
      expect(formatIrcTimestamp(afternoon, 'h:mm:ss a'), '1:05:09 PM');
      expect(formatIrcTimestamp(midnight, 'h:mm a'), '12:05 AM');
      expect(formatIrcTimestamp(noon, 'h:mm a'), '12:05 PM');
    });

    test('unknown pattern falls back to 24-hour HH:mm', () {
      expect(formatIrcTimestamp(afternoon, 'bogus'), '13:05');
    });
  });

  group('formatNickLabel', () {
    test('applies each decoration style', () {
      expect(formatNickLabel('alice', NickDisplayFormat.plain), 'alice');
      expect(formatNickLabel('alice', NickDisplayFormat.angle), '<alice>');
      expect(formatNickLabel('alice', NickDisplayFormat.colon), 'alice:');
      expect(formatNickLabel('alice', NickDisplayFormat.bracket), '[alice]');
    });
  });

  group('AppSettings message format fields', () {
    test('round-trip through JSON', () {
      const settings = AppSettings(
        timestampFormat: 'h:mm a',
        timestampPosition: TimestampPosition.beforeNick,
        nickDisplayFormat: NickDisplayFormat.angle,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.timestampFormat, 'h:mm a');
      expect(restored.timestampPosition, TimestampPosition.beforeNick);
      expect(restored.nickDisplayFormat, NickDisplayFormat.angle);
    });

    test('missing JSON fields keep defaults', () {
      final restored = AppSettings.fromJson(const <String, Object?>{});
      expect(restored.timestampFormat, 'HH:mm');
      expect(restored.timestampPosition, TimestampPosition.afterNick);
      expect(restored.nickDisplayFormat, NickDisplayFormat.plain);
    });
  });

  group('MessageFormatScreen', () {
    testWidgets('edits timestamp and nick style with live preview', (
      tester,
    ) async {
      var settings = const AppSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: MessageFormatScreen(
            initialSettings: settings,
            onSettingsChanged: (next) => settings = next,
          ),
        ),
      );

      // Preview renders the default nick style and 24-hour clock.
      expect(find.text('Message format'), findsOneWidget);
      expect(find.textContaining('alice', findRichText: true), findsWidgets);

      await tester.tap(
        find.byKey(const Key('message-format-timestamp-format')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('12-hour (1:05 PM)').last);
      await tester.pumpAndSettle();
      expect(settings.timestampFormat, 'h:mm a');

      await tester.tap(
        find.byKey(const Key('message-format-timestamp-position')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Before nick').last);
      await tester.pumpAndSettle();
      expect(settings.timestampPosition, TimestampPosition.beforeNick);

      await tester.tap(find.byKey(const Key('message-format-nick-style')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('<nick>').last);
      await tester.pumpAndSettle();
      expect(settings.nickDisplayFormat, NickDisplayFormat.angle);

      // Hiding timestamps removes the format/position controls.
      await tester.tap(find.byKey(const Key('message-format-show-timestamps')));
      await tester.pumpAndSettle();
      expect(settings.showTimestamps, isFalse);
      expect(
        find.byKey(const Key('message-format-timestamp-format')),
        findsNothing,
      );
    });
  });
}

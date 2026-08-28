import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/features/chat/presentation/message_line_format.dart';
import 'package:flutter/material.dart';

/// Visual editor for how message lines are laid out: timestamp format and
/// position, plus sender nick decoration. Changes save immediately through
/// [onSettingsChanged] and the preview updates live.
class MessageFormatScreen extends StatefulWidget {
  const MessageFormatScreen({
    super.key,
    required this.initialSettings,
    required this.onSettingsChanged,
  });

  final AppSettings initialSettings;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<MessageFormatScreen> createState() => _MessageFormatScreenState();
}

class _MessageFormatScreenState extends State<MessageFormatScreen> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void _update(AppSettings next) {
    setState(() => _settings = next);
    widget.onSettingsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Message format')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Preview', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _MessageFormatPreview(settings: _settings),
            const SizedBox(height: 16),
            SwitchListTile(
              key: const Key('message-format-show-timestamps'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Show timestamps'),
              value: _settings.showTimestamps,
              onChanged: (value) =>
                  _update(_settings.copyWith(showTimestamps: value)),
            ),
            if (_settings.showTimestamps) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Timestamp format'),
                trailing: DropdownButton<String>(
                  key: const Key('message-format-timestamp-format'),
                  value:
                      supportedTimestampFormats.any(
                        (option) => option.pattern == _settings.timestampFormat,
                      )
                      ? _settings.timestampFormat
                      : 'HH:mm',
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    _update(_settings.copyWith(timestampFormat: value));
                  },
                  items: supportedTimestampFormats
                      .map(
                        (option) => DropdownMenuItem(
                          value: option.pattern,
                          child: Text(option.label),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Timestamp position'),
                trailing: DropdownButton<TimestampPosition>(
                  key: const Key('message-format-timestamp-position'),
                  value: _settings.timestampPosition,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    _update(_settings.copyWith(timestampPosition: value));
                  },
                  items: TimestampPosition.values
                      .map(
                        (position) => DropdownMenuItem(
                          value: position,
                          child: Text(timestampPositionLabel(position)),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nick style'),
              subtitle: const Text('Decoration around sender names.'),
              trailing: DropdownButton<NickDisplayFormat>(
                key: const Key('message-format-nick-style'),
                value: _settings.nickDisplayFormat,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  _update(_settings.copyWith(nickDisplayFormat: value));
                },
                items: NickDisplayFormat.values
                    .map(
                      (format) => DropdownMenuItem(
                        value: format,
                        child: Text(nickDisplayFormatLabel(format)),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageFormatPreview extends StatelessWidget {
  const _MessageFormatPreview({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sampleTime = DateTime(2026, 1, 1, 13, 5, 9);
    final nickStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.primary,
    );
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    List<InlineSpan> lineSpans(String nick, String message) {
      final timeSpan = settings.showTimestamps
          ? TextSpan(
              text: formatIrcTimestamp(sampleTime, settings.timestampFormat),
              style: metaStyle,
            )
          : null;
      final nickSpan = TextSpan(
        text: formatNickLabel(nick, settings.nickDisplayFormat),
        style: nickStyle,
      );
      return [
        if (timeSpan != null &&
            settings.timestampPosition == TimestampPosition.beforeNick) ...[
          timeSpan,
          const TextSpan(text: '  '),
        ],
        nickSpan,
        if (timeSpan != null &&
            settings.timestampPosition == TimestampPosition.afterNick) ...[
          const TextSpan(text: '  '),
          timeSpan,
        ],
        const TextSpan(text: '   '),
        TextSpan(text: message, style: theme.textTheme.bodyMedium),
      ];
    }

    return Container(
      key: const Key('message-format-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: lineSpans('alice', 'Hello there!'))),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: lineSpans('bob', 'hi alice, welcome back')),
          ),
        ],
      ),
    );
  }
}

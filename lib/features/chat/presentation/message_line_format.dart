import 'package:androidircx/core/models/app_settings.dart';

/// Timestamp patterns offered in the message format editor.
const List<({String pattern, String label})> supportedTimestampFormats = [
  (pattern: 'HH:mm', label: '24-hour (13:05)'),
  (pattern: 'HH:mm:ss', label: '24-hour with seconds (13:05:09)'),
  (pattern: 'h:mm a', label: '12-hour (1:05 PM)'),
  (pattern: 'h:mm:ss a', label: '12-hour with seconds (1:05:09 PM)'),
];

/// Formats [timestamp] (converted to local time) with one of the supported
/// patterns; unknown patterns fall back to 24-hour HH:mm.
String formatIrcTimestamp(DateTime timestamp, String pattern) {
  final local = timestamp.toLocal();
  final hh24 = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final ss = local.second.toString().padLeft(2, '0');
  final hour12 = switch (local.hour % 12) {
    0 => 12,
    final hour => hour,
  };
  final period = local.hour < 12 ? 'AM' : 'PM';
  return switch (pattern) {
    'HH:mm:ss' => '$hh24:$mm:$ss',
    'h:mm a' => '$hour12:$mm $period',
    'h:mm:ss a' => '$hour12:$mm:$ss $period',
    _ => '$hh24:$mm',
  };
}

/// Decorates a sender nick for display per the configured style.
String formatNickLabel(String nick, NickDisplayFormat format) {
  return switch (format) {
    NickDisplayFormat.plain => nick,
    NickDisplayFormat.angle => '<$nick>',
    NickDisplayFormat.colon => '$nick:',
    NickDisplayFormat.bracket => '[$nick]',
  };
}

String nickDisplayFormatLabel(NickDisplayFormat format) {
  return switch (format) {
    NickDisplayFormat.plain => 'nick',
    NickDisplayFormat.angle => '<nick>',
    NickDisplayFormat.colon => 'nick:',
    NickDisplayFormat.bracket => '[nick]',
  };
}

String timestampPositionLabel(TimestampPosition position) {
  return switch (position) {
    TimestampPosition.afterNick => 'After nick',
    TimestampPosition.beforeNick => 'Before nick',
  };
}

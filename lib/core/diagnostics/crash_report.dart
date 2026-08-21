import 'dart:convert';

/// A single captured crash / uncaught-error record, already sanitized of any
/// credentials. Stored locally and, only if the user chooses, emailed as a
/// plaintext report. Nothing is ever sent automatically.
class CrashReport {
  const CrashReport({
    required this.timestamp,
    required this.fatal,
    required this.source,
    required this.message,
    required this.stack,
    this.platform,
  });

  /// When the error was captured (UTC ISO-8601).
  final DateTime timestamp;

  /// Whether the error was fatal (uncaught) rather than a handled report.
  final bool fatal;

  /// Where it came from, e.g. `FlutterError.onError`, `PlatformDispatcher`,
  /// `zone`, or a feature name.
  final String source;

  /// Sanitized error message.
  final String message;

  /// Sanitized stack trace (may be empty).
  final String stack;

  /// Optional platform description (e.g. `android`).
  final String? platform;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'fatal': fatal,
    'source': source,
    'message': message,
    'stack': stack,
    if (platform != null) 'platform': platform,
  };

  static CrashReport fromJson(Map<String, dynamic> json) => CrashReport(
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    fatal: json['fatal'] as bool? ?? true,
    source: json['source'] as String? ?? 'unknown',
    message: json['message'] as String? ?? '',
    stack: json['stack'] as String? ?? '',
    platform: json['platform'] as String?,
  );

  String encode() => jsonEncode(toJson());

  static CrashReport? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return fromJson(decoded);
      }
    } catch (_) {
      // Ignore malformed entries.
    }
    return null;
  }

  /// Human-readable plaintext body for the crash email / on-screen preview.
  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln('AndroidIRCX crash report')
      ..writeln('Time: ${timestamp.toUtc().toIso8601String()}')
      ..writeln('Fatal: $fatal')
      ..writeln('Source: $source');
    if (platform != null) {
      buffer.writeln('Platform: $platform');
    }
    buffer
      ..writeln()
      ..writeln('Message:')
      ..writeln(message);
    if (stack.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Stack:')
        ..writeln(stack);
    }
    return buffer.toString();
  }
}

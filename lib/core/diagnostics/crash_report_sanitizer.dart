/// Redacts credentials and other secrets from crash text before it is stored
/// or leaves the device. Ported from the React Native `ErrorReportingService`
/// sanitizer: IRC auth commands, generic password/token key-values, PEM blocks
/// and long opaque tokens are replaced with `[redacted]`.
class CrashReportSanitizer {
  const CrashReportSanitizer();

  static const String redaction = '[redacted]';

  /// IRC/auth verbs whose trailing argument is a secret (case-insensitive).
  /// The verb is kept, the value is redacted.
  static final RegExp _authCommand = RegExp(
    r'\b(PASS|AUTHENTICATE|OPER|IDENTIFY|NICKSERV|NS)\b[ \t]+(?![:#&])(\S+)',
    caseSensitive: false,
  );

  /// `password: xxx`, `token=xxx`, `secret "xxx"`, `apikey => xxx`, etc.
  static final RegExp _keyValue = RegExp(
    r'\b(password|passwd|pass|token|secret|sasl|oauth|apikey|api_key|authorization|bearer|cert|key)\b'
    r'''[ \t]*[:=]{1,2}[ \t]*["'`]?([^\s"'`,;)]+)''',
    caseSensitive: false,
  );

  /// PEM private-key / certificate blocks.
  static final RegExp _pemBlock = RegExp(
    r'-----BEGIN [A-Z ]+-----[\s\S]*?-----END [A-Z ]+-----',
  );

  /// Long opaque tokens (base64/hex-ish runs of 40+ chars).
  static final RegExp _longToken = RegExp(r'\b[A-Za-z0-9+/=_-]{40,}\b');

  String sanitize(String input) {
    if (input.isEmpty) {
      return input;
    }
    var out = input;
    out = out.replaceAll(_pemBlock, redaction);
    out = out.replaceAllMapped(
      _authCommand,
      (m) => '${m.group(1)} $redaction',
    );
    out = out.replaceAllMapped(
      _keyValue,
      (m) => '${m.group(1)}=$redaction',
    );
    out = out.replaceAll(_longToken, redaction);
    return out;
  }
}

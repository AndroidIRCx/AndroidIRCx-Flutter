import 'dart:convert';

import 'package:enough_convert/enough_convert.dart';

/// Character-encoding support for IRC traffic.
///
/// IRC is a byte protocol with no in-band charset negotiation, so different
/// networks/users send text in different legacy encodings (ISO-8859-*,
/// Windows-125x, KOI8, ...). Incoming line bytes are decoded and outgoing
/// lines encoded using a per-network encoding, with an optional "prefer
/// UTF-8, fall back to legacy" mode for mixed channels.
///
/// Decoding is done per complete IRC line (bytes are split on LF before
/// decoding), so no streaming state is needed and multi-byte characters never
/// straddle a chunk boundary — all supported encodings keep 0x0A/0x0D as
/// ASCII control bytes.
const String defaultIrcEncoding = 'utf-8';

class IrcEncodingOption {
  const IrcEncodingOption(this.label, this.name);

  /// Canonical lower-case label (also what we persist).
  final String label;

  /// Human-readable name shown in settings.
  final String name;
}

/// Curated list of encodings offered in the UI, ordered by how common they
/// are on IRC. `utf-8` is the modern default; the rest are legacy charsets
/// still used on older networks and by older clients.
const List<IrcEncodingOption> supportedIrcEncodings = <IrcEncodingOption>[
  IrcEncodingOption('utf-8', 'UTF-8 (Unicode)'),
  IrcEncodingOption('iso-8859-1', 'Western (ISO-8859-1)'),
  IrcEncodingOption('iso-8859-15', 'Western (ISO-8859-15)'),
  IrcEncodingOption('windows-1252', 'Western (Windows-1252)'),
  IrcEncodingOption('iso-8859-2', 'Central European (ISO-8859-2)'),
  IrcEncodingOption('windows-1250', 'Central European (Windows-1250)'),
  IrcEncodingOption('windows-1251', 'Cyrillic (Windows-1251)'),
  IrcEncodingOption('koi8-r', 'Cyrillic (KOI8-R)'),
  IrcEncodingOption('koi8-u', 'Cyrillic (KOI8-U)'),
  IrcEncodingOption('iso-8859-5', 'Cyrillic (ISO-8859-5)'),
  IrcEncodingOption('iso-8859-7', 'Greek (ISO-8859-7)'),
  IrcEncodingOption('windows-1253', 'Greek (Windows-1253)'),
  IrcEncodingOption('iso-8859-9', 'Turkish (ISO-8859-9)'),
  IrcEncodingOption('windows-1254', 'Turkish (Windows-1254)'),
  IrcEncodingOption('iso-8859-13', 'Baltic (ISO-8859-13)'),
  IrcEncodingOption('windows-1256', 'Arabic (Windows-1256)'),
  IrcEncodingOption('gbk', 'Chinese Simplified (GBK)'),
  IrcEncodingOption('big5', 'Chinese Traditional (Big5)'),
];

final Set<String> _supportedLabels = supportedIrcEncodings
    .map((option) => option.label)
    .toSet();

/// Normalizes a persisted label to a canonical, lower-case supported form.
String normalizeIrcEncoding(String? label) {
  final value = (label ?? defaultIrcEncoding).toLowerCase().trim();
  return _supportedLabels.contains(value) ? value : defaultIrcEncoding;
}

/// Display name for a label (falls back to the normalized label).
String ircEncodingDisplayName(String? label) {
  final normalized = normalizeIrcEncoding(label);
  for (final option in supportedIrcEncodings) {
    if (option.label == normalized) {
      return option.name;
    }
  }
  return normalized;
}

Encoding? _legacyCodec(String normalizedLabel) {
  return switch (normalizedLabel) {
    'iso-8859-1' => const Latin1Codec(allowInvalid: true),
    'iso-8859-2' => const Latin2Codec(allowInvalid: true),
    'iso-8859-5' => const Latin5Codec(allowInvalid: true),
    'iso-8859-7' => const Latin7Codec(allowInvalid: true),
    'iso-8859-9' => const Latin9Codec(allowInvalid: true),
    'iso-8859-13' => const Latin13Codec(allowInvalid: true),
    'iso-8859-15' => const Latin15Codec(allowInvalid: true),
    'windows-1250' => const Windows1250Codec(allowInvalid: true),
    'windows-1251' => const Windows1251Codec(allowInvalid: true),
    'windows-1252' => const Windows1252Codec(allowInvalid: true),
    'windows-1253' => const Windows1253Codec(allowInvalid: true),
    'windows-1254' => const Windows1254Codec(allowInvalid: true),
    'windows-1256' => const Windows1256Codec(allowInvalid: true),
    'koi8-r' => const Koi8rCodec(allowInvalid: true),
    'koi8-u' => const Koi8uCodec(allowInvalid: true),
    'gbk' => const GbkCodec(allowInvalid: true),
    'big5' => const Big5Codec(allowInvalid: true),
    _ => null,
  };
}

/// Decodes the bytes of a single IRC line (without the trailing CRLF).
///
/// When [utf8Fallback] is true and [encoding] is a legacy charset, the line is
/// decoded as UTF-8 first and only falls back to the legacy charset if the
/// bytes are not valid UTF-8. Ignored for `utf-8`.
String decodeIrcLine(
  List<int> bytes, {
  String encoding = defaultIrcEncoding,
  bool utf8Fallback = false,
}) {
  final normalized = normalizeIrcEncoding(encoding);
  if (normalized == defaultIrcEncoding) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  if (utf8Fallback) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Not valid UTF-8 — decode this line with the legacy charset instead.
    }
  }
  final codec = _legacyCodec(normalized);
  if (codec == null) {
    return utf8.decode(bytes, allowMalformed: true);
  }
  return codec.decode(bytes);
}

/// Encodes an outgoing IRC line for the wire.
///
/// Returns legacy bytes, or `null` when the caller should use the plain
/// UTF-8 string write path (encoding is `utf-8`, or [utf8Fallback] prefers
/// sending UTF-8). Returning null keeps the common UTF-8 path byte-identical
/// to the previous behavior.
List<int>? encodeIrcLine(
  String line, {
  String encoding = defaultIrcEncoding,
  bool utf8Fallback = false,
}) {
  final normalized = normalizeIrcEncoding(encoding);
  if (normalized == defaultIrcEncoding || utf8Fallback) {
    return null;
  }
  final codec = _legacyCodec(normalized);
  if (codec == null) {
    return null;
  }
  try {
    return codec.encode(line);
  } on FormatException {
    // Unencodable line — fall back to UTF-8 rather than dropping the send.
    return null;
  }
}

/// Splits raw socket bytes into per-line byte lists on LF, stripping a
/// trailing CR. All supported encodings keep 0x0A and 0x0D as ASCII control
/// bytes, so line splitting is safe before decoding and decoding a whole line
/// keeps multi-byte characters intact.
class IrcByteLineSplitter {
  final List<int> _buffer = <int>[];

  /// Adds [chunk] and returns every complete line's bytes (without CRLF).
  List<List<int>> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final lines = <List<int>>[];
    var start = 0;
    while (true) {
      final newlineIndex = _buffer.indexOf(0x0a, start);
      if (newlineIndex == -1) {
        break;
      }
      var end = newlineIndex;
      if (end > start && _buffer[end - 1] == 0x0d) {
        end -= 1;
      }
      lines.add(_buffer.sublist(start, end));
      start = newlineIndex + 1;
    }
    if (start > 0) {
      _buffer.removeRange(0, start);
    }
    return lines;
  }
}

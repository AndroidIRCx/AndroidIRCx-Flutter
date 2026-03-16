import 'dart:convert';

class MircPresetEntry {
  const MircPresetEntry({
    required this.id,
    required this.raw,
    this.enabled,
  });

  final String id;
  final String raw;
  final bool? enabled;
}

const Map<int, int> _cp1252Map = <int, int>{
  0x80: 0x20AC,
  0x82: 0x201A,
  0x83: 0x0192,
  0x84: 0x201E,
  0x85: 0x2026,
  0x86: 0x2020,
  0x87: 0x2021,
  0x88: 0x02C6,
  0x89: 0x2030,
  0x8A: 0x0160,
  0x8B: 0x2039,
  0x8C: 0x0152,
  0x8E: 0x017D,
  0x91: 0x2018,
  0x92: 0x2019,
  0x93: 0x201C,
  0x94: 0x201D,
  0x95: 0x2022,
  0x96: 0x2013,
  0x97: 0x2014,
  0x98: 0x02DC,
  0x99: 0x2122,
  0x9A: 0x0161,
  0x9B: 0x203A,
  0x9C: 0x0153,
  0x9E: 0x017E,
  0x9F: 0x0178,
};

final RegExp _lineSplit = RegExp(r'\r\n|\n|\r');

String decodeMircPresetBase64(String base64Value) {
  final sanitized = base64Value.replaceAll(RegExp(r'\s+'), '');
  final bytes = base64.decode(sanitized);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte >= 0x80 && byte <= 0x9F) {
        buffer.writeCharCode(_cp1252Map[byte] ?? byte);
      } else {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString();
  }
}

List<String> splitPresetLines(String raw) {
  return raw
      .split(_lineSplit)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

List<MircPresetEntry> parseGenericPresets(String raw) {
  final lines = splitPresetLines(raw);
  return List<MircPresetEntry>.generate(
    lines.length,
    (index) => MircPresetEntry(id: 'preset-${index + 1}', raw: lines[index]),
    growable: false,
  );
}

List<MircPresetEntry> parseNickCompletionPresets(String raw) {
  final lines = splitPresetLines(raw);
  return List<MircPresetEntry>.generate(lines.length, (index) {
    final line = lines[index];
    final match = RegExp(r'(\s+|\x08)(on|off)$', caseSensitive: false).firstMatch(line);
    if (match == null) {
      return MircPresetEntry(id: 'nick-${index + 1}', raw: line);
    }

    final enabled = match.group(2)!.toLowerCase() == 'on';
    final separator = match.group(1)!;
    final rawValue = separator == '\x08'
        ? line.substring(0, match.start + 1)
        : line.substring(0, match.start).trim();
    return MircPresetEntry(
      id: 'nick-${index + 1}',
      raw: rawValue,
      enabled: enabled,
    );
  }, growable: false);
}

List<String> parseIrcapDecorationEti(String raw) {
  final results = <String>[];
  final seen = <String>{};
  final lines = raw.split(_lineSplit).where((line) => line.isNotEmpty);

  for (final line in lines) {
    final fields = line.split('\x08');
    if (fields.length < 9) {
      continue;
    }
    final prefix = fields[fields.length - 3];
    final suffix = fields[fields.length - 2];
    final style = '$prefix\x08$suffix'.replaceAll('\x00', '');
    if (style.trim().isEmpty && !style.contains('\x08')) {
      continue;
    }
    if (seen.add(style)) {
      results.add(style);
    }
  }

  return List<String>.unmodifiable(results);
}

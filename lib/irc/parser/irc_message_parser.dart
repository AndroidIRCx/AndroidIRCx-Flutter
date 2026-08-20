import 'package:androidircx/irc/models/irc_message_frame.dart';

IrcMessageFrame parseIrcMessage(String raw) {
  var rest = raw.trim();
  Map<String, String?> tags = const <String, String?>{};
  String? prefix;
  String? trailing;

  if (rest.startsWith('@')) {
    final tagsEnd = rest.indexOf(' ');
    if (tagsEnd == -1) {
      return IrcMessageFrame(raw: raw, command: '', params: const []);
    }
    tags = _parseMessageTags(rest.substring(1, tagsEnd));
    rest = rest.substring(tagsEnd + 1).trimLeft();
  }

  if (rest.startsWith(':')) {
    final prefixEnd = rest.indexOf(' ');
    if (prefixEnd == -1) {
      return IrcMessageFrame(
        raw: raw,
        tags: tags,
        command: '',
        params: const [],
      );
    }
    prefix = rest.substring(1, prefixEnd);
    rest = rest.substring(prefixEnd + 1).trimLeft();
  }

  final trailingIndex = rest.indexOf(' :');
  if (trailingIndex != -1) {
    trailing = rest.substring(trailingIndex + 2);
    rest = rest.substring(0, trailingIndex);
  }

  final parts = rest
      .split(' ')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  if (parts.isEmpty) {
    return IrcMessageFrame(raw: raw, command: '', params: const []);
  }

  return IrcMessageFrame(
    raw: raw,
    tags: tags,
    prefix: prefix,
    command: parts.first.toUpperCase(),
    params: parts.skip(1).toList(growable: false),
    trailing: trailing,
  );
}

Map<String, String?> _parseMessageTags(String source) {
  if (source.isEmpty) {
    return const <String, String?>{};
  }

  final tags = <String, String?>{};
  for (final entry in source.split(';')) {
    if (entry.isEmpty) {
      continue;
    }

    final separator = entry.indexOf('=');
    if (separator == -1) {
      tags[entry] = null;
      continue;
    }

    final key = entry.substring(0, separator);
    final value = entry.substring(separator + 1);
    tags[key] = _unescapeTagValue(value);
  }

  return tags;
}

String _unescapeTagValue(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i += 1) {
    final current = value[i];
    if (current != r'\' || i + 1 >= value.length) {
      buffer.write(current);
      continue;
    }

    i += 1;
    switch (value[i]) {
      case ':':
        buffer.write(';');
      case 's':
        buffer.write(' ');
      case r'\':
        buffer.write(r'\');
      case 'r':
        buffer.write('\r');
      case 'n':
        buffer.write('\n');
      default:
        buffer.write(value[i]);
    }
  }

  return buffer.toString();
}

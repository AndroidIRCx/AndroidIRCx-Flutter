import 'package:androidircx/irc/models/irc_message_frame.dart';

IrcMessageFrame parseIrcMessage(String raw) {
  var rest = raw.trim();
  String? prefix;
  String? trailing;

  if (rest.startsWith(':')) {
    final prefixEnd = rest.indexOf(' ');
    if (prefixEnd != -1) {
      prefix = rest.substring(1, prefixEnd);
      rest = rest.substring(prefixEnd + 1);
    }
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
    prefix: prefix,
    command: parts.first.toUpperCase(),
    params: parts.skip(1).toList(growable: false),
    trailing: trailing,
  );
}

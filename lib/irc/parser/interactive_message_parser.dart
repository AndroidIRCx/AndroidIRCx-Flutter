import 'package:androidircx/irc/parser/irc_formatter.dart';

enum InteractiveMessageTokenType {
  text,
  url,
  channel,
  nick,
  hostmask,
  userHost,
}

class InteractiveMessageToken {
  const InteractiveMessageToken({
    required this.type,
    required this.text,
    required this.style,
    this.value,
    this.url,
  });

  final InteractiveMessageTokenType type;
  final String text;
  final IrcFormatStyle style;

  /// Normalized interaction target. For nick-like tokens this is the nick; for
  /// channel tokens this is the channel name.
  final String? value;
  final String? url;

  bool get isInteractive => type != InteractiveMessageTokenType.text;
}

List<InteractiveMessageToken> parseInteractiveMessageTokens(
  String text, {
  Iterable<String> knownNicks = const <String>[],
  String channelPrefixes = '#&',
  String nickPrefixes = '~&@%+',
  String? contextNick,
}) {
  final nickMap = <String, String>{};
  for (final nick in knownNicks) {
    final normalized = _normalizeNick(nick, nickPrefixes);
    if (normalized.isNotEmpty) {
      nickMap[normalized.toLowerCase()] = normalized;
    }
  }
  final context = _normalizeNick(contextNick ?? '', nickPrefixes);

  final output = <InteractiveMessageToken>[];
  for (final segment in parseIrcTextWithLinks(text)) {
    if (segment.isLink) {
      output.add(
        InteractiveMessageToken(
          type: InteractiveMessageTokenType.url,
          text: segment.text,
          style: segment.style,
          value: segment.url,
          url: segment.url,
        ),
      );
      continue;
    }
    output.addAll(
      _parsePlainInteractiveSegment(
        segment.text,
        style: segment.style,
        nickMap: nickMap,
        channelPrefixes: channelPrefixes,
        nickPrefixes: nickPrefixes,
        contextNick: context,
      ),
    );
  }
  return output;
}

List<InteractiveMessageToken> _parsePlainInteractiveSegment(
  String text, {
  required IrcFormatStyle style,
  required Map<String, String> nickMap,
  required String channelPrefixes,
  required String nickPrefixes,
  required String contextNick,
}) {
  if (text.isEmpty) {
    return <InteractiveMessageToken>[
      InteractiveMessageToken(
        type: InteractiveMessageTokenType.text,
        text: text,
        style: style,
      ),
    ];
  }

  final output = <InteractiveMessageToken>[];
  for (final match in RegExp(r'\s+|\S+').allMatches(text)) {
    final token = match.group(0)!;
    if (token.trim().isEmpty) {
      output.add(
        InteractiveMessageToken(
          type: InteractiveMessageTokenType.text,
          text: token,
          style: style,
        ),
      );
      continue;
    }
    output.addAll(
      _classifyWordToken(
        token,
        style: style,
        nickMap: nickMap,
        channelPrefixes: channelPrefixes,
        nickPrefixes: nickPrefixes,
        contextNick: contextNick,
      ),
    );
  }
  return output;
}

List<InteractiveMessageToken> _classifyWordToken(
  String token, {
  required IrcFormatStyle style,
  required Map<String, String> nickMap,
  required String channelPrefixes,
  required String nickPrefixes,
  required String contextNick,
}) {
  final split = _splitOuterPunctuation(token);
  final output = <InteractiveMessageToken>[];
  void addText(String value) {
    if (value.isEmpty) {
      return;
    }
    output.add(
      InteractiveMessageToken(
        type: InteractiveMessageTokenType.text,
        text: value,
        style: style,
      ),
    );
  }

  addText(split.leading);
  final classified = _classifyCoreToken(
    split.core,
    style: style,
    nickMap: nickMap,
    channelPrefixes: channelPrefixes,
    nickPrefixes: nickPrefixes,
    contextNick: contextNick,
  );
  output.add(classified);
  addText(split.trailing);
  return output;
}

InteractiveMessageToken _classifyCoreToken(
  String core, {
  required IrcFormatStyle style,
  required Map<String, String> nickMap,
  required String channelPrefixes,
  required String nickPrefixes,
  required String contextNick,
}) {
  if (core.isEmpty) {
    return InteractiveMessageToken(
      type: InteractiveMessageTokenType.text,
      text: core,
      style: style,
    );
  }

  final hostmask = _parseHostmask(core, nickPrefixes);
  if (hostmask != null) {
    final resolved =
        nickMap[hostmask.nick.toLowerCase()] ??
        _normalizeNick(hostmask.nick, nickPrefixes);
    return InteractiveMessageToken(
      type: InteractiveMessageTokenType.hostmask,
      text: core,
      style: style,
      value: resolved,
    );
  }

  if (_looksLikeUserHost(core) && contextNick.isNotEmpty) {
    return InteractiveMessageToken(
      type: InteractiveMessageTokenType.userHost,
      text: core,
      style: style,
      value: contextNick,
    );
  }

  if (_isChannelToken(core, channelPrefixes)) {
    return InteractiveMessageToken(
      type: InteractiveMessageTokenType.channel,
      text: core,
      style: style,
      value: core,
    );
  }

  final normalizedNick = _normalizeNick(core, nickPrefixes);
  final resolved = nickMap[normalizedNick.toLowerCase()];
  if (resolved != null) {
    return InteractiveMessageToken(
      type: InteractiveMessageTokenType.nick,
      text: core,
      style: style,
      value: resolved,
    );
  }

  return InteractiveMessageToken(
    type: InteractiveMessageTokenType.text,
    text: core,
    style: style,
  );
}

({String leading, String core, String trailing}) _splitOuterPunctuation(
  String token,
) {
  var start = 0;
  var end = token.length;
  while (start < end && _isLeadingPunctuation(token[start])) {
    start += 1;
  }
  while (end > start && _isTrailingPunctuation(token[end - 1])) {
    end -= 1;
  }
  return (
    leading: token.substring(0, start),
    core: token.substring(start, end),
    trailing: token.substring(end),
  );
}

bool _isLeadingPunctuation(String value) => '([{<"\''.contains(value);

bool _isTrailingPunctuation(String value) => '.,;:!?)]}>"\''.contains(value);

String _normalizeNick(String value, String nickPrefixes) {
  var normalized = value.trim();
  while (normalized.isNotEmpty && nickPrefixes.contains(normalized[0])) {
    normalized = normalized.substring(1);
  }
  final bangIndex = normalized.indexOf('!');
  if (bangIndex != -1) {
    normalized = normalized.substring(0, bangIndex);
  }
  return normalized;
}

bool _isChannelToken(String value, String channelPrefixes) {
  if (value.length < 2 || channelPrefixes.isEmpty) {
    return false;
  }
  if (!channelPrefixes.contains(value[0])) {
    return false;
  }
  if (value.codeUnits.any((code) => code < 0x20 || code == 0x7F)) {
    return false;
  }
  return true;
}

({String nick})? _parseHostmask(String value, String nickPrefixes) {
  final bangIndex = value.indexOf('!');
  final atIndex = value.indexOf('@');
  if (bangIndex <= 0 ||
      atIndex <= bangIndex + 1 ||
      atIndex == value.length - 1) {
    return null;
  }
  final nick = _normalizeNick(value.substring(0, bangIndex), nickPrefixes);
  if (nick.isEmpty) {
    return null;
  }
  return (nick: nick);
}

bool _looksLikeUserHost(String value) {
  final atIndex = value.indexOf('@');
  if (atIndex <= 0 || atIndex == value.length - 1 || value.contains('!')) {
    return false;
  }
  return !value.substring(0, atIndex).contains(RegExp(r'\s')) &&
      !value.substring(atIndex + 1).contains(RegExp(r'\s'));
}

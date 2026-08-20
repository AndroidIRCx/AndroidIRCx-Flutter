import 'package:androidircx/irc/models/irc_message_frame.dart';

class IrcPrefixMapping {
  const IrcPrefixMapping({required this.modes, required this.prefixes});

  final String modes;
  final String prefixes;

  bool get isValid => modes.length == prefixes.length;
}

class IrcServerSupport {
  const IrcServerSupport({this.tokens = const <String, String?>{}});

  const IrcServerSupport.empty() : tokens = const <String, String?>{};

  static const String defaultCaseMapping = 'rfc1459';
  static const String defaultChannelTypes = '#&';
  static const IrcPrefixMapping defaultPrefixMapping = IrcPrefixMapping(
    modes: 'ov',
    prefixes: '@+',
  );

  final Map<String, String?> tokens;

  bool contains(String token) => tokens.containsKey(token.toUpperCase());

  String? value(String token) => tokens[token.toUpperCase()];

  String get caseMapping {
    final value = this.value('CASEMAPPING');
    return value == null || value.isEmpty ? defaultCaseMapping : value;
  }

  String get channelTypes {
    if (!tokens.containsKey('CHANTYPES')) {
      return defaultChannelTypes;
    }
    return tokens['CHANTYPES'] ?? '';
  }

  String get channelModes => value('CHANMODES') ?? '';

  String? get networkName => value('NETWORK');

  IrcPrefixMapping get prefixMapping {
    if (!tokens.containsKey('PREFIX')) {
      return defaultPrefixMapping;
    }

    final value = tokens['PREFIX'];
    if (value == null || value.isEmpty) {
      return const IrcPrefixMapping(modes: '', prefixes: '');
    }

    final match = RegExp(r'^\(([^)]*)\)(.*)$').firstMatch(value);
    if (match == null) {
      return const IrcPrefixMapping(modes: '', prefixes: '');
    }

    final mapping = IrcPrefixMapping(
      modes: match.group(1) ?? '',
      prefixes: match.group(2) ?? '',
    );
    return mapping.isValid
        ? mapping
        : const IrcPrefixMapping(modes: '', prefixes: '');
  }

  String get nickPrefixModes => prefixMapping.modes;

  String get nickPrefixSymbols => prefixMapping.prefixes;

  IrcServerSupport mergeTokens(Iterable<String> rawTokens) {
    final next = Map<String, String?>.of(tokens);

    for (final rawToken in rawTokens) {
      final token = rawToken.trim();
      if (token.isEmpty) {
        continue;
      }

      final separator = token.indexOf('=');
      if (separator == -1) {
        if (token.startsWith('-') && token.length > 1) {
          next.remove(token.substring(1).toUpperCase());
          continue;
        }
        next[token.toUpperCase()] = null;
        continue;
      }

      final key = token.substring(0, separator).trim().toUpperCase();
      if (key.isEmpty) {
        continue;
      }
      next[key] = _decodeISupportValue(token.substring(separator + 1));
    }

    return IrcServerSupport(tokens: Map<String, String?>.unmodifiable(next));
  }

  IrcServerSupport mergeFrame(IrcMessageFrame frame) {
    return mergeTokens(isupportTokensFromFrame(frame));
  }
}

List<String> isupportTokensFromFrame(IrcMessageFrame frame) {
  if (frame.params.length <= 1) {
    return const <String>[];
  }
  return frame.params.skip(1).toList(growable: false);
}

IrcServerSupport parseIrcServerSupport(Iterable<String> rawTokens) {
  return const IrcServerSupport.empty().mergeTokens(rawTokens);
}

String _decodeISupportValue(String value) {
  return value.replaceAllMapped(RegExp(r'\\x([0-9A-Fa-f]{2})'), (match) {
    final code = int.parse(match.group(1)!, radix: 16);
    return String.fromCharCode(code);
  });
}

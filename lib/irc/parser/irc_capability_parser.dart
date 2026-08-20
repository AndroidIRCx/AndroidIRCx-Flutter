class IrcCapabilityToken {
  const IrcCapabilityToken({
    required this.name,
    this.value,
    this.disabled = false,
  });

  final String name;
  final String? value;
  final bool disabled;
}

List<IrcCapabilityToken> parseIrcCapabilityTokens(
  String source, {
  bool allowDisablePrefix = false,
}) {
  final tokens = <IrcCapabilityToken>[];

  for (final rawPart in source.split(RegExp(r'\s+'))) {
    var part = rawPart.trim();
    if (part.isEmpty || part == '*') {
      continue;
    }
    if (part.startsWith(':')) {
      part = part.substring(1);
    }
    if (part.isEmpty || part == '*') {
      continue;
    }

    final separator = part.indexOf('=');
    var rawName = separator == -1 ? part : part.substring(0, separator);
    final value = separator == -1 ? null : part.substring(separator + 1);
    var disabled = false;

    if (allowDisablePrefix && rawName.startsWith('-')) {
      disabled = true;
      rawName = rawName.substring(1);
    }

    final name = rawName.trim();
    if (name.isEmpty) {
      continue;
    }

    tokens.add(
      IrcCapabilityToken(name: name, value: value, disabled: disabled),
    );
  }

  return tokens;
}

Set<String> parseIrcCapabilityNames(
  String source, {
  bool allowDisablePrefix = false,
}) {
  return parseIrcCapabilityTokens(
    source,
    allowDisablePrefix: allowDisablePrefix,
  ).map((token) => token.name).toSet();
}

Set<String> parseIrcCapabilityValueList(String? value) {
  if (value == null) {
    return const <String>{};
  }

  final values = <String>{};
  for (final rawPart in value.split(',')) {
    final part = rawPart.trim();
    if (part.isNotEmpty) {
      values.add(part.toUpperCase());
    }
  }
  return values;
}

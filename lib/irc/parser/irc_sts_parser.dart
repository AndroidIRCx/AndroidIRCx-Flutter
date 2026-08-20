class IrcStsDirective {
  const IrcStsDirective({
    this.port,
    this.durationSeconds,
    this.preload = false,
  });

  final int? port;
  final int? durationSeconds;
  final bool preload;
}

IrcStsDirective parseIrcStsDirective(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const IrcStsDirective();
  }

  int? port;
  int? durationSeconds;
  var preload = false;

  for (final rawToken in value.split(',')) {
    final token = rawToken.trim();
    if (token.isEmpty) {
      continue;
    }

    final separator = token.indexOf('=');
    final key = (separator == -1 ? token : token.substring(0, separator))
        .trim()
        .toLowerCase();
    final rawValue = separator == -1 ? null : token.substring(separator + 1);

    switch (key) {
      case 'port':
        final parsed = int.tryParse((rawValue ?? '').trim());
        if (parsed != null && parsed > 0 && parsed <= 65535) {
          port = parsed;
        }
      case 'duration':
        final parsed = int.tryParse((rawValue ?? '').trim());
        if (parsed != null && parsed >= 0) {
          durationSeconds = parsed;
        }
      case 'preload':
        preload = true;
    }
  }

  return IrcStsDirective(
    port: port,
    durationSeconds: durationSeconds,
    preload: preload,
  );
}

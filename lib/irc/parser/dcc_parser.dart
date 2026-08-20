class DccOffer {
  const DccOffer({
    required this.command,
    required this.target,
    this.filename,
    this.host,
    this.port,
    this.size,
    this.token,
    this.offset,
  });

  final String command;
  final String target;
  final String? filename;
  final String? host;
  final int? port;
  final int? size;
  final String? token;
  final int? offset;

  bool get isReverseSend => command == 'SEND' && port == 0 && token != null;
}

DccOffer? parseDccOffer(String args) {
  final trimmed = args.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final parts = _tokenizeDccPayload(trimmed);
  if (parts.length < 2 || parts.first.toUpperCase() != 'DCC') {
    return null;
  }

  final command = parts[1].toUpperCase();
  switch (command) {
    case 'CHAT':
      if (parts.length >= 5) {
        return DccOffer(
          command: command,
          target: parts[2],
          host: _normalizeDccHost(parts[3]),
          port: _parseNonNegativeInt(parts[4]),
          token: parts.length > 5 ? parts[5] : null,
        );
      }
      return null;
    case 'SEND':
      if (parts.length >= 5) {
        return DccOffer(
          command: command,
          target: 'file',
          filename: parts[2],
          host: _normalizeDccHost(parts[3]),
          port: _parseNonNegativeInt(parts[4]),
          size: parts.length > 5 ? _parseNonNegativeInt(parts[5]) : null,
          token: parts.length > 6 ? parts[6] : null,
        );
      }
      return null;
    case 'RESUME':
    case 'ACCEPT':
      if (parts.length >= 5) {
        return DccOffer(
          command: command,
          target: 'file',
          filename: parts[2],
          port: _parseNonNegativeInt(parts[3]),
          offset: _parseNonNegativeInt(parts[4]),
          token: parts.length > 5 ? parts[5] : null,
        );
      }
      return null;
    default:
      return DccOffer(
        command: command,
        target: parts.length > 2 ? parts[2] : '',
      );
  }
}

List<String> _tokenizeDccPayload(String value) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  var escaped = false;

  void flush() {
    if (buffer.isEmpty) {
      return;
    }
    tokens.add(buffer.toString());
    buffer.clear();
  }

  for (var i = 0; i < value.length; i += 1) {
    final char = value[i];
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (quoted && char == '\\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      quoted = !quoted;
      continue;
    }
    if (!quoted && char.trim().isEmpty) {
      flush();
      continue;
    }
    buffer.write(char);
  }

  flush();
  return tokens;
}

String _normalizeDccHost(String host) {
  if (!RegExp(r'^\d+$').hasMatch(host)) {
    return host;
  }

  final value = int.tryParse(host);
  if (value == null || value < 0 || value > 0xffffffff) {
    return host;
  }

  return [
    (value >> 24) & 255,
    (value >> 16) & 255,
    (value >> 8) & 255,
    value & 255,
  ].join('.');
}

int? _parseNonNegativeInt(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

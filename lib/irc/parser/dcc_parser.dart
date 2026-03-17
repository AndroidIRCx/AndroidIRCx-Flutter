class DccOffer {
  const DccOffer({
    required this.command,
    required this.target,
    this.filename,
    this.host,
    this.port,
    this.size,
    this.token,
  });

  final String command;
  final String target;
  final String? filename;
  final String? host;
  final int? port;
  final int? size;
  final String? token;
}

DccOffer? parseDccOffer(String args) {
  final trimmed = args.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final parts = trimmed.split(RegExp(r'\s+'));
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
          port: int.tryParse(parts[4]),
        );
      }
      return null;
    case 'SEND':
      if (parts.length >= 5) {
        final filenameStart = trimmed.indexOf('SEND') + 5;
        final afterCommand = trimmed.substring(filenameStart).trim();
        final match = RegExp(r'^"?(.*?)"?\s+(\S+)\s+(\d+)\s+(\d+)(?:\s+(\S+))?$')
            .firstMatch(afterCommand);
        if (match != null) {
          return DccOffer(
            command: command,
            target: 'file',
            filename: match.group(1),
            host: _normalizeDccHost(match.group(2)!),
            port: int.tryParse(match.group(3)!),
            size: int.tryParse(match.group(4)!),
            token: match.group(5),
          );
        }
      }
      return null;
    default:
      return DccOffer(command: command, target: parts.length > 2 ? parts[2] : '');
  }
}

String _normalizeDccHost(String host) {
  if (!RegExp(r'^\d+$').hasMatch(host)) {
    return host;
  }

  final value = int.tryParse(host);
  if (value == null) {
    return host;
  }

  return [
    (value >> 24) & 255,
    (value >> 16) & 255,
    (value >> 8) & 255,
    value & 255,
  ].join('.');
}

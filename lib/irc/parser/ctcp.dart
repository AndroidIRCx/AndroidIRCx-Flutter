class CtcpMessage {
  const CtcpMessage({
    required this.isCtcp,
    this.command,
    this.args,
  });

  final bool isCtcp;
  final String? command;
  final String? args;
}

const _ctcpDelimiter = '\u0001';

CtcpMessage parseCtcp(String message) {
  if (!message.startsWith(_ctcpDelimiter) || !message.endsWith(_ctcpDelimiter)) {
    return const CtcpMessage(isCtcp: false);
  }

  final body = message.substring(1, message.length - 1).trim();
  if (body.isEmpty) {
    return const CtcpMessage(isCtcp: false);
  }

  final separator = body.indexOf(' ');
  if (separator == -1) {
    return CtcpMessage(isCtcp: true, command: body.toUpperCase());
  }

  return CtcpMessage(
    isCtcp: true,
    command: body.substring(0, separator).toUpperCase(),
    args: body.substring(separator + 1),
  );
}

String encodeCtcp(String command, [String? args]) {
  final normalizedCommand = command.trim().toUpperCase();
  final normalizedArgs = (args ?? '').trim();
  if (normalizedArgs.isEmpty) {
    return '$_ctcpDelimiter$normalizedCommand$_ctcpDelimiter';
  }

  return '$_ctcpDelimiter$normalizedCommand $normalizedArgs$_ctcpDelimiter';
}

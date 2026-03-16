class IrcMessageFrame {
  const IrcMessageFrame({
    required this.raw,
    required this.command,
    required this.params,
    this.prefix,
    this.trailing,
  });

  final String raw;
  final String? prefix;
  final String command;
  final List<String> params;
  final String? trailing;

  String? get senderNick {
    final value = prefix;
    if (value == null || value.isEmpty) {
      return null;
    }

    final bangIndex = value.indexOf('!');
    return bangIndex == -1 ? value : value.substring(0, bangIndex);
  }
}

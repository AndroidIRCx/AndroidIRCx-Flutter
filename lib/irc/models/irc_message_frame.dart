class IrcMessageFrame {
  const IrcMessageFrame({
    required this.raw,
    required this.command,
    required this.params,
    this.tags = const <String, String?>{},
    this.prefix,
    this.trailing,
  });

  final String raw;
  final Map<String, String?> tags;
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

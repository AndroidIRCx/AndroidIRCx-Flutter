/// A single channel returned by a server LIST (numeric 322).
class ChannelListEntry {
  const ChannelListEntry({
    required this.name,
    required this.userCount,
    required this.topic,
  });

  final String name;
  final int userCount;
  final String topic;
}

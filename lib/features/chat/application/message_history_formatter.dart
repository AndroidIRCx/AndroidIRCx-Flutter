import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';

String formatIrcMessagePlainText(
  IrcMessage message, {
  bool includeTimestamp = true,
  bool includeTags = false,
  bool includeAttachments = true,
}) {
  final buffer = StringBuffer();
  if (includeTimestamp) {
    buffer.write('[${message.timestamp.toIso8601String()}] ');
  }

  final senderPrefix = switch (message.kind) {
    IrcMessageKind.action => '* ${message.sender} ',
    IrcMessageKind.system ||
    IrcMessageKind.raw ||
    IrcMessageKind.error ||
    IrcMessageKind.event ||
    IrcMessageKind.dcc => '${message.sender} ',
    IrcMessageKind.chat ||
    IrcMessageKind.notice ||
    IrcMessageKind.media => '<${message.sender}> ',
  };

  buffer
    ..write(senderPrefix)
    ..write(formatIrcPlainText(message.content));

  if (includeAttachments && message.attachments.isNotEmpty) {
    for (final attachment in message.attachments) {
      final description = _formatAttachment(attachment);
      if (description.isNotEmpty) {
        buffer.write(' [$description]');
      }
    }
  }

  if (includeTags && message.tags.isNotEmpty) {
    buffer.write(' [tags: ${message.tags.entries.map(_formatTag).join(', ')}]');
  }

  return buffer.toString();
}

String _formatAttachment(IrcMessageAttachment attachment) {
  final type = switch (attachment.type) {
    IrcMessageAttachmentType.dccChat => 'dcc chat',
    IrcMessageAttachmentType.dccSend => 'dcc send',
    _ => attachment.type.name,
  };
  final name =
      (attachment.fileName ?? attachment.mediaId ?? attachment.uri ?? '')
          .trim();
  final parts = <String>[
    type,
    if (name.isNotEmpty) name,
    if ((attachment.uri ?? '').trim().isNotEmpty && attachment.uri != name)
      'url=${attachment.uri!.trim()}',
    if ((attachment.transferId ?? '').trim().isNotEmpty)
      'transfer=${attachment.transferId!.trim()}',
    if ((attachment.peerNick ?? '').trim().isNotEmpty)
      'peer=${attachment.peerNick!.trim()}',
    if (attachment.size != null) 'size=${attachment.size}',
    if ((attachment.direction ?? '').trim().isNotEmpty)
      'direction=${attachment.direction!.trim()}',
    if ((attachment.status ?? '').trim().isNotEmpty)
      'status=${attachment.status!.trim()}',
  ];
  return parts.join(' ');
}

String _formatTag(MapEntry<String, String?> entry) {
  final value = entry.value;
  if (value == null) {
    return entry.key;
  }
  return '${entry.key}=${formatIrcPlainText(value)}';
}

import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/features/chat/presentation/chat_screen.dart';
import 'package:flutter_test/flutter_test.dart';

IrcMessageAttachment att(IrcMessageAttachmentType type, {String? uri}) =>
    IrcMessageAttachment(type: type, label: '', uri: uri);

void main() {
  test('null uri means no action', () {
    expect(
      attachmentTapAction(att(IrcMessageAttachmentType.video)),
      AttachmentTapAction.none,
    );
  });

  test('image opens the image preview', () {
    expect(
      attachmentTapAction(
        att(IrcMessageAttachmentType.image, uri: 'https://x/y.png'),
      ),
      AttachmentTapAction.imagePreview,
    );
  });

  test('video/audio attachments play in-app', () {
    expect(
      attachmentTapAction(
        att(IrcMessageAttachmentType.video, uri: 'https://x/y.mp4'),
      ),
      AttachmentTapAction.playVideo,
    );
    expect(
      attachmentTapAction(
        att(IrcMessageAttachmentType.audio, uri: 'https://x/y.mp3'),
      ),
      AttachmentTapAction.playAudio,
    );
  });

  test('url attachments route by extension', () {
    expect(
      attachmentTapAction(
        att(IrcMessageAttachmentType.url, uri: 'https://x/clip.mp4'),
      ),
      AttachmentTapAction.playVideo,
    );
    expect(
      attachmentTapAction(
        att(IrcMessageAttachmentType.url, uri: 'https://x/song.ogg'),
      ),
      AttachmentTapAction.playAudio,
    );
    expect(
      attachmentTapAction(
        att(IrcMessageAttachmentType.url, uri: 'https://example.net/page'),
      ),
      AttachmentTapAction.external,
    );
  });

  test('file/dcc attachments go external', () {
    expect(
      attachmentTapAction(
        att(IrcMessageAttachmentType.file, uri: 'https://x/y.zip'),
      ),
      AttachmentTapAction.external,
    );
  });
}

import 'package:androidircx/irc/parser/message_content_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects media and url parts in a message', () {
    final parts = parseMessageContent(
      'Look https://example.com/a.png !enc-media [123e4567-e89b-12d3-a456-426614174000]',
    );

    expect(parts.any((part) => part.type == ParsedMessagePartType.image), isTrue);
    expect(parts.any((part) => part.type == ParsedMessagePartType.media), isTrue);
  });

  test('extracts urls and emojis', () {
    expect(
      extractUrls('Visit www.androidircx.com and https://example.com'),
      hasLength(2),
    );
    expect(extractEmojis('Hi 😀 IRC'), contains('😀'));
  });

  test('classifies downloadable file urls', () {
    expect(isDownloadableFileUrl('https://example.com/manual.pdf'), isTrue);
    expect(isDownloadableFileUrl('https://example.com/photo.jpg'), isFalse);
  });

  test('extracts media tags', () {
    final tags = extractMediaTags(
      'file !enc-media [123e4567-e89b-12d3-a456-426614174000]',
    );

    expect(tags, hasLength(1));
    expect(tags.first.mediaId, '123e4567-e89b-12d3-a456-426614174000');
  });
}

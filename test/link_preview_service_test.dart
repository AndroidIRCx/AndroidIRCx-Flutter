import 'package:androidircx/media/services/link_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLinkPreview', () {
    test('parses OpenGraph metadata', () {
      const html = '<html><head>'
          '<meta property="og:title" content="Cool Title">'
          '<meta property="og:description" content="A description">'
          '<meta property="og:image" content="https://example.com/img.png">'
          '<title>Fallback</title></head></html>';
      final preview = parseLinkPreview(html, 'https://example.com');
      expect(preview.title, 'Cool Title');
      expect(preview.description, 'A description');
      expect(preview.imageUrl, 'https://example.com/img.png');
      expect(preview.hasContent, isTrue);
    });

    test('falls back to <title> and decodes entities', () {
      const html = '<head><title>Just Title &amp; More</title></head>';
      final preview = parseLinkPreview(html, 'https://example.com');
      expect(preview.title, 'Just Title & More');
    });

    test('handles content-before-property attribute order', () {
      const html =
          '<meta content="Reversed" property="og:title">';
      expect(parseLinkPreview(html, 'https://x').title, 'Reversed');
    });
  });

  group('LinkPreviewService', () {
    test('fetches and caches previews', () async {
      var calls = 0;
      final service = LinkPreviewService(
        fetcher: (_) async {
          calls++;
          return '<meta property="og:title" content="X">';
        },
      );
      final first = await service.fetch('https://example.com');
      final second = await service.fetch('https://example.com');
      expect(first?.title, 'X');
      expect(second?.title, 'X');
      expect(calls, 1);
    });

    test('returns null for non-http URLs', () async {
      final service = LinkPreviewService(fetcher: (_) async => '');
      expect(await service.fetch('ftp://example.com'), isNull);
    });

    test('returns null when the fetch throws', () async {
      final service = LinkPreviewService(
        fetcher: (_) async => throw Exception('offline'),
      );
      expect(await service.fetch('https://example.com'), isNull);
    });
  });
}

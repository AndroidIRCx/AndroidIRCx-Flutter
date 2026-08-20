import 'dart:convert';
import 'dart:io';

/// OpenGraph-style preview for a URL.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  bool get hasContent =>
      (title != null && title!.isNotEmpty) ||
      (description != null && description!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);
}

/// Fetches a URL and returns its HTML. Injectable for tests.
typedef LinkHtmlFetcher = Future<String> Function(Uri url);

/// Fetches and caches link previews by parsing OpenGraph/HTML metadata.
class LinkPreviewService {
  LinkPreviewService({LinkHtmlFetcher? fetcher})
      : _fetcher = fetcher ?? _defaultFetch;

  final LinkHtmlFetcher _fetcher;
  final Map<String, LinkPreview?> _cache = <String, LinkPreview?>{};

  Future<LinkPreview?> fetch(String url) async {
    if (_cache.containsKey(url)) {
      return _cache[url];
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      _cache[url] = null;
      return null;
    }
    try {
      final html = await _fetcher(uri);
      final preview = parseLinkPreview(html, url);
      _cache[url] = preview.hasContent ? preview : null;
      return _cache[url];
    } catch (_) {
      _cache[url] = null;
      return null;
    }
  }

  static Future<String> _defaultFetch(Uri url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'text/html');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      // Only need the <head>; cap the amount we read.
      final buffer = StringBuffer();
      await for (final chunk in response.transform(utf8.decoder)) {
        buffer.write(chunk);
        if (buffer.length > 200000 ||
            buffer.toString().contains('</head>')) {
          break;
        }
      }
      return buffer.toString();
    } finally {
      client.close(force: true);
    }
  }
}

/// Parses OpenGraph tags (falling back to `<title>`) out of [html].
LinkPreview parseLinkPreview(String html, String url) {
  String? meta(String property) {
    for (final attr in const ['property', 'name']) {
      final pattern = RegExp(
        '<meta[^>]*$attr=["\']$property["\'][^>]*content=["\']([^"\']*)["\']',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(html);
      if (match != null) {
        return _decodeEntities(match.group(1)!.trim());
      }
      // content-before-property ordering
      final reversed = RegExp(
        '<meta[^>]*content=["\']([^"\']*)["\'][^>]*$attr=["\']$property["\']',
        caseSensitive: false,
      );
      final reverseMatch = reversed.firstMatch(html);
      if (reverseMatch != null) {
        return _decodeEntities(reverseMatch.group(1)!.trim());
      }
    }
    return null;
  }

  String? title = meta('og:title');
  if (title == null || title.isEmpty) {
    final titleTag =
        RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false)
            .firstMatch(html);
    if (titleTag != null) {
      title = _decodeEntities(titleTag.group(1)!.trim());
    }
  }

  return LinkPreview(
    url: url,
    title: (title == null || title.isEmpty) ? null : title,
    description: meta('og:description') ?? meta('description'),
    imageUrl: meta('og:image'),
  );
}

String _decodeEntities(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}

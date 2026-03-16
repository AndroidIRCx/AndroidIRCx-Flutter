class ParsedMessagePart {
  const ParsedMessagePart({
    required this.type,
    required this.content,
    this.url,
    this.mediaId,
  });

  final ParsedMessagePartType type;
  final String content;
  final String? url;
  final String? mediaId;
}

enum ParsedMessagePartType {
  text,
  url,
  image,
  media,
}

final RegExp _mediaTagPattern = RegExp(
  r'!enc-media\s+\[([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]',
  caseSensitive: false,
);
final RegExp _urlPattern = RegExp(
  r'(https?:\/\/[^\s<>"{}|\\^`\[\]]+|ftp:\/\/[^\s<>"{}|\\^`\[\]]+|www\.[^\s<>"{}|\\^`\[\]]+)',
  caseSensitive: false,
);
final RegExp _imagePattern = RegExp(
  r'(https?:\/\/[^\s<>"{}|\\^`\[\]]+\.(jpg|jpeg|png|gif|webp|svg|bmp|ico)(\?[^\s<>"{}|\\^`\[\]]*)?)',
  caseSensitive: false,
);
final RegExp _videoPattern = RegExp(
  r'(https?:\/\/[^\s<>"{}|\\^`\[\]]+\.(mp4|mov|webm|mkv|avi)(\?[^\s<>"{}|\\^`\[\]]*)?)',
  caseSensitive: false,
);
final RegExp _audioPattern = RegExp(
  r'(https?:\/\/[^\s<>"{}|\\^`\[\]]+\.(mp3|ogg|wav|m4a|flac)(\?[^\s<>"{}|\\^`\[\]]*)?)',
  caseSensitive: false,
);
final RegExp _emojiPattern = RegExp(
  r'[\u{1F300}-\u{1F9FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{1F600}-\u{1F64F}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]',
  unicode: true,
);

const List<String> _downloadableExtensions = <String>[
  'pdf',
  'zip',
  'rar',
  '7z',
  'tar',
  'gz',
  'tgz',
  'bz2',
  'xz',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'csv',
  'txt',
  'json',
  'xml',
  'apk',
  'ipa',
  'exe',
  'msi',
  'dmg',
  'pkg',
  'iso',
  'psd',
  'ai',
  'sketch',
  'fig',
  'epub',
  'mobi',
];

class ExtractedMediaTag {
  const ExtractedMediaTag({
    required this.tag,
    required this.mediaId,
  });

  final String tag;
  final String mediaId;
}

bool isImageUrl(String url) {
  final lowerUrl = url.toLowerCase();
  const imageExtensions = <String>[
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.svg',
    '.bmp',
    '.ico',
  ];
  return imageExtensions.any(lowerUrl.contains) || _imagePattern.hasMatch(url);
}

bool isVideoUrl(String url) {
  final lowerUrl = url.toLowerCase();
  const videoExtensions = <String>['.mp4', '.mov', '.webm', '.mkv', '.avi'];
  return videoExtensions.any(lowerUrl.contains) || _videoPattern.hasMatch(url);
}

bool isAudioUrl(String url) {
  final lowerUrl = url.toLowerCase();
  const audioExtensions = <String>['.mp3', '.ogg', '.wav', '.m4a', '.flac'];
  return audioExtensions.any(lowerUrl.contains) || _audioPattern.hasMatch(url);
}

String? getUrlExtension(String url) {
  try {
    final normalized = url.contains('://') ? url : 'https://$url';
    final parsed = Uri.parse(normalized);
    final nonEmptySegments =
        parsed.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    final lastSegment = nonEmptySegments.isEmpty ? null : nonEmptySegments.last;
    if (lastSegment == null || !lastSegment.contains('.')) {
      return null;
    }
    final ext = lastSegment.split('.').last.toLowerCase();
    const nonFileExtensions = <String>[
      'html',
      'htm',
      'php',
      'asp',
      'aspx',
      'jsp',
      'cfm',
    ];
    return nonFileExtensions.contains(ext) ? null : ext;
  } catch (_) {
    return null;
  }
}

bool isDownloadableFileUrl(String url) {
  final ext = getUrlExtension(url);
  if (ext == null) {
    return false;
  }
  if (isImageUrl(url) || isVideoUrl(url) || isAudioUrl(url)) {
    return false;
  }
  return _downloadableExtensions.contains(ext) || RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext);
}

List<String> extractUrls(String text) =>
    _urlPattern.allMatches(text).map((match) => match.group(0)!).toList(growable: false);

List<String> extractImageUrls(String text) =>
    _imagePattern.allMatches(text).map((match) => match.group(0)!).toList(growable: false);

List<String> extractEmojis(String text) =>
    _emojiPattern.allMatches(text).map((match) => match.group(0)!).toList(growable: false);

List<ExtractedMediaTag> extractMediaTags(String text) {
  return _mediaTagPattern
      .allMatches(text)
      .map(
        (match) => ExtractedMediaTag(
          tag: match.group(0)!,
          mediaId: match.group(1)!,
        ),
      )
      .toList(growable: false);
}

bool hasMediaTags(String text) => _mediaTagPattern.hasMatch(text);

List<ParsedMessagePart> parseMessageContent(String text) {
  if (text.isEmpty) {
    return const <ParsedMessagePart>[];
  }

  final matches = <_IndexedMatch>[];

  for (final match in _mediaTagPattern.allMatches(text)) {
    matches.add(
      _IndexedMatch(
        index: match.start,
        content: match.group(0)!,
        type: ParsedMessagePartType.media,
        mediaId: match.group(1),
      ),
    );
  }

  for (final match in _imagePattern.allMatches(text)) {
    matches.add(
      _IndexedMatch(
        index: match.start,
        content: match.group(0)!,
        type: ParsedMessagePartType.image,
      ),
    );
  }

  for (final match in _urlPattern.allMatches(text)) {
    final content = match.group(0)!;
    final alreadyCaptured =
        matches.any((item) => item.index == match.start && item.content == content);
    if (alreadyCaptured) {
      continue;
    }
    matches.add(
      _IndexedMatch(
        index: match.start,
        content: content,
        type: isImageUrl(content)
            ? ParsedMessagePartType.image
            : ParsedMessagePartType.url,
      ),
    );
  }

  matches.sort((a, b) => a.index.compareTo(b.index));

  final parts = <ParsedMessagePart>[];
  var lastIndex = 0;
  for (final match in matches) {
    if (match.index > lastIndex) {
      parts.add(
        ParsedMessagePart(
          type: ParsedMessagePartType.text,
          content: text.substring(lastIndex, match.index),
        ),
      );
    }

    parts.add(
      ParsedMessagePart(
        type: match.type,
        content: match.content,
        url: match.type == ParsedMessagePartType.media ? null : match.content,
        mediaId: match.mediaId,
      ),
    );

    lastIndex = match.index + match.content.length;
  }

  if (lastIndex < text.length) {
    parts.add(
      ParsedMessagePart(
        type: ParsedMessagePartType.text,
        content: text.substring(lastIndex),
      ),
    );
  }

  return parts;
}

class _IndexedMatch {
  const _IndexedMatch({
    required this.index,
    required this.content,
    required this.type,
    this.mediaId,
  });

  final int index;
  final String content;
  final ParsedMessagePartType type;
  final String? mediaId;
}

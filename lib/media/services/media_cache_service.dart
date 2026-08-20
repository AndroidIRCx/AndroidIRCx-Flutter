class MediaCacheEntry {
  const MediaCacheEntry({
    required this.id,
    required this.url,
    required this.fileName,
    required this.localPath,
    required this.sizeBytes,
    required this.createdAt,
    required this.lastAccessedAt,
    this.contentType,
  });

  final String id;
  final String url;
  final String fileName;
  final String localPath;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime lastAccessedAt;
  final String? contentType;

  MediaCacheEntry copyWith({
    String? id,
    String? url,
    String? fileName,
    String? localPath,
    int? sizeBytes,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
    String? contentType,
  }) {
    return MediaCacheEntry(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      contentType: contentType ?? this.contentType,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'url': url,
      'fileName': fileName,
      'localPath': localPath,
      'sizeBytes': sizeBytes,
      'createdAt': createdAt.toIso8601String(),
      'lastAccessedAt': lastAccessedAt.toIso8601String(),
      'contentType': contentType,
    };
  }

  factory MediaCacheEntry.fromJson(Map<String, Object?> json) {
    final createdAt = DateTime.parse(json['createdAt']! as String);
    return MediaCacheEntry(
      id: json['id']! as String,
      url: json['url']! as String,
      fileName: json['fileName']! as String,
      localPath: json['localPath']! as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      createdAt: createdAt,
      lastAccessedAt:
          DateTime.tryParse((json['lastAccessedAt'] as String?) ?? '') ??
          createdAt,
      contentType: json['contentType'] as String?,
    );
  }
}

class MediaCacheLimits {
  const MediaCacheLimits({
    this.maxEntries = 200,
    this.maxBytes = 250 * 1024 * 1024,
  });

  final int maxEntries;
  final int maxBytes;
}

typedef DeleteCachedMediaFile = Future<void> Function(String localPath);

class MediaCacheService {
  MediaCacheService({
    MediaCacheLimits limits = const MediaCacheLimits(),
    DateTime Function()? clock,
    DeleteCachedMediaFile? deleteFile,
  }) : _limits = limits,
       _clock = clock ?? DateTime.now,
       _deleteFile = deleteFile;

  final MediaCacheLimits _limits;
  final DateTime Function() _clock;
  final DeleteCachedMediaFile? _deleteFile;
  final Map<String, MediaCacheEntry> _entries = <String, MediaCacheEntry>{};

  List<MediaCacheEntry> get entries {
    final values = _entries.values.toList(growable: false)
      ..sort(
        (left, right) => right.lastAccessedAt.compareTo(left.lastAccessedAt),
      );
    return List<MediaCacheEntry>.unmodifiable(values);
  }

  int get totalBytes =>
      _entries.values.fold<int>(0, (total, entry) => total + entry.sizeBytes);

  MediaCacheEntry? entryForUrl(String url) {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final entry in _entries.values) {
      if (entry.url == normalized) {
        return entry;
      }
    }
    return null;
  }

  Future<MediaCacheEntry> put({
    required String url,
    required String fileName,
    required String localPath,
    required int sizeBytes,
    String? contentType,
  }) async {
    final now = _clock();
    final normalizedUrl = url.trim();
    final existing = entryForUrl(normalizedUrl);
    if (existing != null) {
      final updated = existing.copyWith(
        fileName: fileName,
        localPath: localPath,
        sizeBytes: sizeBytes,
        contentType: contentType,
        lastAccessedAt: now,
      );
      _entries[existing.id] = updated;
      await enforceLimits();
      return updated;
    }

    final entry = MediaCacheEntry(
      id: _cacheId(normalizedUrl, localPath),
      url: normalizedUrl,
      fileName: fileName,
      localPath: localPath,
      sizeBytes: sizeBytes < 0 ? 0 : sizeBytes,
      createdAt: now,
      lastAccessedAt: now,
      contentType: contentType,
    );
    _entries[entry.id] = entry;
    await enforceLimits();
    return entry;
  }

  Future<MediaCacheEntry?> touch(String url) async {
    final existing = entryForUrl(url);
    if (existing == null) {
      return null;
    }

    final updated = existing.copyWith(lastAccessedAt: _clock());
    _entries[existing.id] = updated;
    return updated;
  }

  Future<void> remove(String id) async {
    final entry = _entries.remove(id);
    if (entry != null) {
      await _delete(entry);
    }
  }

  Future<void> clear() async {
    final removed = _entries.values.toList(growable: false);
    _entries.clear();
    for (final entry in removed) {
      await _delete(entry);
    }
  }

  Future<void> enforceLimits() async {
    final maxEntries = _limits.maxEntries < 0 ? 0 : _limits.maxEntries;
    final maxBytes = _limits.maxBytes < 0 ? 0 : _limits.maxBytes;

    while (_entries.length > maxEntries || totalBytes > maxBytes) {
      final oldest = _entries.values.reduce(
        (left, right) =>
            left.lastAccessedAt.isBefore(right.lastAccessedAt) ? left : right,
      );
      _entries.remove(oldest.id);
      await _delete(oldest);
      if (_entries.isEmpty) {
        break;
      }
    }
  }

  Future<void> _delete(MediaCacheEntry entry) async {
    final deleteFile = _deleteFile;
    if (deleteFile == null || entry.localPath.trim().isEmpty) {
      return;
    }
    await deleteFile(entry.localPath);
  }

  String _cacheId(String url, String localPath) => '$url\x1f$localPath';
}

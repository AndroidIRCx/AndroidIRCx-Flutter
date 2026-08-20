import 'package:androidircx/media/services/media_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evicts least recently used entries by count and byte limits', () async {
    var now = DateTime.utc(2026, 8, 20, 12);
    final deleted = <String>[];
    final service = MediaCacheService(
      limits: const MediaCacheLimits(maxEntries: 2, maxBytes: 100),
      clock: () => now,
      deleteFile: (path) async => deleted.add(path),
    );

    await service.put(
      url: 'https://example.test/a.png',
      fileName: 'a.png',
      localPath: '/cache/a.png',
      sizeBytes: 40,
    );
    now = now.add(const Duration(seconds: 1));
    await service.put(
      url: 'https://example.test/b.png',
      fileName: 'b.png',
      localPath: '/cache/b.png',
      sizeBytes: 40,
    );
    now = now.add(const Duration(seconds: 1));
    await service.touch('https://example.test/a.png');
    now = now.add(const Duration(seconds: 1));
    await service.put(
      url: 'https://example.test/c.png',
      fileName: 'c.png',
      localPath: '/cache/c.png',
      sizeBytes: 40,
    );

    expect(service.entries.map((entry) => entry.fileName), ['c.png', 'a.png']);
    expect(deleted, ['/cache/b.png']);

    now = now.add(const Duration(seconds: 1));
    await service.put(
      url: 'https://example.test/d.png',
      fileName: 'd.png',
      localPath: '/cache/d.png',
      sizeBytes: 80,
    );

    expect(service.entries.map((entry) => entry.fileName), ['d.png']);
    expect(deleted, ['/cache/b.png', '/cache/a.png', '/cache/c.png']);
  });

  test('updates existing url and clears cached files', () async {
    final deleted = <String>[];
    final service = MediaCacheService(
      deleteFile: (path) async => deleted.add(path),
    );

    final first = await service.put(
      url: 'https://example.test/a.png',
      fileName: 'a.png',
      localPath: '/cache/a.png',
      sizeBytes: 10,
    );
    final second = await service.put(
      url: 'https://example.test/a.png',
      fileName: 'a-new.png',
      localPath: '/cache/a-new.png',
      sizeBytes: 20,
    );

    expect(second.id, first.id);
    expect(service.totalBytes, 20);
    expect(
      service.entryForUrl('https://example.test/a.png')!.fileName,
      'a-new.png',
    );

    await service.clear();

    expect(service.entries, isEmpty);
    expect(deleted, ['/cache/a-new.png']);
  });
}

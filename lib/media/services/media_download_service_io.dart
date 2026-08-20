import 'dart:io';

import 'media_download_service.dart';

MediaDownloadService createPlatformMediaDownloadService() {
  return _IoMediaDownloadService();
}

class _IoMediaDownloadService implements MediaDownloadService {
  @override
  Future<MediaDownloadResult> download(
    String url, {
    String? directoryPath,
  }) async {
    final uri = _normalizeMediaDownloadUri(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    File? file;
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Media download failed with HTTP ${response.statusCode}.',
          uri: uri,
        );
      }

      final fileName = _mediaFileNameFor(uri, response);
      final directory =
          await _prepareConfiguredDirectory(directoryPath) ??
          await _prepareDefaultMediaDirectory();
      file = await _createDuplicateSafeFile(directory, fileName);
      sink = file.openWrite(mode: FileMode.writeOnly);
      var bytesDownloaded = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        bytesDownloaded += chunk.length;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return MediaDownloadResult(
        url: uri.toString(),
        fileName: file.uri.pathSegments.isEmpty
            ? fileName
            : file.uri.pathSegments.last,
        localPath: file.path,
        bytesDownloaded: bytesDownloaded,
        contentType: response.headers.contentType?.toString(),
      );
    } catch (_) {
      await sink?.close();
      if (file != null && await file.exists()) {
        await file.delete();
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}

Uri _normalizeMediaDownloadUri(String rawUrl) {
  final normalized = rawUrl.contains('://') ? rawUrl : 'https://$rawUrl';
  final uri = Uri.tryParse(normalized);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw ArgumentError.value(
      rawUrl,
      'url',
      'Only HTTP(S) media URLs are supported.',
    );
  }
  return uri;
}

String _mediaFileNameFor(Uri uri, HttpClientResponse response) {
  final headerFileName = _fileNameFromContentDisposition(
    response.headers.value('content-disposition'),
  );
  if (headerFileName != null && headerFileName.trim().isNotEmpty) {
    return _sanitizeMediaFileName(headerFileName);
  }
  final pathName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  return _sanitizeMediaFileName(
    pathName.trim().isEmpty ? 'media-download.bin' : pathName,
  );
}

String? _fileNameFromContentDisposition(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final parts = value.split(';');
  String? fallback;
  for (final part in parts) {
    final separator = part.indexOf('=');
    if (separator == -1) {
      continue;
    }
    final key = part.substring(0, separator).trim().toLowerCase();
    var itemValue = part.substring(separator + 1).trim();
    if (itemValue.length >= 2 &&
        itemValue.startsWith('"') &&
        itemValue.endsWith('"')) {
      itemValue = itemValue.substring(1, itemValue.length - 1);
    }
    if (key == 'filename*') {
      final utf8Prefix = "UTF-8''";
      if (itemValue.toUpperCase().startsWith(utf8Prefix)) {
        return Uri.decodeComponent(itemValue.substring(utf8Prefix.length));
      }
      return Uri.decodeComponent(itemValue);
    }
    if (key == 'filename') {
      fallback = itemValue;
    }
  }
  return fallback;
}

String _sanitizeMediaFileName(String fileName) {
  final sanitized = fileName
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  return sanitized.isEmpty ? 'media-download.bin' : sanitized;
}

Future<Directory?> _prepareConfiguredDirectory(String? directoryPath) async {
  final normalized = directoryPath?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  try {
    final directory = Directory(normalized);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final probe = File(
      '${directory.path}${Platform.pathSeparator}.androidircx-media-write-${DateTime.now().microsecondsSinceEpoch}',
    );
    await probe.writeAsString('ok');
    await probe.delete();
    return directory;
  } on FileSystemException {
    return null;
  }
}

Future<Directory> _prepareDefaultMediaDirectory() async {
  final directory = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}androidircx-media',
  );
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<File> _createDuplicateSafeFile(
  Directory directory,
  String fileName,
) async {
  final extensionStart = fileName.lastIndexOf('.');
  final hasExtension =
      extensionStart > 0 && extensionStart < fileName.length - 1;
  final baseName = hasExtension
      ? fileName.substring(0, extensionStart)
      : fileName;
  final extension = hasExtension ? fileName.substring(extensionStart) : '';

  for (var index = 0; ; index += 1) {
    final suffix = index == 0 ? '' : '-$index';
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}$baseName$suffix$extension',
    );
    try {
      return await candidate.create(exclusive: true);
    } on FileSystemException {
      if (!await candidate.exists()) {
        rethrow;
      }
    }
  }
}

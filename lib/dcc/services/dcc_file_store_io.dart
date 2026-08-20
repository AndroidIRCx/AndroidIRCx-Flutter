import 'dart:io';

import 'dcc_file_store.dart';

class _IoDccFileSink implements DccFileSink {
  _IoDccFileSink(this._sink);

  final IOSink _sink;

  @override
  void add(List<int> bytes) {
    _sink.add(bytes);
  }

  @override
  Future<void> close() => _sink.close();

  @override
  Future<void> flush() => _sink.flush();
}

Future<DccTempFile> createPlatformDccTempFile(
  String fileName, {
  String? directoryPath,
}) async {
  final sanitized = _sanitizeDccFileName(fileName);
  final directory =
      await _prepareConfiguredDirectory(directoryPath) ??
      await _prepareDefaultDccDirectory();
  final file = await _createDuplicateSafeFile(directory, sanitized);
  final sink = file.openWrite(mode: FileMode.writeOnly);
  return (
    path: file.path,
    sink: _IoDccFileSink(sink),
    delete: () async {
      if (await file.exists()) {
        await file.delete();
      }
    },
  );
}

String _sanitizeDccFileName(String fileName) {
  final sanitized = fileName
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ');
  return sanitized.isEmpty ? 'dcc-download.bin' : sanitized;
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
      '${directory.path}${Platform.pathSeparator}.androidircx-dcc-write-${DateTime.now().microsecondsSinceEpoch}',
    );
    await probe.writeAsString('ok');
    await probe.delete();
    return directory;
  } on FileSystemException {
    return null;
  }
}

Future<Directory> _prepareDefaultDccDirectory() async {
  final directory = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}androidircx-dcc',
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
      continue;
    }
  }
}

Future<DccSourceFile> openPlatformDccSourceFile(String path) async {
  final file = File(path);
  final exists = await file.exists();
  if (!exists) {
    throw FileSystemException('DCC source file does not exist.', path);
  }

  final stat = await file.stat();
  return (
    path: file.path,
    fileName: file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last,
    size: stat.size,
    openRead: file.openRead,
  );
}

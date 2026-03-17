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

Future<DccTempFile> createPlatformDccTempFile(String fileName) async {
  final sanitized = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final path = '${Directory.systemTemp.path}/$sanitized';
  final file = File(path);
  final sink = file.openWrite(mode: FileMode.writeOnly);
  return (path: path, sink: _IoDccFileSink(sink));
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
    fileName: file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last,
    size: stat.size,
    readAllBytes: file.readAsBytes,
  );
}

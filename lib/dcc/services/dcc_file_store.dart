import 'dcc_file_store_stub.dart' if (dart.library.io) 'dcc_file_store_io.dart';

abstract class DccFileSink {
  void add(List<int> bytes);

  Future<void> flush();

  Future<void> close();
}

typedef DccTempFile = ({
  String path,
  DccFileSink sink,
  Future<void> Function() delete,
});
typedef DccSourceFile = ({
  String path,
  String fileName,
  int size,
  Stream<List<int>> Function() openRead,
});

Future<DccTempFile> createDccTempFile(String fileName) =>
    createPlatformDccTempFile(fileName);

Future<DccSourceFile> openDccSourceFile(String path) =>
    openPlatformDccSourceFile(path);

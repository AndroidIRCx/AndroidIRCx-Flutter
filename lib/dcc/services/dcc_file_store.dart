import 'dcc_file_store_stub.dart' if (dart.library.io) 'dcc_file_store_io.dart';

abstract class DccFileSink {
  void add(List<int> bytes);

  Future<void> flush();

  Future<void> close();
}

typedef DccTempFile = ({String path, DccFileSink sink});
typedef DccSourceFile = ({
  String path,
  String fileName,
  int size,
  Future<List<int>> Function() readAllBytes,
});

Future<DccTempFile> createDccTempFile(String fileName) => createPlatformDccTempFile(fileName);

Future<DccSourceFile> openDccSourceFile(String path) => openPlatformDccSourceFile(path);

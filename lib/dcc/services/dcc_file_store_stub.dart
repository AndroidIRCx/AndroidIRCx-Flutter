import 'dcc_file_store.dart';

Future<DccTempFile> createPlatformDccTempFile(String fileName) async {
  throw UnsupportedError('DCC file storage is only supported on IO platforms.');
}

Future<DccSourceFile> openPlatformDccSourceFile(String path) async {
  throw UnsupportedError('Outgoing DCC SEND is only supported on IO platforms.');
}

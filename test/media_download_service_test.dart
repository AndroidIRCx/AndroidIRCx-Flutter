import 'dart:io';

import 'package:androidircx/media/services/media_download_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'downloads media files into duplicate-safe configured directories',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'androidircx-media-test-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      server.listen((request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'pdf',
        );
        request.response.write('manual');
        await request.response.close();
      });

      final service = createMediaDownloadService();
      final url = 'http://${server.address.address}:${server.port}/manual.pdf';

      final first = await service.download(url, directoryPath: directory.path);
      final second = await service.download(url, directoryPath: directory.path);

      expect(first.fileName, 'manual.pdf');
      expect(second.fileName, 'manual-1.pdf');
      expect(first.bytesDownloaded, 6);
      expect(await File(first.localPath).readAsString(), 'manual');
      expect(await File(second.localPath).readAsString(), 'manual');
    },
  );
}

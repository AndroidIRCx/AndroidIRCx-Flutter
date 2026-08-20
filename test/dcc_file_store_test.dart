import 'dart:io';

import 'package:androidircx/dcc/services/dcc_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates duplicate-safe sanitized temp files', () async {
    final first = await createDccTempFile('folder:bad/name?.txt');
    final second = await createDccTempFile('folder:bad/name?.txt');

    try {
      first.sink.add(<int>[1, 2, 3]);
      second.sink.add(<int>[4, 5, 6]);
      await first.sink.close();
      await second.sink.close();

      expect(first.path, isNot(second.path));
      expect(first.path, isNot(contains('?')));
      expect(second.path, isNot(contains('?')));
      expect(await File(first.path).exists(), isTrue);
      expect(await File(second.path).exists(), isTrue);
    } finally {
      await first.delete();
      await second.delete();
    }
  });

  test('uses configured download directories when writable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'androidircx-dcc-custom-',
    );
    final file = await createDccTempFile(
      'picked.txt',
      directoryPath: directory.path,
    );

    try {
      file.sink.add(<int>[1]);
      await file.sink.close();

      expect(file.path, startsWith(directory.path));
      expect(await File(file.path).exists(), isTrue);
    } finally {
      await file.delete();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });
}

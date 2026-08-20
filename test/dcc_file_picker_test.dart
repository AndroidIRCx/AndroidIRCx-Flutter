import 'package:androidircx/dcc/services/dcc_file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('androidircx/dcc_file_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('returns selected file path from platform channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickFile');
      return '  /tmp/androidircx-dcc.txt  ';
    });

    final picker = const MethodChannelDccFilePicker();

    expect(await picker.pickFile(), '/tmp/androidircx-dcc.txt');
  });

  test('returns null when picker is cancelled', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    final picker = const MethodChannelDccFilePicker();

    expect(await picker.pickFile(), isNull);
  });

  test('returns null when platform implementation is unavailable', () async {
    final picker = const MethodChannelDccFilePicker();

    expect(await picker.pickFile(), isNull);
  });
}

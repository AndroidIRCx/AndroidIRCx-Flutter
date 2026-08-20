import 'package:flutter/services.dart';

abstract class DccFilePicker {
  Future<String?> pickFile();
}

class MethodChannelDccFilePicker implements DccFilePicker {
  const MethodChannelDccFilePicker();

  static const MethodChannel _channel = MethodChannel(
    'androidircx/dcc_file_picker',
  );

  @override
  Future<String?> pickFile() async {
    try {
      final path = await _channel.invokeMethod<String>('pickFile');
      final normalized = path?.trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    } on MissingPluginException {
      return null;
    }
  }
}

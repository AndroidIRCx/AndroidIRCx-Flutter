import 'dart:convert';

import 'package:androidircx/irc/parser/mirc_preset_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes utf8 mirc preset base64', () {
    final decoded = decodeMircPresetBase64(
      base64.encode(utf8.encode('line1\nline2')),
    );
    expect(decoded, 'line1\nline2');
  });

  test('parses generic presets', () {
    final presets = parseGenericPresets('one\ntwo');
    expect(presets, hasLength(2));
    expect(presets.first.raw, 'one');
  });

  test('parses nick completion presets with on off suffix', () {
    final presets = parseNickCompletionPresets('nick1 on\nnick2 off');
    expect(presets.first.enabled, isTrue);
    expect(presets.last.enabled, isFalse);
  });

  test('parses ircap decoration eti values', () {
    final parsed = parseIrcapDecorationEti(
      'a\x08b\x08c\x08d\x08e\x08f\x08prefix\x08suffix\x08z',
    );

    expect(parsed, contains('prefix\x08suffix'));
  });
}

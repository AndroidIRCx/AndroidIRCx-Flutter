import 'dart:convert';

import 'package:androidircx/features/chat/data/history_payload_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final key = base64Encode(List<int>.filled(32, 3));

  test('round-trips plaintext through AES-256-GCM', () async {
    final codec = AesGcmHistoryPayloadCodec.fromBase64Key(key);
    final cipher = await codec.encrypt('hello #room secret message');
    // The stored envelope must not contain the plaintext.
    expect(cipher.contains('hello'), isFalse);
    expect(cipher.contains('secret'), isFalse);
    expect(await codec.decrypt(cipher), 'hello #room secret message');
  });

  test(
    'uses a fresh random nonce so equal plaintext differs on disk',
    () async {
      final codec = AesGcmHistoryPayloadCodec.fromBase64Key(key);
      final a = await codec.encrypt('same');
      final b = await codec.encrypt('same');
      expect(a, isNot(b));
      expect(await codec.decrypt(a), 'same');
      expect(await codec.decrypt(b), 'same');
    },
  );

  test('a wrong key cannot decrypt (tamper/theft protection)', () async {
    final codec = AesGcmHistoryPayloadCodec.fromBase64Key(key);
    final cipher = await codec.encrypt('private history');
    final wrong = AesGcmHistoryPayloadCodec.fromBase64Key(
      base64Encode(List<int>.filled(32, 9)),
    );
    await expectLater(wrong.decrypt(cipher), throwsA(anything));
  });
}

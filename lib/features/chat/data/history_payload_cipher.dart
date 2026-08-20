import 'dart:convert';

import 'package:androidircx/features/chat/data/history_database.dart';
import 'package:cryptography/cryptography.dart';

/// AES-256-GCM codec for message payloads, keyed by the base64 database key
/// released by `HistoryEncryptionKeyManager` after biometric/PIN unlock.
///
/// Each payload is stored as a small JSON envelope carrying a fresh random
/// nonce, the ciphertext, and the GCM authentication tag, all base64-encoded.
class AesGcmHistoryPayloadCodec implements HistoryPayloadCodec {
  AesGcmHistoryPayloadCodec(List<int> keyBytes)
      : _secretKey = SecretKey(keyBytes);

  factory AesGcmHistoryPayloadCodec.fromBase64Key(String base64Key) {
    return AesGcmHistoryPayloadCodec(base64Decode(base64Key));
  }

  final SecretKey _secretKey;
  final AesGcm _algorithm = AesGcm.with256bits();

  @override
  Future<String> encrypt(String plaintext) async {
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: _secretKey,
    );
    return jsonEncode({
      'n': base64Encode(secretBox.nonce),
      'c': base64Encode(secretBox.cipherText),
      'm': base64Encode(secretBox.mac.bytes),
    });
  }

  @override
  Future<String> decrypt(String ciphertext) async {
    final envelope = jsonDecode(ciphertext) as Map<String, Object?>;
    final secretBox = SecretBox(
      base64Decode(envelope['c']! as String),
      nonce: base64Decode(envelope['n']! as String),
      mac: Mac(base64Decode(envelope['m']! as String)),
    );
    final clear = await _algorithm.decrypt(secretBox, secretKey: _secretKey);
    return utf8.decode(clear);
  }
}

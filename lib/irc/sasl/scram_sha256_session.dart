import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class ScramSha256Session {
  ScramSha256Session({
    required this.username,
    required this.password,
    String Function()? nonceGenerator,
  }) : _nonceGenerator = nonceGenerator ?? _defaultNonceGenerator;

  final String username;
  final String password;
  final String Function() _nonceGenerator;
  String? get expectedServerSignature => _expectedServerSignature;

  String? _clientFirstBare;
  String? _expectedServerSignature;

  String createClientFirstMessage() {
    final nonce = _nonceGenerator();
    _clientFirstBare = 'n=${_escape(username)},r=$nonce';
    return 'n,,$_clientFirstBare';
  }

  String createClientFinalMessage(String serverFirstMessage) {
    final attributes = _parseAttributes(serverFirstMessage);
    final nonce = attributes['r'];
    final salt = attributes['s'];
    final iterationText = attributes['i'];
    final clientFirstBare = _clientFirstBare;
    if (nonce == null ||
        salt == null ||
        iterationText == null ||
        clientFirstBare == null) {
      throw const FormatException('Invalid SCRAM server-first message.');
    }

    if (!nonce.startsWith(_parseAttributes(clientFirstBare)['r']!)) {
      throw const FormatException('SCRAM nonce mismatch.');
    }

    final iterations = int.tryParse(iterationText);
    if (iterations == null || iterations <= 0) {
      throw const FormatException('Invalid SCRAM iteration count.');
    }

    final clientFinalWithoutProof = 'c=biws,r=$nonce';
    final authMessage =
        '$clientFirstBare,$serverFirstMessage,$clientFinalWithoutProof';
    final saltedPassword = _pbkdf2Sha256(
      utf8.encode(password),
      base64.decode(salt),
      iterations,
    );
    final clientKey = _hmacSha256(saltedPassword, utf8.encode('Client Key'));
    final storedKey = sha256.convert(clientKey).bytes;
    final clientSignature =
        _hmacSha256(storedKey, utf8.encode(authMessage));
    final clientProof = _xor(clientKey, clientSignature);
    final serverKey = _hmacSha256(saltedPassword, utf8.encode('Server Key'));
    final serverSignature =
        _hmacSha256(serverKey, utf8.encode(authMessage));
    _expectedServerSignature = base64.encode(serverSignature);

    return '$clientFinalWithoutProof,p=${base64.encode(clientProof)}';
  }

  bool validateServerFinalMessage(String serverFinalMessage) {
    final expected = _expectedServerSignature;
    if (expected == null) {
      return false;
    }

    final attributes = _parseAttributes(serverFinalMessage);
    final verification = attributes['v'];
    return verification != null && verification == expected;
  }

  static String _defaultNonceGenerator() {
    final random = Random.secure();
    final bytes =
        List<int>.generate(18, (_) => random.nextInt(256), growable: false);
    return base64.encode(bytes).replaceAll('=', '');
  }

  static String _escape(String input) {
    return input.replaceAll('=', '=3D').replaceAll(',', '=2C');
  }

  static Map<String, String> _parseAttributes(String message) {
    final attributes = <String, String>{};
    for (final part in message.split(',')) {
      if (part.length < 3 || part[1] != '=') {
        continue;
      }
      attributes[part[0]] = part.substring(2);
    }
    return attributes;
  }

  static List<int> _hmacSha256(List<int> key, List<int> data) {
    return Hmac(sha256, key).convert(data).bytes;
  }

  static List<int> _pbkdf2Sha256(
    List<int> password,
    List<int> salt,
    int iterations,
  ) {
    final blockIndex = Uint8List.fromList([
      ...salt,
      0,
      0,
      0,
      1,
    ]);
    var u = _hmacSha256(password, blockIndex);
    final output = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = _hmacSha256(password, u);
      for (var j = 0; j < output.length; j++) {
        output[j] ^= u[j];
      }
    }
    return output;
  }

  static List<int> _xor(List<int> left, List<int> right) {
    return List<int>.generate(
      left.length,
      (index) => left[index] ^ right[index],
      growable: false,
    );
  }
}

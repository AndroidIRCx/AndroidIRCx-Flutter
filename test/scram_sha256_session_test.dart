import 'package:androidircx/irc/sasl/scram_sha256_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds and validates SCRAM-SHA-256 exchange', () {
    final session = ScramSha256Session(
      username: 'alice',
      password: 'secret',
      nonceGenerator: () => 'fixedNonce',
    );

    final clientFirst = session.createClientFirstMessage();
    expect(clientFirst, 'n,,n=alice,r=fixedNonce');

    final clientFinal = session.createClientFinalMessage(
      'r=fixedNonceServer,s=c2FsdHlTYWx0,i=4096',
    );
    expect(clientFinal, startsWith('c=biws,r=fixedNonceServer,p='));

    final serverFinal = 'v=${session.expectedServerSignature}';
    expect(session.validateServerFinalMessage(serverFinal), isTrue);
    expect(session.validateServerFinalMessage('v=invalid'), isFalse);
  });

  group('interop fixtures', () {
    test('matches the official RFC 7677 SCRAM-SHA-256 test vector', () {
      // RFC 7677 section 3: username "user", password "pencil",
      // client nonce "rOprNGfwEbeRWgbNEkqO". This is the canonical
      // interop vector shared with real servers and libsodium clients.
      final session = ScramSha256Session(
        username: 'user',
        password: 'pencil',
        nonceGenerator: () => 'rOprNGfwEbeRWgbNEkqO',
      );

      expect(
        session.createClientFirstMessage(),
        'n,,n=user,r=rOprNGfwEbeRWgbNEkqO',
      );

      final clientFinal = session.createClientFinalMessage(
        'r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0,'
        's=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096',
      );
      expect(
        clientFinal,
        'c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF\$k0,'
        'p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=',
      );

      expect(
        session.validateServerFinalMessage(
          'v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=',
        ),
        isTrue,
      );
    });

    test('escapes "=" and "," in the username per SCRAM rules', () {
      final session = ScramSha256Session(
        username: 'user,=name',
        password: 'secret',
        nonceGenerator: () => 'fixedNonce',
      );
      expect(
        session.createClientFirstMessage(),
        'n,,n=user=2C=3Dname,r=fixedNonce',
      );
    });

    test('is self-consistent for a high iteration count', () {
      final session = ScramSha256Session(
        username: 'alice',
        password: 'hunter2',
        nonceGenerator: () => 'clientNonce',
      );
      session.createClientFirstMessage();
      session.createClientFinalMessage(
        'r=clientNonceServer,s=c2FsdHlTYWx0,i=8192',
      );
      expect(
        session.validateServerFinalMessage(
          'v=${session.expectedServerSignature}',
        ),
        isTrue,
      );
    });

    test('rejects a server nonce that does not extend the client nonce', () {
      final session = ScramSha256Session(
        username: 'alice',
        password: 'secret',
        nonceGenerator: () => 'clientNonce',
      );
      session.createClientFirstMessage();
      expect(
        () => session.createClientFinalMessage(
          'r=totallyDifferent,s=c2FsdHlTYWx0,i=4096',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an iteration count below the SCRAM minimum', () {
      final session = ScramSha256Session(
        username: 'alice',
        password: 'secret',
        nonceGenerator: () => 'clientNonce',
      );
      session.createClientFirstMessage();
      expect(
        () => session.createClientFinalMessage(
          'r=clientNonceServer,s=c2FsdHlTYWx0,i=10',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a malformed server-first message missing the salt', () {
      final session = ScramSha256Session(
        username: 'alice',
        password: 'secret',
        nonceGenerator: () => 'clientNonce',
      );
      session.createClientFirstMessage();
      expect(
        () => session.createClientFinalMessage('r=clientNonceServer,i=4096'),
        throwsA(isA<FormatException>()),
      );
    });

    test('treats a server-error final (e=) as verification failure', () {
      final session = ScramSha256Session(
        username: 'alice',
        password: 'secret',
        nonceGenerator: () => 'clientNonce',
      );
      session.createClientFirstMessage();
      session.createClientFinalMessage(
        'r=clientNonceServer,s=c2FsdHlTYWx0,i=4096',
      );
      expect(
        session.validateServerFinalMessage('e=invalid-proof'),
        isFalse,
      );
    });
  });
}

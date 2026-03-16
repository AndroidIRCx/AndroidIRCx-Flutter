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
}

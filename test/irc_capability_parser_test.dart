import 'package:androidircx/irc/parser/irc_capability_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses capability names and values in order', () {
    final tokens = parseIrcCapabilityTokens(
      'multi-prefix sasl=PLAIN,SCRAM-SHA-256,EXTERNAL draft/example=one=two',
    );

    expect(tokens, hasLength(3));
    expect(tokens[0].name, 'multi-prefix');
    expect(tokens[0].value, isNull);
    expect(tokens[1].name, 'sasl');
    expect(tokens[1].value, 'PLAIN,SCRAM-SHA-256,EXTERNAL');
    expect(tokens[2].name, 'draft/example');
    expect(tokens[2].value, 'one=two');
  });

  test('strips disable prefix only when requested', () {
    final disabled = parseIrcCapabilityTokens(
      '-echo-message sasl=PLAIN',
      allowDisablePrefix: true,
    );
    final literal = parseIrcCapabilityTokens('-echo-message');

    expect(disabled[0].name, 'echo-message');
    expect(disabled[0].disabled, isTrue);
    expect(disabled[1].name, 'sasl');
    expect(disabled[1].disabled, isFalse);
    expect(literal.single.name, '-echo-message');
    expect(literal.single.disabled, isFalse);
  });

  test('parses comma separated capability values case-insensitively', () {
    expect(parseIrcCapabilityValueList('plain, SCRAM-SHA-256,,external'), {
      'PLAIN',
      'SCRAM-SHA-256',
      'EXTERNAL',
    });
    expect(parseIrcCapabilityValueList(null), isEmpty);
    expect(parseIrcCapabilityValueList(''), isEmpty);
  });
}

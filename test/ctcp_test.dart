import 'package:androidircx/irc/parser/ctcp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses CTCP command with args', () {
    final parsed = parseCtcp('\u0001VERSION AndroidIRCX\u0001');

    expect(parsed.isCtcp, isTrue);
    expect(parsed.command, 'VERSION');
    expect(parsed.args, 'AndroidIRCX');
  });

  test('parses CTCP ACTION', () {
    final parsed = parseCtcp('\u0001ACTION waves\u0001');

    expect(parsed.isCtcp, isTrue);
    expect(parsed.command, 'ACTION');
    expect(parsed.args, 'waves');
  });

  test('returns non-ctcp for regular text', () {
    final parsed = parseCtcp('hello');

    expect(parsed.isCtcp, isFalse);
    expect(parsed.command, isNull);
    expect(parsed.args, isNull);
  });

  test('encodes CTCP command', () {
    expect(encodeCtcp('ping', '123'), '\u0001PING 123\u0001');
  });
}

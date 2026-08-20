import 'package:androidircx/irc/parser/irc_sts_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses STS port duration and preload directives', () {
    final directive = parseIrcStsDirective(
      'unknown,duration=31536000,port=6697,preload',
    );

    expect(directive.port, 6697);
    expect(directive.durationSeconds, 31536000);
    expect(directive.preload, isTrue);
  });

  test('ignores invalid STS numeric values', () {
    final directive = parseIrcStsDirective(
      'duration=-1,port=70000,preload=yes',
    );

    expect(directive.port, isNull);
    expect(directive.durationSeconds, isNull);
    expect(directive.preload, isTrue);
  });

  test('keeps zero duration for policy clearing', () {
    final directive = parseIrcStsDirective('duration=0');

    expect(directive.durationSeconds, 0);
  });
}

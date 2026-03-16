import 'package:androidircx/irc/parser/irc_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses IRC formatting into styled segments', () {
    final segments = parseIrcText('Hello \u0002bold\u0002 and \u001ditalic\u001d');

    expect(segments, hasLength(4));
    expect(segments[0].text, 'Hello ');
    expect(segments[1].text, 'bold');
    expect(segments[1].style.bold, isTrue);
    expect(segments[2].text, ' and ');
    expect(segments[3].text, 'italic');
    expect(segments[3].style.italic, isTrue);
  });

  test('strips IRC formatting codes', () {
    expect(
      stripIrcFormatting('\u000304,01Red on black\u000f plain'),
      'Red on black plain',
    );
  });

  test('formats IRC debug markers', () {
    expect(
      formatIrcDebug('\u0002Bold\u000f'),
      '[B]Bold[R]',
    );
  });

  test('parses IRC formatted links', () {
    final segments = parseIrcTextWithLinks(
      'See \u0002www.androidircx.com\u000f now',
    );

    expect(segments.any((segment) => segment.isLink), isTrue);
    final link = segments.firstWhere((segment) => segment.isLink);
    expect(link.text, 'www.androidircx.com');
    expect(link.url, 'https://www.androidircx.com');
    expect(link.style.bold, isTrue);
  });
}

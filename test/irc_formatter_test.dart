import 'package:androidircx/irc/parser/irc_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses IRC formatting into styled segments', () {
    final segments = parseIrcText(
      'Hello \u0002bold\u0002 and \u001ditalic\u001d',
    );

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

  test('handles mIRC hex colors and monospace formatting', () {
    final segments = parseIrcText(
      '\u0004ff8800,001122orange\u0004 mono \u0011code\u0011',
    );

    expect(segments[0].text, 'orange');
    expect(segments[0].style.colorHex, '#FF8800');
    expect(segments[0].style.backgroundHex, '#001122');
    expect(segments[1].text, ' mono ');
    expect(segments[1].style.colorHex, isNull);
    expect(segments[2].text, 'code');
    expect(segments[2].style.monospace, isTrue);
    expect(
      stripIrcFormatting(
        '\u0004ff8800,001122orange\u0004 mono \u0011code\u0011',
      ),
      'orange mono code',
    );
  });

  test('keeps comma literal when color background is missing', () {
    expect(stripIrcFormatting('x\u000304,y'), 'x,y');
    expect(parseIrcText('x\u000304,y').last.text, ',y');
  });

  test('formats plain text for search export and notifications', () {
    expect(
      formatIrcPlainText(
        '  Hello \u0002bold\u0002\nIRC  ',
        collapseWhitespace: true,
      ),
      'Hello bold IRC',
    );
  });

  test('formats IRC debug markers', () {
    expect(
      formatIrcDebug('\u0002Bold\u000f \u0011code\u0011 \u0004ff0000red'),
      '[B]Bold[R] [M]code[M] [HC#FF0000]red',
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

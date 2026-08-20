import 'package:androidircx/irc/parser/irc_message_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses prefixed privmsg with trailing body', () {
    final frame = parseIrcMessage(
      ':nick!user@host PRIVMSG #flutter :hello world',
    );

    expect(frame.prefix, 'nick!user@host');
    expect(frame.command, 'PRIVMSG');
    expect(frame.params, ['#flutter']);
    expect(frame.trailing, 'hello world');
    expect(frame.senderNick, 'nick');
  });

  test('parses ping payload', () {
    final frame = parseIrcMessage('PING :server.example');

    expect(frame.command, 'PING');
    expect(frame.params, isEmpty);
    expect(frame.trailing, 'server.example');
  });

  test('parses IRCv3 message tags and server-time', () {
    final frame = parseIrcMessage(
      '@time=2026-03-17T10:11:12.000Z;+draft/example=hello\\sworld :nick!user@host PRIVMSG #flutter :hi',
    );

    expect(frame.tags['time'], '2026-03-17T10:11:12.000Z');
    expect(frame.tags['+draft/example'], 'hello world');
    expect(frame.command, 'PRIVMSG');
    expect(frame.trailing, 'hi');
  });

  test('parses IRCv3 tag escaping edge cases', () {
    final frame = parseIrcMessage(
      r'@semi=a\:b;space=a\sb;slash=a\\b;cr=a\rb;lf=a\nb;empty;blank= PRIVMSG #c :body',
    );

    expect(frame.tags['semi'], 'a;b');
    expect(frame.tags['space'], 'a b');
    expect(frame.tags['slash'], r'a\b');
    expect(frame.tags['cr'], 'a\rb');
    expect(frame.tags['lf'], 'a\nb');
    expect(frame.tags['empty'], isNull);
    expect(frame.tags['blank'], '');
    expect(frame.command, 'PRIVMSG');
    expect(frame.params, ['#c']);
    expect(frame.trailing, 'body');
  });

  test('keeps the first duplicate IRCv3 message tag', () {
    final frame = parseIrcMessage(
      '@time=first;time=second;msgid=abc PRIVMSG #c :body',
    );

    expect(frame.tags['time'], 'first');
    expect(frame.tags['msgid'], 'abc');
  });

  test('preserves significant trailing spaces before CRLF', () {
    final frame = parseIrcMessage('PRIVMSG #c :hello   \r\n');

    expect(frame.command, 'PRIVMSG');
    expect(frame.params, ['#c']);
    expect(frame.trailing, 'hello   ');
  });

  test('handles repeated spaces around tags prefix params and trailing', () {
    final frame = parseIrcMessage(
      '@time=2026-03-17T10:11:12.000Z   :nick!user@host   PRIVMSG   #flutter   :hello world',
    );

    expect(frame.tags['time'], '2026-03-17T10:11:12.000Z');
    expect(frame.prefix, 'nick!user@host');
    expect(frame.command, 'PRIVMSG');
    expect(frame.params, ['#flutter']);
    expect(frame.trailing, 'hello world');
  });

  test('returns empty command for empty and incomplete frames', () {
    expect(parseIrcMessage('').command, '');
    expect(parseIrcMessage('   ').command, '');
    expect(parseIrcMessage('@time=2026-03-17T10:11:12.000Z').command, '');
    expect(parseIrcMessage(':nick!user@host').command, '');
  });
}

import 'package:androidircx/irc/parser/irc_message_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses prefixed privmsg with trailing body', () {
    final frame = parseIrcMessage(':nick!user@host PRIVMSG #flutter :hello world');

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
}

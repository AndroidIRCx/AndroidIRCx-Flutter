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
}

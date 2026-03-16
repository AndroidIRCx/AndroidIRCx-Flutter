import 'package:androidircx/irc/parser/irc_url_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses ircs url with query overrides', () {
    final parsed = parseIrcUrl(
      'ircs://nick:secret@irc.example.com:6697/androidircx?nick=AndroidIRCX&altNick=AndroidIRCX_&ident=androidircx',
    );

    expect(parsed.isValid, isTrue);
    expect(parsed.ssl, isTrue);
    expect(parsed.server, 'irc.example.com');
    expect(parsed.port, 6697);
    expect(parsed.nick, 'AndroidIRCX');
    expect(parsed.altNick, 'AndroidIRCX_');
    expect(parsed.ident, 'androidircx');
    expect(parsed.channel, '#androidircx');
  });

  test('rejects invalid port', () {
    final parsed = parseIrcUrl('irc://irc.example.com:99999/test');
    expect(parsed.isValid, isFalse);
    expect(parsed.error, contains('Invalid port'));
  });

  test('creates temporary network config', () {
    final parsed = parseIrcUrl('irc://irc.example.com/flutter');
    final network = toTemporaryNetworkConfig(parsed);

    expect(network.host, 'irc.example.com');
    expect(network.port, 6667);
    expect(network.nickname, 'AndroidIRCX');
  });
}

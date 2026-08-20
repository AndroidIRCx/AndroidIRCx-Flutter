import 'package:androidircx/irc/parser/irc_message_parser.dart';
import 'package:androidircx/irc/parser/isupport_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses common ISUPPORT values', () {
    final support = parseIrcServerSupport(<String>[
      'CHANTYPES=#&',
      'PREFIX=(qaohv)~&@%+',
      r'NETWORK=Example\x20Network',
      'CASEMAPPING=ascii',
      'CHANMODES=beI,k,l,imnpst',
    ]);

    expect(support.channelTypes, '#&');
    expect(support.nickPrefixModes, 'qaohv');
    expect(support.nickPrefixSymbols, '~&@%+');
    expect(support.networkName, 'Example Network');
    expect(support.caseMapping, 'ascii');
    expect(support.channelModes, 'beI,k,l,imnpst');
  });

  test('uses documented defaults only when tokens are absent', () {
    final empty = const IrcServerSupport.empty();
    final explicitEmpty = empty.mergeTokens(<String>['CHANTYPES', 'PREFIX']);

    expect(empty.channelTypes, '#&');
    expect(empty.nickPrefixModes, 'ov');
    expect(empty.nickPrefixSymbols, '@+');
    expect(empty.caseMapping, 'rfc1459');
    expect(explicitEmpty.channelTypes, '');
    expect(explicitEmpty.nickPrefixModes, '');
    expect(explicitEmpty.nickPrefixSymbols, '');
  });

  test('removes advertised tokens and ignores 005 trailing text', () {
    final frame = parseIrcMessage(
      ':server 005 AndroidIRCX CHANTYPES=# PREFIX=(ov)@+ NETWORK=DBase :are supported by this server',
    );
    final support = const IrcServerSupport.empty()
        .mergeFrame(frame)
        .mergeTokens(<String>['-NETWORK']);

    expect(isupportTokensFromFrame(frame), [
      'CHANTYPES=#',
      'PREFIX=(ov)@+',
      'NETWORK=DBase',
    ]);
    expect(support.channelTypes, '#');
    expect(support.nickPrefixModes, 'ov');
    expect(support.nickPrefixSymbols, '@+');
    expect(support.networkName, isNull);
  });

  test('rejects invalid PREFIX mapping', () {
    final support = parseIrcServerSupport(<String>['PREFIX=(ov)@']);

    expect(support.nickPrefixModes, '');
    expect(support.nickPrefixSymbols, '');
  });
}

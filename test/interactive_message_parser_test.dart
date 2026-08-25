import 'package:androidircx/irc/parser/interactive_message_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps IRC style while exposing links, channels, and nicks', () {
    final tokens = parseInteractiveMessageTokens(
      'Hi \u0002Alice\u0002 join #flutter and https://example.com',
      knownNicks: const ['Alice'],
    );

    final nick = tokens.firstWhere(
      (token) => token.type == InteractiveMessageTokenType.nick,
    );
    expect(nick.text, 'Alice');
    expect(nick.value, 'Alice');
    expect(nick.style.bold, isTrue);

    final channel = tokens.firstWhere(
      (token) => token.type == InteractiveMessageTokenType.channel,
    );
    expect(channel.text, '#flutter');
    expect(channel.value, '#flutter');

    final link = tokens.firstWhere(
      (token) => token.type == InteractiveMessageTokenType.url,
    );
    expect(link.text, 'https://example.com');
    expect(link.url, 'https://example.com');
  });

  test('preserves punctuation around channels and nicks', () {
    final tokens = parseInteractiveMessageTokens(
      '(@bob), check #ops:',
      knownNicks: const ['bob'],
    );

    expect(tokens.map((token) => token.text).join(), '(@bob), check #ops:');
    expect(
      tokens.where((token) => token.type == InteractiveMessageTokenType.nick),
      hasLength(1),
    );
    expect(
      tokens.where(
        (token) => token.type == InteractiveMessageTokenType.channel,
      ),
      hasLength(1),
    );
  });

  test('does not split URLs into nick or channel tokens', () {
    final tokens = parseInteractiveMessageTokens(
      'Open https://example.com/#alice for alice',
      knownNicks: const ['alice'],
    );

    expect(
      tokens.where((token) => token.type == InteractiveMessageTokenType.url),
      hasLength(1),
    );
    expect(
      tokens.where(
        (token) => token.type == InteractiveMessageTokenType.channel,
      ),
      isEmpty,
    );
    expect(
      tokens.where((token) => token.type == InteractiveMessageTokenType.nick),
      hasLength(1),
    );
  });

  test('resolves hostmask and userhost tokens to the message context nick', () {
    final tokens = parseInteractiveMessageTokens(
      'alice!ident@example.net ident@example.net',
      knownNicks: const ['alice'],
      contextNick: 'alice',
    );

    final hostmask = tokens.firstWhere(
      (token) => token.type == InteractiveMessageTokenType.hostmask,
    );
    expect(hostmask.value, 'alice');

    final userHost = tokens.firstWhere(
      (token) => token.type == InteractiveMessageTokenType.userHost,
    );
    expect(userHost.value, 'alice');
  });
}

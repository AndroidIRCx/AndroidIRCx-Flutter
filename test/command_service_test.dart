import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('normalizes default aliases', () {
    final service = CommandService();

    expect(service.normalizeCommand('/j #flutter'), '/join #flutter');
    expect(service.normalizeCommand('/w nick'), '/whois nick');
    expect(
      service.normalizeCommand('/ns identify secret'),
      '/nickserv identify secret',
    );
    expect(
      service.normalizeCommand('/cs op #flutter nick'),
      '/chanserv op #flutter nick',
    );
    expect(
      service.normalizeCommand('/ms send nick hello'),
      '/memoserv send nick hello',
    );
    expect(service.normalizeCommand('/bs botlist'), '/botserv botlist');
    expect(service.normalizeCommand('hello'), 'hello');
  });

  test('exposes safe parity command registry', () {
    final service = CommandService();
    final names = service.commands.map((command) => command.name).toSet();

    expect(
      names,
      containsAll(<String>{
        'join',
        'part',
        'quit',
        'nick',
        'msg',
        'notice',
        'me',
        'topic',
        'mode',
        'whois',
        'whowas',
        'who',
        'names',
        'list',
        'away',
        'back',
        'cap',
        'monitor',
        'ison',
        'userhost',
        'nickserv',
        'chanserv',
        'hostserv',
        'operserv',
        'memoserv',
        'botserv',
      }),
    );
    expect(service.getCommand('JOIN')?.usage, '/join <channel> [key]');
    expect(service.getCommand('encmsg'), isNull);
  });

  test('renders safe core commands to IRC raw lines', () {
    final service = CommandService();

    expect(
      service.toRawCommand('/join #flutter secret'),
      'JOIN #flutter secret',
    );
    expect(
      service.toRawCommand('/part Gone now', currentTarget: '#flutter'),
      'PART #flutter :Gone now',
    );
    expect(service.toRawCommand('/quit bye'), 'QUIT :bye');
    expect(service.toRawCommand('/nick newNick'), 'NICK newNick');
    expect(
      service.toRawCommand('/msg nick hello there'),
      'PRIVMSG nick :hello there',
    );
    expect(service.toRawCommand('/notice nick hi'), 'NOTICE nick :hi');
    expect(
      service.toRawCommand('/me waves', currentTarget: '#flutter'),
      'PRIVMSG #flutter :\u0001ACTION waves\u0001',
    );
    expect(
      service.toRawCommand('/topic new topic', currentTarget: '#flutter'),
      'TOPIC #flutter :new topic',
    );
    expect(
      service.toRawCommand('/mode +o nick', currentTarget: '#flutter'),
      'MODE #flutter +o nick',
    );
    expect(service.toRawCommand('/whois nick'), 'WHOIS nick');
    expect(service.toRawCommand('/whowas nick 10'), 'WHOWAS nick 10');
    expect(
      service.toRawCommand('/who', currentTarget: '#flutter'),
      'WHO #flutter',
    );
    expect(
      service.toRawCommand('/names', currentTarget: '#flutter'),
      'NAMES #flutter',
    );
    expect(service.toRawCommand('/list'), 'LIST');
    expect(service.toRawCommand('/away lunch'), 'AWAY :lunch');
    expect(service.toRawCommand('/back'), 'AWAY');
    expect(service.toRawCommand('/cap ls 302'), 'CAP ls 302');
    expect(service.toRawCommand('/monitor + nick'), 'MONITOR + nick');
    expect(service.toRawCommand('/ison a b'), 'ISON a b');
    expect(service.toRawCommand('/userhost a b'), 'USERHOST a b');
  });

  test('renders service aliases to service privmsgs', () {
    final service = CommandService();

    expect(
      service.toRawCommand('/nickserv identify secret'),
      'PRIVMSG NickServ :identify secret',
    );
    expect(
      service.toRawCommand('/ns ghost oldNick secret'),
      'PRIVMSG NickServ :ghost oldNick secret',
    );
    expect(
      service.toRawCommand('/chanserv op #flutter nick'),
      'PRIVMSG ChanServ :op #flutter nick',
    );
    expect(service.toRawCommand('/hostserv on'), 'PRIVMSG HostServ :on');
    expect(service.toRawCommand('/operserv stats'), 'PRIVMSG OperServ :stats');
    expect(service.toRawCommand('/memoserv list'), 'PRIVMSG MemoServ :list');
    expect(
      service.toRawCommand('/botserv botlist'),
      'PRIVMSG BotServ :botlist',
    );
  });

  test('does not render unsupported or incomplete commands', () {
    final service = CommandService();

    expect(service.toRawCommand('plain text'), isNull);
    expect(service.toRawCommand('/encmsg nick secret'), isNull);
    expect(service.toRawCommand('/join'), isNull);
    expect(service.toRawCommand('/msg nick'), isNull);
    expect(service.toRawCommand('/part'), isNull);
    expect(service.toRawCommand('/me waves'), isNull);
  });

  test('persists command history', () async {
    final service = CommandService();

    await service.load();
    await service.addToHistory('/join #flutter');
    await service.addToHistory('/whois nick');

    final secondInstance = CommandService();
    await secondInstance.load();

    expect(secondInstance.history, hasLength(2));
    expect(secondInstance.history.first.command, '/whois nick');
  });

  test(
    'exposes command suggestions for slash prefixes without history mutation',
    () async {
      final service = CommandService();

      await service.load();
      await service.addToHistory('/join #flutter');
      final historyBefore = service.history.map((entry) => entry.id).toList();

      final joinSuggestions = service.suggestCommands('/j');
      expect(
        joinSuggestions.map((item) => item.text),
        containsAll(['/j', '/join']),
      );
      expect(
        joinSuggestions.map((item) => item.text).toList(),
        orderedEquals([...joinSuggestions.map((item) => item.text)]..sort()),
      );
      expect(
        joinSuggestions.firstWhere((item) => item.text == '/join').source,
        CommandSuggestionSource.command,
      );
      expect(
        joinSuggestions.firstWhere((item) => item.text == '/j').source,
        CommandSuggestionSource.alias,
      );
      expect(service.history.map((entry) => entry.id).toList(), historyBefore);
    },
  );

  test('includes service aliases in command suggestions', () {
    final service = CommandService();

    final suggestions = service.suggestCommands('/n');

    expect(
      suggestions.map((item) => item.text),
      containsAll(['/nick', '/nickserv', '/ns']),
    );
    expect(
      suggestions.firstWhere((item) => item.text == '/ns').source,
      CommandSuggestionSource.alias,
    );
    expect(
      suggestions.firstWhere((item) => item.text == '/nickserv').source,
      CommandSuggestionSource.command,
    );
  });

  test(
    'returns empty command suggestions for non slash or unknown prefixes',
    () {
      final service = CommandService();

      expect(service.suggestCommands('join'), isEmpty);
      expect(service.suggestCommands('/'), isEmpty);
      expect(service.suggestCommands('/zzz'), isEmpty);
      expect(service.suggestCommands('/enc'), isEmpty);
    },
  );

  test(
    'returns de-duplicated history suggestions without mutating history',
    () async {
      final service = CommandService();

      await service.load();
      await service.addToHistory('/join #flutter');
      await service.addToHistory('/whois nick');
      await service.addToHistory('/join #flutter');
      final commandsBefore = service.history
          .map((entry) => entry.command)
          .toList();

      final suggestions = service.suggestHistory('/j');

      expect(suggestions.map((item) => item.text), ['/join #flutter']);
      expect(suggestions.single.source, CommandSuggestionSource.history);
      expect(
        service.history.map((entry) => entry.command).toList(),
        commandsBefore,
      );
    },
  );
}

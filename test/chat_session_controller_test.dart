import 'dart:async';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/chat_session_controller.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTransport implements IrcTransport {
  final StreamController<String> _controller = StreamController<String>.broadcast();
  final List<String> sentLines = <String>[];

  @override
  Stream<String> get lines => _controller.stream;

  void emit(String line) {
    _controller.add(line);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  Future<void> sendLine(String line) async {
    sentLines.add(line);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('routes SASL/auth numerics into server messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
        saslAccount: 'alice',
        saslPassword: 'secret',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 900 AndroidIRCX alice!ident@example :You are now logged in as alice');
    transport.emit(':server 903 AndroidIRCX :SASL authentication successful');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('logged in as alice'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('SASL authentication successful'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('sends IRC service commands through private messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/ns identify secret');
    await controller.handleComposerSubmit('/cs op #androidircx AndroidIRCX');

    expect(
      transport.sentLines,
      contains('PRIVMSG NickServ :identify secret'),
    );
    expect(
      transport.sentLines,
      contains('PRIVMSG ChanServ :op #androidircx AndroidIRCX'),
    );
    expect(
      controller.tabs.any(
        (tab) => tab.type.name == 'query' && tab.name == 'NickServ',
      ),
      isTrue,
    );
    await controller.handleComposerSubmit('/ms send AndroidIRCX hello');
    await controller.handleComposerSubmit('/bs botlist');

    expect(
      transport.sentLines,
      contains('PRIVMSG MemoServ :send AndroidIRCX hello'),
    );
    expect(
      transport.sentLines,
      contains('PRIVMSG BotServ :botlist'),
    );
    expect(controller.activeTab.name, 'BotServ');
    expect(
      controller.activeMessages.any(
        (message) => message.sender == 'AndroidIRCX' && message.content == 'botlist',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('routes incoming IRC service notices and messages into service tabs', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':NickServ!service@services NOTICE AndroidIRCX :This nickname is registered.');
    transport.emit(':MemoServ!service@services PRIVMSG AndroidIRCX :You have 2 new memos.');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.tabs.any(
        (tab) => tab.type.name == 'query' && tab.name == 'NickServ',
      ),
      isTrue,
    );
    expect(
      controller.tabs.any(
        (tab) => tab.type.name == 'query' && tab.name == 'MemoServ',
      ),
      isTrue,
    );

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'query' && tab.name == 'NickServ').id,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.sender == 'NickServ' && message.content.contains('registered'),
      ),
      isTrue,
    );

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'query' && tab.name == 'MemoServ').id,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.sender == 'MemoServ' && message.content.contains('2 new memos'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('tracks outgoing notice commands in the matching tab', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/notice NickServ STATUS AndroidIRCX');

    expect(
      transport.sentLines,
      contains('NOTICE NickServ :STATUS AndroidIRCX'),
    );
    expect(controller.activeTab.name, 'NickServ');
    expect(
      controller.activeMessages.any(
        (message) =>
            message.isOwn &&
            message.sender == 'AndroidIRCX' &&
            message.content == 'STATUS AndroidIRCX',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('handles CAP commands from the composer', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/cap ls');
    await controller.handleComposerSubmit('/cap req message-tags echo-message');
    await controller.handleComposerSubmit('/cap end');

    expect(transport.sentLines, contains('CAP LS 302'));
    expect(transport.sentLines, contains('CAP REQ :message-tags echo-message'));
    expect(transport.sentLines, contains('CAP END'));
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Requested capabilities: message-tags echo-message'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Ended capability negotiation'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('shows capability status and CAP frame updates in server messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
        saslAccount: 'alice',
        saslPassword: 'secret',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server CAP * LS :multi-prefix sasl message-tags');
    await Future<void>.delayed(Duration.zero);
    transport.emit(':server CAP * ACK :sasl message-tags');
    await Future<void>.delayed(Duration.zero);
    await controller.handleComposerSubmit('/cap status');

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('CAP LS: multi-prefix sasl message-tags'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('CAP ACK: sasl message-tags'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Available capabilities:'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Enabled capabilities:'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('handles away and back commands from the composer', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/away Grabbing coffee');
    await controller.handleComposerSubmit('/back');

    expect(transport.sentLines, contains('AWAY :Grabbing coffee'));
    expect(transport.sentLines, contains('AWAY'));
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Away: Grabbing coffee'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.where((message) => message.content == 'Away status cleared.'),
      isNotEmpty,
    );

    controller.dispose();
  });

  test('handles list command and channel list numerics', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/list #android*');
    transport.emit(':server 321 AndroidIRCX Channel :Users Name');
    transport.emit(':server 322 AndroidIRCX #androidircx 42 :AndroidIRCx official channel');
    transport.emit(':server 323 AndroidIRCX :End of /LIST');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('LIST #android*'));
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Requested channel list for: #android*'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Channel list started.'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('#androidircx (42 users) - AndroidIRCx official channel'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('End of /LIST'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('handles server info commands and numerics', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.handleComposerSubmit('/motd');
    await controller.handleComposerSubmit('/time');
    await controller.handleComposerSubmit('/version irc.example.test');
    await controller.handleComposerSubmit('/links *.example.test');

    transport.emit(':server 371 AndroidIRCX :- Welcome to the network');
    transport.emit(':server 374 AndroidIRCX :End of /INFO list');
    transport.emit(':server 391 AndroidIRCX irc.example.test :2026-03-16 20:15:00');
    transport.emit(':server 351 AndroidIRCX ircd-seven-1.1 example.test :server version info');
    transport.emit(':server 364 AndroidIRCX hub.example.test 1 :Example hub');
    transport.emit(':server 365 AndroidIRCX :End of /LINKS list');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('MOTD'));
    expect(transport.sentLines, contains('TIME'));
    expect(transport.sentLines, contains('VERSION irc.example.test'));
    expect(transport.sentLines, contains('LINKS *.example.test'));

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Requested MOTD.'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Welcome to the network'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('2026-03-16 20:15:00'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Server version:'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Link: hub.example.test (1) - Example hub'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('End of /LINKS list'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('handles channel admin commands and ban list numerics', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#androidircx'));
    await controller.handleComposerSubmit('/op Alice');
    await controller.handleComposerSubmit('/deop Alice');
    await controller.handleComposerSubmit('/voice Bob');
    await controller.handleComposerSubmit('/devoice Bob');
    await controller.handleComposerSubmit('/ban bad!*@*');
    await controller.handleComposerSubmit('/unban bad!*@*');
    await controller.handleComposerSubmit('/banlist');

    transport.emit(':server 367 AndroidIRCX #androidircx bad!*@* ChanOp 1710000000');
    transport.emit(':server 368 AndroidIRCX #androidircx :End of channel ban list');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.sentLines, contains('MODE #androidircx +o Alice'));
    expect(transport.sentLines, contains('MODE #androidircx -o Alice'));
    expect(transport.sentLines, contains('MODE #androidircx +v Bob'));
    expect(transport.sentLines, contains('MODE #androidircx -v Bob'));
    expect(transport.sentLines, contains('MODE #androidircx +b bad!*@*'));
    expect(transport.sentLines, contains('MODE #androidircx -b bad!*@*'));
    expect(transport.sentLines, contains('MODE #androidircx +b'));

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Requested ban list for #androidircx'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Ban: bad!*@* set by ChanOp'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('End of channel ban list'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('routes away numerics into server messages', () async {
    final transport = _FakeTransport();
    final service = IrcService(
      transportConnector: (_) async => transport,
    );
    final controller = ChatSessionController(
      network: const NetworkConfig(
        id: 'dbase',
        name: 'DBase',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'AndroidIRCX',
        altNickname: 'AndroidIRCX_',
      ),
      ircService: service,
    );

    await controller.start();
    transport.emit(':server 306 AndroidIRCX :You have been marked as being away');
    transport.emit(':server 305 AndroidIRCX :You are no longer marked as being away');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('marked as being away'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('no longer marked as being away'),
      ),
      isTrue,
    );

    controller.dispose();
  });
}

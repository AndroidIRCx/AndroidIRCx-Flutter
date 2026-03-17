import 'dart:async';

import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
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

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
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

  test('routes incoming notices to a dedicated notice tab when configured', () async {
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
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(noticeRouting: NoticeRoutingMode.notice),
      ),
    );

    await controller.start();
    transport.emit(':services.example NOTICE AndroidIRCX :Maintenance tonight');
    await Future<void>.delayed(Duration.zero);

    final noticeTab = controller.tabs.firstWhere((tab) => tab.type.name == 'notice');
    controller.selectTab(noticeTab.id);
    expect(
      controller.activeMessages.any((message) => message.content == 'Maintenance tonight'),
      isTrue,
    );

    controller.dispose();
  });

  test('routes incoming notices to the active tab when configured', () async {
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
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(noticeRouting: NoticeRoutingMode.active),
      ),
    );

    await controller.start();
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':services.example NOTICE AndroidIRCX :Maintenance tonight');
    await Future<void>.delayed(Duration.zero);

    expect(controller.activeTab.name, '#room');
    expect(
      controller.activeMessages.any((message) => message.content == 'Maintenance tonight'),
      isTrue,
    );

    controller.dispose();
  });

  test('routes incoming notices to a private query when configured', () async {
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
      settingsRepository: _FakeSettingsRepository(
        const AppSettings(noticeRouting: NoticeRoutingMode.private),
      ),
    );

    await controller.start();
    transport.emit(':NickServ!service@example NOTICE AndroidIRCX :Identify now');
    await Future<void>.delayed(Duration.zero);

    final queryTab = controller.tabs.firstWhere((tab) => tab.type.name == 'query');
    controller.selectTab(queryTab.id);
    expect(queryTab.name, 'NickServ');
    expect(
      controller.activeMessages.any((message) => message.content == 'Identify now'),
      isTrue,
    );

    controller.dispose();
  });

  test('uses server-time tag as message timestamp and stores tags', () async {
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
    transport.emit(
      '@time=2026-03-17T10:11:12.000Z;+draft/source=test :alice!user@example PRIVMSG #room :hello',
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'channel' && tab.name == '#room').id,
    );
    final message = controller.activeMessages.last;
    expect(message.timestamp.toUtc(), DateTime.parse('2026-03-17T10:11:12.000Z'));
    expect(message.tags['+draft/source'], 'test');

    controller.dispose();
  });

  test('routes self echo direct messages into the target query tab', () async {
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
    transport.emit(':server 001 AndroidIRCX :Welcome');
    transport.emit(':server CAP * ACK :echo-message message-tags server-time');
    transport.emit(':AndroidIRCX!me@example PRIVMSG alice :hello from echo');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'query' && tab.name == 'alice').id,
    );
    expect(
      controller.activeMessages.any(
        (message) =>
            message.isOwn &&
            message.sender == 'AndroidIRCX' &&
            message.content == 'hello from echo',
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('filters and exports current tab history', () async {
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
    transport.emit(':alice!user@example PRIVMSG #room :hello flutter');
    transport.emit(':bob!user@example NOTICE #room :system notice');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'channel' && tab.name == '#room').id,
    );
    final chatOnly = controller.messagesForTab(
      controller.activeTabId,
      query: 'flutter',
      kinds: const <IrcMessageKind>{IrcMessageKind.chat},
    );
    final export = controller.exportTabHistory(controller.activeTabId, query: 'flutter');

    expect(chatOnly, hasLength(1));
    expect(chatOnly.single.content, 'hello flutter');
    expect(export, contains('hello flutter'));
    expect(export, isNot(contains('system notice')));

    controller.dispose();
  });

  test('renders draft intent action as an action message', () async {
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
    transport.emit('@draft/intent=ACTION :alice!user@example PRIVMSG #room :waves');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'channel' && tab.name == '#room').id,
    );
    expect(
      controller.activeMessages.any((message) => message.content == '• waves'),
      isTrue,
    );

    controller.dispose();
  });

  test('deduplicates messages with the same msgid', () async {
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
    transport.emit('@msgid=abc123 :alice!user@example PRIVMSG #room :hello once');
    transport.emit('@msgid=abc123 :alice!user@example PRIVMSG #room :hello once');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'channel' && tab.name == '#room').id,
    );
    expect(controller.activeMessages.where((message) => message.content == 'hello once'), hasLength(1));

    controller.dispose();
  });

  test('tracks batch start and end with message count', () async {
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
    transport.emit(':server BATCH +batch-1 chathistory #room');
    transport.emit('@batch=batch-1;msgid=1 :alice!user@example PRIVMSG #room :first history');
    transport.emit(':server BATCH -batch-1');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(controller.tabs.firstWhere((tab) => tab.type.name == 'server').id);
    expect(
      controller.activeMessages.any((message) => message.content.contains('BATCH start: chathistory #room')),
      isTrue,
    );
    expect(
      controller.activeMessages.any((message) => message.content.contains('Playback batch completed: 1 messages')),
      isTrue,
    );

    controller.dispose();
  });

  test('shows playback batch summary and labeled response match in server tab', () async {
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
    transport.emit(':server CAP * ACK :labeled-response');
    await Future<void>.delayed(Duration.zero);
    final label = await service.sendRawLabeled('WHOIS alice alice');
    transport.emit(':server BATCH +batch-2 znc.in/playback #room');
    transport.emit('@batch=batch-2;msgid=2 :alice!user@example PRIVMSG #room :older line');
    transport.emit(':server BATCH -batch-2');
    transport.emit('@label=$label :server 318 AndroidIRCX alice :End of /WHOIS list.');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(controller.tabs.firstWhere((tab) => tab.type.name == 'server').id);
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Playback batch completed: 1 messages'),
      ),
      isTrue,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Labeled response matched: WHOIS alice alice'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('requests chathistory for the active channel when supported', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);

    await controller.handleComposerSubmit('/chathistory 25');

    expect(
      transport.sentLines.any((line) => line.contains('CHATHISTORY LATEST #room * 25')),
      isTrue,
    );
    controller.selectTab(controller.tabs.firstWhere((tab) => tab.type.name == 'server').id);
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains(
          'Requested CHATHISTORY LATEST for #room (*, 25 messages).',
        ),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('uses latest known msgid for /chathistory before when omitted', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit('@msgid=abc123 :alice!user@example PRIVMSG #room :hello');
    transport.emit(':server CAP * ACK :chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await controller.handleComposerSubmit('/chathistory before 20');

    expect(
      transport.sentLines.any((line) => line.contains('CHATHISTORY BEFORE #room abc123 20')),
      isTrue,
    );

    controller.dispose();
  });

  test('marks playback messages from chathistory batch', () async {
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
    transport.emit(':server BATCH +hist chathistory #room');
    transport.emit('@batch=hist;msgid=1 :alice!user@example PRIVMSG #room :older line');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'channel' && tab.name == '#room').id,
    );
    expect(controller.activeMessages.single.isPlayback, isTrue);

    controller.dispose();
  });

  test('requests recent history for the active tab through controller API', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);

    expect(await controller.requestRecentHistory(limit: 25), isTrue);
    expect(
      transport.sentLines.any((line) => line.contains('CHATHISTORY LATEST #room * 25')),
      isTrue,
    );

    controller.selectTab(controller.tabs.firstWhere((tab) => tab.type.name == 'server').id);
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('Requested recent history for #room (25 messages).'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('requests older history using the oldest known msgid anchor', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit('@msgid=first-1 :alice!user@example PRIVMSG #room :older');
    transport.emit('@msgid=last-1 :bob!user@example PRIVMSG #room :newer');
    transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.requestOlderHistory(limit: 40), isTrue);
    expect(
      transport.sentLines.any((line) => line.contains('CHATHISTORY BEFORE #room first-1 40')),
      isTrue,
    );

    controller.dispose();
  });

  test('reports missing history anchor when requesting older history too early', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);

    expect(await controller.requestOlderHistory(limit: 50), isFalse);
    controller.selectTab(controller.tabs.firstWhere((tab) => tab.type.name == 'server').id);
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('No history anchor is available yet for #room.'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('requests newer history using the latest known msgid anchor', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit('@msgid=first-1 :alice!user@example PRIVMSG #room :older');
    transport.emit('@msgid=last-1 :bob!user@example PRIVMSG #room :newer');
    transport.emit(':server CAP * ACK :draft/chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.requestNewerHistory(limit: 40), isTrue);
    expect(
      transport.sentLines.any((line) => line.contains('CHATHISTORY AFTER #room last-1 40')),
      isTrue,
    );

    controller.dispose();
  });

  test('requests surrounding history around the latest known msgid anchor', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit('@msgid=mid-1 :alice!user@example PRIVMSG #room :hello');
    transport.emit(':server CAP * ACK :chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(await controller.requestAroundLatestHistory(limit: 30), isTrue);
    expect(
      transport.sentLines.any((line) => line.contains('CHATHISTORY AROUND #room mid-1 30')),
      isTrue,
    );

    controller.dispose();
  });

  test('reports missing recent anchor when requesting newer history too early', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    transport.emit(':server CAP * ACK :chathistory labeled-response');
    await Future<void>.delayed(Duration.zero);

    expect(await controller.requestNewerHistory(limit: 50), isFalse);
    controller.selectTab(controller.tabs.firstWhere((tab) => tab.type.name == 'server').id);
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('No recent history anchor is available yet for #room.'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('shows unsupported chathistory error when capability is missing', () async {
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
    await controller.joinChannel(const JoinChannelRequest(channel: '#room'));
    await controller.handleComposerSubmit('/chathistory');

    controller.selectTab(controller.tabs.firstWhere((tab) => tab.type.name == 'server').id);
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('CHATHISTORY is not supported by this server.'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('routes CTCP requests and sends CTCP replies', () async {
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
    transport.emit(':alice!user@example PRIVMSG AndroidIRCX :\u0001VERSION\u0001');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      transport.sentLines,
      contains('NOTICE alice :\u0001VERSION AndroidIRCx Flutter 1.0.0\u0001'),
    );
    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'query' && tab.name == 'alice').id,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('CTCP VERSION request from alice'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('routes CTCP replies into the matching query tab', () async {
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
    transport.emit(':alice!user@example NOTICE AndroidIRCX :\u0001PING 12345\u0001');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    controller.selectTab(
      controller.tabs.firstWhere((tab) => tab.type.name == 'query' && tab.name == 'alice').id,
    );
    expect(
      controller.activeMessages.any(
        (message) => message.content.contains('CTCP PING reply from alice: 12345'),
      ),
      isTrue,
    );

    controller.dispose();
  });

  test('sends CTCP commands from the composer', () async {
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
    await controller.handleComposerSubmit('/ctcp alice ping 999');

    expect(
      transport.sentLines,
      contains('PRIVMSG alice :\u0001PING 999\u0001'),
    );
    expect(controller.activeTab.name, 'alice');
    expect(
      controller.activeMessages.any(
        (message) => message.content == 'Sent CTCP PING: 999',
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

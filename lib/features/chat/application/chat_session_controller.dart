import 'dart:async';

import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:androidircx/features/chat/data/chat_session_persistence.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:flutter/foundation.dart';

class ChatSessionController extends ChangeNotifier {
  ChatSessionController({
    required this.network,
    IrcService? ircService,
    ChatSessionPersistence? persistence,
    SettingsRepository? settingsRepository,
    CommandService? commandService,
  })  : _ircService = ircService ?? IrcService(),
        _persistence = persistence ?? ChatSessionPersistence(),
        _settingsRepository =
            settingsRepository ?? SharedPrefsSettingsRepository(),
        _commandService = commandService ?? CommandService() {
    final serverTab = ChatTab(
      id: _serverTabId(network.id),
      name: network.name,
      type: ChatTabType.server,
      networkId: network.id,
    );
    _tabs = [serverTab];
    _activeTabId = serverTab.id;
    _messages[serverTab.id] = [];
  }

  final NetworkConfig network;
  final IrcService _ircService;
  final ChatSessionPersistence _persistence;
  final SettingsRepository _settingsRepository;
  final CommandService _commandService;
  final Map<String, List<IrcMessage>> _messages = {};
  final Map<String, Set<String>> _channelUsers = {};
  final Map<String, String> _channelTopics = {};
  final Map<String, String> _channelModes = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _reconnectTimer;

  late List<ChatTab> _tabs;
  late String _activeTabId;
  AppSettings _settings = const AppSettings();
  bool _isBootstrapped = false;
  bool _manualDisconnectRequested = false;
  int _reconnectAttempt = 0;
  Duration? _pendingReconnectDelay;
  ConnectionSnapshot _connection = const ConnectionSnapshot(
    networkId: '',
    phase: ConnectionPhase.idle,
  );

  List<ChatTab> get tabs => List<ChatTab>.unmodifiable(_tabs);
  String get activeTabId => _activeTabId;
  ConnectionSnapshot get connection => _connection;
  AppSettings get settings => _settings;
  List<CommandHistoryEntry> get commandHistory => _commandService.history;
  bool get isReconnectScheduled => _reconnectTimer?.isActive ?? false;
  Duration? get pendingReconnectDelay => _pendingReconnectDelay;
  ChatTab get activeTab => _tabs.firstWhere((tab) => tab.id == _activeTabId);
  String get currentNick => _ircService.currentNick ?? network.nickname;
  String? get activeChannelTopic => _channelTopics[activeTabId];
  String? get activeChannelModes => _channelModes[activeTabId];
  String get activeChannelSummary {
    if (activeTab.type != ChatTabType.channel) {
      return '';
    }

    final users = activeChannelUsers.length;
    final modes = (activeChannelModes ?? '').trim();
    if (modes.isEmpty) {
      return '$users users';
    }

    return '$users users • $modes';
  }
  List<String> get activeChannelUsers {
    final users = _channelUsers[activeTab.id];
    if (users == null) {
      return const [];
    }

    final sorted = users.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List<String>.unmodifiable(sorted);
  }
  List<IrcMessage> get activeMessages {
    final source = _messages[_activeTabId] ?? const <IrcMessage>[];
    if (_settings.showRawEvents) {
      return List<IrcMessage>.unmodifiable(source);
    }

    return List<IrcMessage>.unmodifiable(
      source.where((message) => message.kind != IrcMessageKind.raw),
    );
  }

  Future<void> start() async {
    if (!_isBootstrapped) {
      await _commandService.load();
      await _loadPersistedState();
      _isBootstrapped = true;
      notifyListeners();
    }

    if (_subscriptions.isEmpty) {
      _subscriptions.add(_ircService.frames.listen(_handleFrame));
      _subscriptions.add(_ircService.stateStream.listen((snapshot) {
        _connection = snapshot;
        _handleConnectionLifecycle(snapshot);
        notifyListeners();
      }));
      _subscriptions.add(_ircService.rawEvents.listen((line) {
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: line,
          kind: IrcMessageKind.raw,
        );
        unawaited(_persistState());
        notifyListeners();
      }));
    }

    _manualDisconnectRequested = false;
    _cancelReconnect();
    await _ircService.connect(network);
  }

  void selectTab(String tabId) {
    _activeTabId = tabId;
    _setTabActivity(tabId, false);
    unawaited(_persistState());
    notifyListeners();
  }

  void closeTab(String tabId) {
    final tab = _findTab(tabId);
    if (tab == null || tab.type == ChatTabType.server) {
      return;
    }

    _tabs = _tabs.where((item) => item.id != tabId).toList(growable: false);
    _messages.remove(tabId);
    _channelUsers.remove(tabId);
    _channelTopics.remove(tabId);

    if (_activeTabId == tabId) {
      _activeTabId = _serverTabId(network.id);
      _setTabActivity(_activeTabId, false);
    }

    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> handleComposerSubmit(String input) async {
    final text = _commandService.normalizeCommand(input.trim());
    if (text.isEmpty) {
      return;
    }

    if (text.startsWith('/')) {
      await _commandService.addToHistory(text);
      await _handleSlashCommand(text.substring(1));
      notifyListeners();
      return;
    }

    if (activeTab.type == ChatTabType.server) {
      await _ircService.sendRaw(text);
      return;
    }

    await _ircService.sendPrivmsg(target: activeTab.name, text: text);
    _appendMessage(
      tabId: activeTab.id,
      sender: _ircService.currentNick ?? network.nickname,
      content: text,
      isOwn: true,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> joinChannel(JoinChannelRequest request) async {
    final name = request.channel.trim();
    if (name.isEmpty) {
      return;
    }

    final normalized = name.startsWith('#') ? name : '#$name';
    final tab = _ensureChannelTab(normalized);
    _activeTabId = tab.id;
    unawaited(_persistState());
    notifyListeners();
    await _ircService.joinChannel(normalized);
  }

  Future<void> disconnect() async {
    _manualDisconnectRequested = true;
    _cancelReconnect();
    await _ircService.disconnect();
  }

  Future<void> reconnectNow() async {
    _cancelReconnect();
    await start();
  }

  Future<void> reloadSettings() async {
    _settings = await _settingsRepository.loadSettings();
    notifyListeners();
  }

  void _handleConnectionLifecycle(ConnectionSnapshot snapshot) {
    if (snapshot.phase == ConnectionPhase.connected) {
      _reconnectAttempt = 0;
      _pendingReconnectDelay = null;
      _manualDisconnectRequested = false;
      _cancelReconnect();
      return;
    }

    if (_manualDisconnectRequested) {
      return;
    }

    if (snapshot.phase == ConnectionPhase.error ||
        snapshot.phase == ConnectionPhase.disconnected) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) {
      return;
    }

    _reconnectAttempt += 1;
    final seconds = (_reconnectAttempt * 2).clamp(2, 12);
    _pendingReconnectDelay = Duration(seconds: seconds);
    _reconnectTimer = Timer(_pendingReconnectDelay!, () {
      _reconnectTimer = null;
      _pendingReconnectDelay = null;
      unawaited(start());
      notifyListeners();
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pendingReconnectDelay = null;
  }

  Future<void> _handleSlashCommand(String commandLine) async {
    final parts = commandLine.split(' ');
    final command = parts.first.toLowerCase();
    final rest = parts.skip(1).join(' ').trim();

    switch (command) {
      case 'join':
        if (rest.isNotEmpty) {
          await joinChannel(JoinChannelRequest(channel: rest));
          return;
        }
      case 'part':
        if (activeTab.type == ChatTabType.channel) {
          final suffix = rest.isEmpty ? '' : ' :$rest';
          await _ircService.sendRaw('PART ${activeTab.name}$suffix');
          return;
        }
      case 'query':
        if (rest.isNotEmpty) {
          final tab = _ensureQueryTab(rest.split(' ').first);
          _activeTabId = tab.id;
          unawaited(_persistState());
          return;
        }
      case 'msg':
        final space = rest.indexOf(' ');
        if (space != -1) {
          final target = rest.substring(0, space);
          final text = rest.substring(space + 1).trim();
          if (text.isNotEmpty) {
            final tab = _ensureQueryTab(target);
            await _ircService.sendPrivmsg(target: target, text: text);
            _appendMessage(
              tabId: tab.id,
              sender: _ircService.currentNick ?? network.nickname,
              content: text,
              isOwn: true,
            );
            unawaited(_persistState());
            notifyListeners();
            return;
          }
        }
      case 'notice':
        final space = rest.indexOf(' ');
        if (space != -1) {
          final target = rest.substring(0, space);
          final text = rest.substring(space + 1).trim();
          if (text.isNotEmpty) {
            await _ircService.sendNotice(target: target, text: text);
            return;
          }
        }
      case 'me':
        if (rest.isNotEmpty && activeTab.type != ChatTabType.server) {
          await _ircService.sendAction(target: activeTab.name, text: rest);
          _appendMessage(
            tabId: activeTab.id,
            sender: _ircService.currentNick ?? network.nickname,
            content: '• $rest',
            isOwn: true,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
      case 'nick':
        if (rest.isNotEmpty) {
          await _ircService.sendRaw('NICK $rest');
          return;
        }
      case 'whois':
        if (rest.isNotEmpty) {
          await _ircService.sendWhois(rest.split(' ').first);
          return;
        }
      case 'who':
        await _ircService.sendWho(rest.isEmpty && activeTab.type == ChatTabType.channel ? activeTab.name : rest);
        return;
      case 'whowas':
        if (rest.isNotEmpty) {
          await _ircService.sendWhowas(rest.split(' ').first);
          return;
        }
      case 'names':
        if (activeTab.type == ChatTabType.channel) {
          await _ircService.sendNames(activeTab.name);
          return;
        }
        if (rest.isNotEmpty) {
          await _ircService.sendNames(rest.split(' ').first);
          return;
        }
      case 'invite':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          await _ircService.sendInvite(
            nick: rest.split(' ').first,
            channel: activeTab.name,
          );
          return;
        }
      case 'kick':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          final parts = rest.split(' ');
          final nick = parts.first;
          final reason = parts.length > 1 ? parts.skip(1).join(' ') : null;
          await _ircService.sendKick(
            channel: activeTab.name,
            nick: nick,
            reason: reason,
          );
          return;
        }
      case 'topic':
        if (activeTab.type == ChatTabType.channel) {
          await _ircService.sendTopic(channel: activeTab.name, topic: rest.isEmpty ? null : rest);
          return;
        }
      case 'mode':
        if (rest.isNotEmpty) {
          final args = activeTab.type == ChatTabType.channel ? '${activeTab.name} $rest' : rest;
          await _ircService.sendMode(args);
          return;
        }
      case 'quote':
      case 'raw':
        if (rest.isNotEmpty) {
          await _ircService.sendRaw(rest);
          return;
        }
      case 'clear':
        _messages[activeTab.id] = [];
        if (activeTab.type == ChatTabType.channel) {
          _channelUsers.putIfAbsent(activeTab.id, () => <String>{});
        }
        unawaited(_persistState());
        return;
      case 'quit':
        await _ircService.disconnect(rest.isEmpty ? null : rest);
        return;
      default:
        await _ircService.sendRaw(commandLine);
        return;
    }
  }

  void _handleFrame(IrcMessageFrame frame) {
    switch (frame.command) {
      case '001':
      case '002':
      case '003':
      case '004':
      case '372':
      case '375':
      case '376':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing ?? frame.params.join(' '),
          kind: IrcMessageKind.system,
        );
      case '332':
        if (frame.params.length >= 2 && frame.trailing != null) {
          final channel = frame.params[1];
          final tab = _ensureChannelTab(channel);
          _channelTopics[tab.id] = frame.trailing!;
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'Topic: ${frame.trailing!}',
            kind: IrcMessageKind.system,
          );
        }
      case '331':
        if (frame.params.length >= 2) {
          final channel = frame.params[1];
          final tab = _ensureChannelTab(channel);
          _channelTopics.remove(tab.id);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: frame.trailing ?? 'No topic is set.',
            kind: IrcMessageKind.system,
          );
        }
      case '333':
        if (frame.params.length >= 3) {
          final channel = frame.params[1];
          final author = frame.params[2];
          final tab = _ensureChannelTab(channel);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'Topic set by $author',
            kind: IrcMessageKind.system,
          );
        }
      case '324':
        if (frame.params.length >= 3) {
          final channel = frame.params[1];
          final modes = frame.params.skip(2).join(' ');
          final tab = _ensureChannelTab(channel);
          _channelModes[tab.id] = modes;
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'Channel modes: $modes',
            kind: IrcMessageKind.system,
          );
        }
      case '311':
        _appendWhoisMessage(
          frame,
          'WHOIS: ${frame.params.length > 3 ? '${frame.params[1]} is ${frame.params[2]}@${frame.params[3]}' : frame.raw}',
        );
      case '900':
      case '901':
      case '902':
      case '903':
      case '904':
      case '905':
      case '906':
      case '907':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: 'auth',
          content: frame.trailing ?? frame.raw,
          kind: IrcMessageKind.system,
        );
      case '312':
        _appendWhoisMessage(
          frame,
          'WHOIS server: ${frame.params.length > 2 ? '${frame.params[1]} on ${frame.params[2]} ${frame.trailing ?? ''}'.trim() : frame.raw}',
        );
      case '317':
        _appendWhoisMessage(
          frame,
          'WHOIS idle: ${frame.params.length > 2 ? '${frame.params[1]} idle ${frame.params[2]}s' : frame.raw}',
        );
      case '319':
        _appendWhoisMessage(
          frame,
          'WHOIS channels: ${frame.params.length > 1 ? '${frame.params[1]} ${frame.trailing ?? ''}'.trim() : frame.raw}',
        );
      case '318':
        _appendWhoisMessage(
          frame,
          'End of WHOIS for ${frame.params.length > 1 ? frame.params[1] : ''}'.trim(),
        );
      case '314':
        _appendWhoisMessage(
          frame,
          'WHOWAS: ${frame.params.length > 3 ? '${frame.params[1]} was ${frame.params[2]}@${frame.params[3]}' : frame.raw}',
        );
      case '352':
        if (frame.params.length >= 6) {
          final channel = frame.params[1];
          final nick = frame.params[5];
          final tab = _ensureChannelTab(channel);
          _channelUsers.putIfAbsent(tab.id, () => <String>{}).add(nick);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'WHO: $nick ${frame.params[2]}@${frame.params[3]}',
            kind: IrcMessageKind.system,
          );
        }
      case '315':
        if (frame.params.length >= 2) {
          final target = frame.params[1];
          final tabId = target.startsWith('#')
              ? _ensureChannelTab(target).id
              : _serverTabId(network.id);
          _appendMessage(
            tabId: tabId,
            sender: '*',
            content: frame.trailing ?? 'End of WHO.',
            kind: IrcMessageKind.system,
          );
        }
      case '369':
        _appendWhoisMessage(
          frame,
          'End of WHOWAS for ${frame.params.length > 1 ? frame.params[1] : ''}'.trim(),
        );
      case '353':
        if (frame.params.length >= 3 && frame.trailing != null) {
          final channel = frame.params[2];
          final tab = _ensureChannelTab(channel);
          final users = frame.trailing!
              .split(RegExp(r'\s+'))
              .where((item) => item.isNotEmpty)
              .map(_normalizeNickPrefix);
          _channelUsers.putIfAbsent(tab.id, () => <String>{}).addAll(users);
        }
      case '366':
        if (frame.params.length >= 2) {
          final channel = frame.params[1];
          final tab = _ensureChannelTab(channel);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: frame.trailing ?? 'Nick list complete.',
            kind: IrcMessageKind.system,
          );
        }
      case 'JOIN':
        final channel = frame.trailing ?? _firstOrNull(frame.params);
        if (channel != null) {
          final tab = _ensureChannelTab(channel);
          final nick = frame.senderNick ?? '*';
          _channelUsers.putIfAbsent(tab.id, () => <String>{}).add(nick);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: '$nick joined $channel',
            kind: IrcMessageKind.system,
          );
          if (nick == (_ircService.currentNick ?? network.nickname)) {
            _activeTabId = tab.id;
          }
        }
      case 'PART':
        final channel = _firstOrNull(frame.params);
        if (channel != null) {
          final tab = _ensureChannelTab(channel);
          _channelUsers.putIfAbsent(tab.id, () => <String>{}).remove(frame.senderNick ?? '');
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content:
                '${frame.senderNick ?? '*'} left $channel${frame.trailing == null ? '' : ' (${frame.trailing})'}',
            kind: IrcMessageKind.system,
          );
        }
      case 'QUIT':
        _removeUserFromAllChannels(frame.senderNick);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content:
              '${frame.senderNick ?? '*'} quit${frame.trailing == null ? '' : ' (${frame.trailing})'}',
          kind: IrcMessageKind.system,
        );
      case 'NICK':
        _renameUserAcrossChannels(
          frame.senderNick,
          frame.trailing ?? _firstOrNull(frame.params),
        );
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content:
              '${frame.senderNick ?? '*'} is now known as ${frame.trailing ?? _firstOrNull(frame.params) ?? '?'}',
          kind: IrcMessageKind.system,
        );
      case 'NOTICE':
        _handleNotice(frame);
      case 'TOPIC':
        _handleTopic(frame);
      case 'MODE':
        _handleMode(frame);
      case 'PRIVMSG':
        _handlePrivmsg(frame);
      case '401':
      case '403':
      case '442':
      case '421':
      case '433':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: 'error',
          content: frame.trailing ?? frame.raw,
          kind: IrcMessageKind.system,
        );
      case 'ERROR':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: 'error',
          content: frame.trailing ?? frame.raw,
          kind: IrcMessageKind.system,
        );
      default:
        break;
    }

    unawaited(_persistState());
    notifyListeners();
  }

  void _handleNotice(IrcMessageFrame frame) {
    final target = _firstOrNull(frame.params);
    final content = frame.trailing;
    if (target == null || content == null) {
      return;
    }

    final tabId = target.startsWith('#')
        ? _ensureChannelTab(target).id
        : _serverTabId(network.id);

    _appendMessage(
      tabId: tabId,
      sender: frame.senderNick ?? 'notice',
      content: content,
    );
    _markActivityIfInactive(tabId);
  }

  void _handlePrivmsg(IrcMessageFrame frame) {
    final target = _firstOrNull(frame.params);
    final content = frame.trailing;
    if (target == null || content == null) {
      return;
    }

    final isChannel = target.startsWith('#');
    final tab = isChannel
        ? _ensureChannelTab(target)
        : _ensureQueryTab(frame.senderNick ?? target);

    _appendMessage(
      tabId: tab.id,
      sender: frame.senderNick ?? target,
      content: _normalizeContent(content),
    );
    _markActivityIfInactive(tab.id);
  }

  void _handleTopic(IrcMessageFrame frame) {
    final channel = _firstOrNull(frame.params);
    final topic = frame.trailing;
    if (channel == null || topic == null) {
      return;
    }

    final tab = _ensureChannelTab(channel);
    _channelTopics[tab.id] = topic;
    _appendMessage(
      tabId: tab.id,
      sender: '*',
      content: '${frame.senderNick ?? '*'} changed the topic to: $topic',
      kind: IrcMessageKind.system,
    );
    _markActivityIfInactive(tab.id);
  }

  void _handleMode(IrcMessageFrame frame) {
    if (frame.params.length < 2) {
      return;
    }

    final target = frame.params.first;
    final modeText = [...frame.params.skip(1), if (frame.trailing != null) frame.trailing!].join(' ');
    final tabId = target.startsWith('#')
        ? _ensureChannelTab(target).id
        : _serverTabId(network.id);
    _appendMessage(
      tabId: tabId,
      sender: '*',
      content: '${frame.senderNick ?? '*'} set mode $modeText on $target',
      kind: IrcMessageKind.system,
    );
    _markActivityIfInactive(tabId);
  }

  String _normalizeContent(String content) {
    const actionPrefix = '\u0001ACTION ';
    if (content.startsWith(actionPrefix) && content.endsWith('\u0001')) {
      return '• ${content.substring(actionPrefix.length, content.length - 1)}';
    }

    return content;
  }

  ChatTab _ensureChannelTab(String channel) {
    final existing = _findTab(_channelTabId(network.id, channel));
    if (existing != null) {
      return existing;
    }

    final tab = ChatTab(
      id: _channelTabId(network.id, channel),
      name: channel,
      type: ChatTabType.channel,
      networkId: network.id,
    );
    _tabs = [..._tabs, tab];
    _messages.putIfAbsent(tab.id, () => []);
    _channelUsers.putIfAbsent(tab.id, () => <String>{});
    _channelTopics.putIfAbsent(tab.id, () => '');
    return tab;
  }

  ChatTab _ensureQueryTab(String nick) {
    final existing = _findTab(_queryTabId(network.id, nick));
    if (existing != null) {
      return existing;
    }

    final tab = ChatTab(
      id: _queryTabId(network.id, nick),
      name: nick,
      type: ChatTabType.query,
      networkId: network.id,
    );
    _tabs = [..._tabs, tab];
    _messages.putIfAbsent(tab.id, () => []);
    return tab;
  }

  ChatTab? _findTab(String id) {
    for (final tab in _tabs) {
      if (tab.id == id) {
        return tab;
      }
    }

    return null;
  }

  void _appendMessage({
    required String tabId,
    required String sender,
    required String content,
    bool isOwn = false,
    IrcMessageKind kind = IrcMessageKind.chat,
  }) {
    final list = _messages.putIfAbsent(tabId, () => []);
    list.add(
      IrcMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}-${list.length}',
        tabId: tabId,
        sender: sender,
        content: content,
        timestamp: DateTime.now(),
        isOwn: isOwn,
        kind: kind,
      ),
    );
  }

  Future<void> _loadPersistedState() async {
    _settings = await _settingsRepository.loadSettings();
    final snapshot = await _persistence.load(network.id);
    if (snapshot == null) {
      return;
    }

    if (snapshot.tabs.isNotEmpty) {
      _tabs = snapshot.tabs;
    }

    _messages
      ..clear()
      ..addAll(snapshot.messagesByTab);

    for (final tab in _tabs) {
      _messages.putIfAbsent(tab.id, () => []);
        if (tab.type == ChatTabType.channel) {
          _channelUsers.putIfAbsent(tab.id, () => <String>{});
          _channelTopics.putIfAbsent(tab.id, () => '');
          _channelModes.putIfAbsent(tab.id, () => '');
        }
      }

    if (snapshot.activeTabId.isNotEmpty && _findTab(snapshot.activeTabId) != null) {
      _activeTabId = snapshot.activeTabId;
    }
  }

  Future<void> _persistState() {
    return _persistence.save(
      networkId: network.id,
      tabs: _tabs,
      messagesByTab: _messages,
      activeTabId: _activeTabId,
    );
  }

  String? _firstOrNull(List<String> values) {
    if (values.isEmpty) {
      return null;
    }

    return values.first;
  }

  void _appendWhoisMessage(IrcMessageFrame frame, String content) {
    final nick = frame.params.length > 1 ? frame.params[1] : null;
    final targetTabId = nick == null ? _serverTabId(network.id) : _ensureQueryTab(nick).id;
    _appendMessage(
      tabId: targetTabId,
      sender: '*',
      content: content,
      kind: IrcMessageKind.system,
    );
    _markActivityIfInactive(targetTabId);
  }

  String _normalizeNickPrefix(String value) {
    return value.replaceFirst(RegExp(r'^[~&@%+]'), '');
  }

  void _removeUserFromAllChannels(String? nick) {
    if (nick == null || nick.isEmpty) {
      return;
    }

    for (final users in _channelUsers.values) {
      users.remove(nick);
    }
  }

  void _renameUserAcrossChannels(String? oldNick, String? newNick) {
    if (oldNick == null || oldNick.isEmpty || newNick == null || newNick.isEmpty) {
      return;
    }

    for (final users in _channelUsers.values) {
      if (users.remove(oldNick)) {
        users.add(newNick);
      }
    }
  }

  void _markActivityIfInactive(String tabId) {
    if (tabId == _activeTabId) {
      return;
    }

    _setTabActivity(tabId, true);
  }

  void _setTabActivity(String tabId, bool hasActivity) {
    _tabs = _tabs
        .map(
          (tab) => tab.id == tabId ? tab.copyWith(hasActivity: hasActivity) : tab,
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _cancelReconnect();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _ircService.dispose();
    super.dispose();
  }
}

String _serverTabId(String networkId) => 'server::$networkId';
String _channelTabId(String networkId, String name) => 'channel::$networkId::$name';
String _queryTabId(String networkId, String nick) => 'query::$networkId::$nick';

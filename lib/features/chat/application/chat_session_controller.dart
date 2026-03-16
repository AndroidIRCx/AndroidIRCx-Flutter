import 'dart:async';

import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/models/app_settings.dart';
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
  })  : _ircService = ircService ?? IrcService(),
        _persistence = persistence ?? ChatSessionPersistence(),
        _settingsRepository =
            settingsRepository ?? SharedPrefsSettingsRepository() {
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
  final Map<String, List<IrcMessage>> _messages = {};
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
  bool get isReconnectScheduled => _reconnectTimer?.isActive ?? false;
  Duration? get pendingReconnectDelay => _pendingReconnectDelay;
  ChatTab get activeTab => _tabs.firstWhere((tab) => tab.id == _activeTabId);
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
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> handleComposerSubmit(String input) async {
    final text = input.trim();
    if (text.isEmpty) {
      return;
    }

    if (text.startsWith('/')) {
      await _handleSlashCommand(text.substring(1));
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
          await _ircService.sendRaw('PART ${activeTab.name}');
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
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'Topic: ${frame.trailing!}',
            kind: IrcMessageKind.system,
          );
        }
      case 'JOIN':
        final channel = frame.trailing ?? _firstOrNull(frame.params);
        if (channel != null) {
          final tab = _ensureChannelTab(channel);
          final nick = frame.senderNick ?? '*';
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
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content:
                '${frame.senderNick ?? '*'} left $channel${frame.trailing == null ? '' : ' (${frame.trailing})'}',
            kind: IrcMessageKind.system,
          );
        }
      case 'QUIT':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content:
              '${frame.senderNick ?? '*'} quit${frame.trailing == null ? '' : ' (${frame.trailing})'}',
          kind: IrcMessageKind.system,
        );
      case 'NICK':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content:
              '${frame.senderNick ?? '*'} is now known as ${frame.trailing ?? _firstOrNull(frame.params) ?? '?'}',
          kind: IrcMessageKind.system,
        );
      case 'NOTICE':
        _handleNotice(frame);
      case 'PRIVMSG':
        _handlePrivmsg(frame);
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

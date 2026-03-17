import 'dart:async';

import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/dcc_session.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/dcc/services/dcc_service.dart';
import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:androidircx/features/chat/data/chat_session_persistence.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/parser/ctcp.dart';
import 'package:androidircx/irc/parser/dcc_parser.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:flutter/foundation.dart';

class ChatSessionController extends ChangeNotifier {
  static const _ctcpVersionReply = 'AndroidIRCx Flutter 1.0.0';
  static const _ctcpClientInfoReply =
      'ACTION CLIENTINFO DCC FINGER PING SOURCE TIME USERINFO VERSION';
  static const _ctcpUserInfoReply = 'AndroidIRCx Flutter user';
  static const _ctcpSourceReply = 'https://github.com/AndroidIRCx/AndroidIRCx-Flutter';
  static const _ctcpFingerReply = 'AndroidIRCx Flutter';

  ChatSessionController({
    required this.network,
    IrcService? ircService,
    DccService? dccService,
    ChatSessionPersistence? persistence,
    SettingsRepository? settingsRepository,
    CommandService? commandService,
  })  : _ircService = ircService ?? IrcService(),
        _dccService = dccService ?? DccService(),
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
  final DccService _dccService;
  final ChatSessionPersistence _persistence;
  final SettingsRepository _settingsRepository;
  final CommandService _commandService;
  final Map<String, List<IrcMessage>> _messages = {};
  final Map<String, Set<String>> _channelUsers = {};
  final Map<String, String> _channelTopics = {};
  final Map<String, String> _channelModes = {};
  final Map<String, String> _nickAccounts = {};
  final Map<String, String> _nickRealNames = {};
  final Map<String, String> _nickHosts = {};
  final Map<String, String> _nickIdents = {};
  final Map<String, String> _nickAwayMessages = {};
  final Map<String, ({String type, int messageCount})> _activeBatches = {};
  final Set<String> _autoHistoryRequestedChannels = <String>{};
  final Map<String, DateTime> _readMarkers = {};
  final Map<String, Map<String, Set<String>>> _messageReactions = {};
  final Map<String, Set<String>> _typingUsersByTab = {};
  final Map<String, List<String>> _multilineBuffers = {};
  final Map<String, DccSession> _dccSessions = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _reconnectTimer;

  late List<ChatTab> _tabs;
  late String _activeTabId;
  AppSettings _settings = const AppSettings();
  bool _isBootstrapped = false;
  bool _manualDisconnectRequested = false;
  int _reconnectAttempt = 0;
  Duration? _pendingReconnectDelay;
  String _nickPrefixChars = '~&@%+';
  String _channelPrefixChars = '#&+!';
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
  bool get canRequestServerHistory =>
      activeTab.type != ChatTabType.server && _ircService.supportsChatHistory;
  bool get canRequestOlderServerHistory =>
      canRequestServerHistory && _oldestMsgIdForTab(_activeTabId) != null;
  bool get canRequestNewerServerHistory =>
      canRequestServerHistory && _latestMsgIdForTab(_activeTabId) != null;
  int get activityCount => _tabs.where((tab) => tab.hasActivity).length;
  bool get hasActivity => activityCount > 0;
  String? get activeChannelTopic => _channelTopics[activeTabId];
  String? get activeChannelModes => _channelModes[activeTabId];
  DateTime? get activeReadMarker => _readMarkers[activeTabId];
  List<String> get activeTypingUsers =>
      List<String>.unmodifiable((_typingUsersByTab[activeTabId] ?? const <String>{}).toList()..sort());
  DccSession? get activeDccSession => _dccSessions[activeTabId];
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
  List<({String nick, String details})> get activeChannelUserDetails {
    return List<({String nick, String details})>.unmodifiable(
      activeChannelUsers.map((nick) => (nick: nick, details: userDetailsForNick(nick))),
    );
  }
  List<IrcMessage> get activeMessages {
    return messagesForTab(_activeTabId);
  }

  IrcMessage? messageByMsgId(String tabId, String msgid) {
    final normalized = msgid.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final messages = _messages[tabId];
    if (messages == null) {
      return null;
    }

    for (final message in messages) {
      if (message.tags['msgid'] == normalized) {
        return message;
      }
    }

    return null;
  }

  Map<String, int> reactionsForMessage(IrcMessage message) {
    final msgid = (message.tags['msgid'] ?? '').trim();
    if (msgid.isEmpty) {
      return const <String, int>{};
    }

    final reactions = _messageReactions[msgid];
    if (reactions == null || reactions.isEmpty) {
      return const <String, int>{};
    }

    final summary = <String, int>{};
    final entries = reactions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      summary[entry.key] = entry.value.length;
    }
    return summary;
  }

  String userDetailsForNick(String nick) {
    final key = nick.trim().toLowerCase();
    if (key.isEmpty) {
      return '';
    }

    final details = <String>[
      if ((_nickAccounts[key] ?? '').isNotEmpty) 'account: ${_nickAccounts[key]}',
      if ((_nickRealNames[key] ?? '').isNotEmpty) 'realname: ${_nickRealNames[key]}',
      if ((_nickIdents[key] ?? '').isNotEmpty || (_nickHosts[key] ?? '').isNotEmpty)
        '${(_nickIdents[key] ?? '').isEmpty ? '*' : _nickIdents[key]}@${(_nickHosts[key] ?? '').isEmpty ? '*' : _nickHosts[key]}',
      if ((_nickAwayMessages[key] ?? '').isNotEmpty)
        _nickAwayMessages[key] == '__away__'
            ? 'away'
            : 'away: ${_nickAwayMessages[key]}',
    ];
    return details.join(' • ');
  }

  void _rememberFrameSenderState(IrcMessageFrame frame) {
    final nick = frame.senderNick;
    if (nick == null || nick.trim().isEmpty) {
      return;
    }

    final identity = _senderIdentity(frame);
    final accountTag = frame.tags['account'] ??
        frame.tags['+account'] ??
        frame.tags['draft/account'] ??
        frame.tags['+draft/account'];
    _rememberNickState(
      nick,
      ident: identity.ident,
      host: identity.host,
      account: accountTag,
    );
  }

  String _messageContextTarget(String fallbackTarget, Map<String, String?> tags) {
    final context = (tags['draft/channel-context'] ??
            tags['+draft/channel-context'] ??
            tags['channel-context'] ??
            tags['+channel-context'] ??
            '')
        .trim();
    if (context.isEmpty) {
      return fallbackTarget;
    }

    return context;
  }

  void _rememberContextualChannelUser(String target, String? senderNick) {
    final nick = (senderNick ?? '').trim();
    if (nick.isEmpty || !_isChannelName(target)) {
      return;
    }

    final tab = _ensureChannelTab(target);
    _channelUsers.putIfAbsent(tab.id, () => <String>{}).add(nick);
  }

  void _rememberNickState(
    String nick, {
    String? account,
    String? realName,
    String? ident,
    String? host,
    String? awayMessage,
    bool clearAway = false,
  }) {
    final key = nick.trim().toLowerCase();
    if (key.isEmpty) {
      return;
    }

    if (account != null) {
      final normalized = account.trim();
      if (normalized.isEmpty || normalized == '*') {
        _nickAccounts.remove(key);
      } else {
        _nickAccounts[key] = normalized;
      }
    }

    if (realName != null) {
      final normalized = realName.trim();
      if (normalized.isEmpty) {
        _nickRealNames.remove(key);
      } else {
        _nickRealNames[key] = normalized;
      }
    }

    if (ident != null) {
      final normalized = ident.trim();
      if (normalized.isEmpty || normalized == '*') {
        _nickIdents.remove(key);
      } else {
        _nickIdents[key] = normalized;
      }
    }

    if (host != null) {
      final normalized = host.trim();
      if (normalized.isEmpty || normalized == '*') {
        _nickHosts.remove(key);
      } else {
        _nickHosts[key] = normalized;
      }
    }

    if (clearAway) {
      _nickAwayMessages.remove(key);
    } else if (awayMessage != null) {
      final normalized = awayMessage.trim();
      if (normalized.isEmpty) {
        _nickAwayMessages.remove(key);
      } else {
        _nickAwayMessages[key] = normalized;
      }
    }
  }

  ({String? ident, String? host}) _senderIdentity(IrcMessageFrame frame) {
    final prefix = frame.prefix ?? '';
    final bangIndex = prefix.indexOf('!');
    final atIndex = prefix.indexOf('@');
    if (bangIndex == -1 || atIndex == -1 || bangIndex > atIndex) {
      return (ident: null, host: null);
    }

    final ident = prefix.substring(bangIndex + 1, atIndex).trim();
    final host = prefix.substring(atIndex + 1).trim();
    return (
      ident: ident.isEmpty ? null : ident,
      host: host.isEmpty ? null : host,
    );
  }

  ({String nick, String? ident, String? host}) _parseNamesEntry(String entry) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) {
      return (nick: '', ident: null, host: null);
    }

    var cursor = trimmed;
    while (cursor.isNotEmpty && _nickPrefixChars.contains(cursor[0])) {
      cursor = cursor.substring(1);
    }

    final bangIndex = cursor.indexOf('!');
    final atIndex = cursor.indexOf('@');
    if (bangIndex == -1 || atIndex == -1 || bangIndex > atIndex) {
      return (
        nick: _normalizeNickPrefix(trimmed),
        ident: null,
        host: null,
      );
    }

    final nick = cursor.substring(0, bangIndex).trim();
    final ident = cursor.substring(bangIndex + 1, atIndex).trim();
    final host = cursor.substring(atIndex + 1).trim();
    return (
      nick: nick,
      ident: ident.isEmpty ? null : ident,
      host: host.isEmpty ? null : host,
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
      _subscriptions.add(_ircService.labeledResponses.listen((event) {
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content:
              'Labeled response matched: ${event.command} [${event.label}]',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
      }));
      _subscriptions.add(_dccService.sessions.listen((session) {
        final previous = _dccSessions[session.tabId];
        _dccSessions[session.tabId] = session;
        _appendDccStatusMessage(previous: previous, next: session);
        unawaited(_persistState());
        notifyListeners();
      }));
      _subscriptions.add(_dccService.messages.listen((event) {
        _appendMessage(
          tabId: event.tabId,
          sender: event.sender,
          content: event.content,
          isOwn: event.isOwn,
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
    unawaited(_sendReadMarkerForTab(tabId));
    unawaited(_persistState());
    notifyListeners();
  }

  void closeTab(String tabId) {
    final tab = _findTab(tabId);
    if (tab == null || tab.type == ChatTabType.server) {
      return;
    }

    final dccSession = _dccSessions[tabId];
    if (dccSession != null) {
      unawaited(_dccService.close(dccSession));
    }

    _tabs = _tabs.where((item) => item.id != tabId).toList(growable: false);
    _messages.remove(tabId);
    _channelUsers.remove(tabId);
    _channelTopics.remove(tabId);
    _dccSessions.remove(tabId);

    if (_activeTabId == tabId) {
      _activeTabId = _serverTabId(network.id);
      _setTabActivity(_activeTabId, false);
    }

    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> handleComposerSubmit(String input, {String? replyTo}) async {
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

    if (activeTab.type == ChatTabType.dcc) {
      await _handleDccComposerSubmit(text);
      return;
    }

    final normalizedReply = (replyTo ?? '').trim();
    await _ircService.sendPrivmsg(
      target: activeTab.name,
      text: text,
      replyTo: normalizedReply.isEmpty ? null : normalizedReply,
    );
    if (!_ircService.enabledCapabilities.contains('echo-message')) {
      _appendMessage(
        tabId: activeTab.id,
        sender: _ircService.currentNick ?? network.nickname,
        content: text,
        tags: {
          if (normalizedReply.isNotEmpty) 'draft/reply': normalizedReply,
        },
        isOwn: true,
      );
    }
    unawaited(_ircService.sendTyping(target: activeTab.name, status: 'done'));
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> acceptActiveDccSession() async {
    final session = activeDccSession;
    if (session == null) {
      return;
    }
    if (session.type == DccSessionType.send && session.isReverse) {
      _appendMessage(
        tabId: session.tabId,
        sender: 'error',
        content: 'Reverse DCC SEND is detected, but direct reverse accept is not implemented yet.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }
    await _dccService.accept(session);
    final latest = _dccService.sessionForTab(session.tabId);
    if (latest != null) {
      _dccSessions[session.tabId] = latest;
    }
    _appendMessage(
      tabId: session.tabId,
      sender: '*',
      content: session.type == DccSessionType.chat
          ? 'DCC CHAT accept requested.'
          : 'DCC SEND accept requested.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> declineActiveDccSession() async {
    final session = activeDccSession;
    if (session == null) {
      return;
    }
    await _dccService.close(session);
    final latest = _dccService.sessionForTab(session.tabId);
    if (latest != null) {
      _dccSessions[session.tabId] = latest;
    }
    _appendMessage(
      tabId: session.tabId,
      sender: '*',
      content: 'DCC session declined.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> closeActiveDccSession() async {
    final session = activeDccSession;
    if (session == null) {
      return;
    }
    await _dccService.close(session);
    final latest = _dccService.sessionForTab(session.tabId);
    if (latest != null) {
      _dccSessions[session.tabId] = latest;
    }
    _appendMessage(
      tabId: session.tabId,
      sender: '*',
      content: 'DCC session closed.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _handleDccComposerSubmit(String text) async {
    final session = activeDccSession;
    if (session == null) {
      return;
    }

    if (session.type != DccSessionType.chat) {
      _appendMessage(
        tabId: session.tabId,
        sender: 'error',
        content: 'DCC SEND tabs do not support chat messages.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    if (session.status != DccSessionStatus.connected) {
      _appendMessage(
        tabId: session.tabId,
        sender: 'error',
        content: 'DCC CHAT is not connected yet.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    await _dccService.sendChatMessage(
      session: session,
      sender: currentNick,
      text: text,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _startOutgoingDccChat(String nick) async {
    final sessionId = 'outgoing-chat-${DateTime.now().microsecondsSinceEpoch}';
    final tab = _ensureDccTab(
      sessionId: sessionId,
      name: 'DCC CHAT $nick',
    );
    _activeTabId = tab.id;
    try {
      await _dccService.startOutgoingChat(
        peerNick: nick,
        tabId: tab.id,
        onOfferReady: (ctcpOffer) {
          unawaited(_ircService.sendRaw('PRIVMSG $nick :$ctcpOffer'));
        },
      );
      _appendMessage(
        tabId: tab.id,
        sender: '*',
        content: 'Offering DCC CHAT to $nick.',
        kind: IrcMessageKind.system,
      );
    } catch (error) {
      _appendMessage(
        tabId: tab.id,
        sender: 'error',
        content: 'Unable to start DCC CHAT offer: $error',
        kind: IrcMessageKind.system,
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _startOutgoingDccSend({
    required String nick,
    required String filePath,
  }) async {
    final sessionId = 'outgoing-send-${DateTime.now().microsecondsSinceEpoch}';
    final tab = _ensureDccTab(
      sessionId: sessionId,
      name: 'DCC SEND $nick',
    );
    _activeTabId = tab.id;
    try {
      final session = await _dccService.startOutgoingSend(
        peerNick: nick,
        filePath: filePath,
        tabId: tab.id,
        onOfferReady: (ctcpOffer) {
          unawaited(_ircService.sendRaw('PRIVMSG $nick :$ctcpOffer'));
        },
      );
      _appendMessage(
        tabId: tab.id,
        sender: '*',
        content:
            'Offering DCC SEND to $nick: ${session.filename ?? filePath} (${session.size ?? 0} bytes).',
        kind: IrcMessageKind.system,
      );
    } catch (error) {
      _appendMessage(
        tabId: tab.id,
        sender: 'error',
        content: 'Unable to start DCC SEND offer: $error',
        kind: IrcMessageKind.system,
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _handleDccResumeCommand(String rest) async {
    final session = activeDccSession;
    if (session == null || session.type != DccSessionType.send) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Open a DCC SEND tab before using /dccresume.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }
    final offset = int.tryParse(rest.trim()) ?? session.bytesTransferred;
    await _sendDccResumeLikeCommand(
      session: session,
      subcommand: 'RESUME',
      offset: offset,
    );
  }

  Future<void> _handleDccAcceptCommand(String rest) async {
    final session = activeDccSession;
    if (session == null || session.type != DccSessionType.send) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Open a DCC SEND tab before using /dccaccept.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }
    final offset = int.tryParse(rest.trim()) ?? session.resumeOffset;
    await _sendDccResumeLikeCommand(
      session: session,
      subcommand: 'ACCEPT',
      offset: offset,
    );
  }

  Future<void> _sendDccResumeLikeCommand({
    required DccSession session,
    required String subcommand,
    required int offset,
  }) async {
    final fileName = (session.filename ?? '').trim();
    final port = session.port;
    if (fileName.isEmpty || port == null) {
      _appendMessage(
        tabId: session.tabId,
        sender: 'error',
        content: 'This DCC session is missing filename/port for $subcommand.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    final args = <String>[
      subcommand,
      '"$fileName"',
      '$port',
      '$offset',
      if ((session.token ?? '').trim().isNotEmpty) session.token!.trim(),
    ].join(' ');
    await _ircService.sendCtcpRequest(
      target: session.peerNick,
      command: 'DCC',
      args: args,
    );
    _dccSessions[session.tabId] = session.copyWith(resumeOffset: offset);
    _appendMessage(
      tabId: session.tabId,
      sender: '*',
      content: 'Sent DCC $subcommand for $fileName at offset $offset.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  List<IrcMessage> messagesForTab(
    String tabId, {
    String query = '',
    Set<IrcMessageKind>? kinds,
  }) {
    final source = _messages[tabId] ?? const <IrcMessage>[];
    final normalizedQuery = query.trim().toLowerCase();
    final effectiveKinds = kinds ?? <IrcMessageKind>{};
    return List<IrcMessage>.unmodifiable(
      source.where((message) {
        if (!_settings.showRawEvents && message.kind == IrcMessageKind.raw) {
          return false;
        }
        if (effectiveKinds.isNotEmpty && !effectiveKinds.contains(message.kind)) {
          return false;
        }
        if (normalizedQuery.isEmpty) {
          return true;
        }

        return message.sender.toLowerCase().contains(normalizedQuery) ||
            message.content.toLowerCase().contains(normalizedQuery);
      }),
    );
  }

  String exportTabHistory(
    String tabId, {
    String query = '',
    Set<IrcMessageKind>? kinds,
  }) {
    final messages = messagesForTab(tabId, query: query, kinds: kinds);
    return messages
        .map((message) {
          final stamp = message.timestamp.toIso8601String();
          final tags = message.tags.isEmpty
              ? ''
              : ' [tags: ${message.tags.entries.map((e) => e.value == null ? e.key : '${e.key}=${e.value}').join(', ')}]';
          return '[$stamp] <${message.sender}> ${message.content}$tags';
        })
        .join('\n');
  }

  Future<bool> requestRecentHistory({int limit = 50}) async {
    if (activeTab.type == ChatTabType.server) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Open a channel or query tab to request CHATHISTORY.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return false;
    }

    final normalizedLimit = limit.clamp(1, 200);
    final success = await _ircService.sendChatHistory(
      target: activeTab.name,
      subcommand: 'LATEST',
      reference: '*',
      limit: normalizedLimit,
    );
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: success ? '*' : 'error',
      content: success
          ? 'Requested recent history for ${activeTab.name} ($normalizedLimit messages).'
          : 'CHATHISTORY is not supported by this server.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
    return success;
  }

  Future<bool> requestOlderHistory({int limit = 50}) async {
    if (activeTab.type == ChatTabType.server) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Open a channel or query tab to request CHATHISTORY.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return false;
    }

    final reference = _oldestMsgIdForTab(_activeTabId);
    if (reference == null) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'No history anchor is available yet for ${activeTab.name}.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return false;
    }

    final normalizedLimit = limit.clamp(1, 200);
    final success = await _ircService.sendChatHistory(
      target: activeTab.name,
      subcommand: 'BEFORE',
      reference: reference,
      limit: normalizedLimit,
    );
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: success ? '*' : 'error',
      content: success
          ? 'Requested older history for ${activeTab.name} before $reference ($normalizedLimit messages).'
          : 'CHATHISTORY is not supported by this server.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
    return success;
  }

  Future<bool> requestNewerHistory({int limit = 50}) async {
    if (activeTab.type == ChatTabType.server) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Open a channel or query tab to request CHATHISTORY.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return false;
    }

    final reference = _latestMsgIdForTab(_activeTabId);
    if (reference == null) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'No recent history anchor is available yet for ${activeTab.name}.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return false;
    }

    final normalizedLimit = limit.clamp(1, 200);
    final success = await _ircService.sendChatHistory(
      target: activeTab.name,
      subcommand: 'AFTER',
      reference: reference,
      limit: normalizedLimit,
    );
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: success ? '*' : 'error',
      content: success
          ? 'Requested newer history for ${activeTab.name} after $reference ($normalizedLimit messages).'
          : 'CHATHISTORY is not supported by this server.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
    return success;
  }

  Future<bool> requestAroundLatestHistory({int limit = 50}) async {
    if (activeTab.type == ChatTabType.server) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Open a channel or query tab to request CHATHISTORY.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return false;
    }

    final reference = _latestMsgIdForTab(_activeTabId);
    if (reference == null) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'No recent history anchor is available yet for ${activeTab.name}.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return false;
    }

    final normalizedLimit = limit.clamp(1, 200);
    final success = await _ircService.sendChatHistory(
      target: activeTab.name,
      subcommand: 'AROUND',
      reference: reference,
      limit: normalizedLimit,
    );
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: success ? '*' : 'error',
      content: success
          ? 'Requested surrounding history for ${activeTab.name} around $reference ($normalizedLimit messages).'
          : 'CHATHISTORY is not supported by this server.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
    return success;
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

  Future<void> updateTypingState(String text) async {
    if (activeTab.type == ChatTabType.server) {
      return;
    }

    final trimmed = text.trim();
    final status = trimmed.isEmpty ? 'done' : 'active';
    await _ircService.sendTyping(target: activeTab.name, status: status);
  }

  Future<bool> redactMessage(IrcMessage message) async {
    final msgid = (message.tags['msgid'] ?? '').trim();
    if (msgid.isEmpty) {
      return false;
    }

    final target = _targetForTabId(message.tabId);
    if (target == null) {
      return false;
    }

    final success = await _ircService.redactMessage(target: target, msgid: msgid);
    if (!success) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'MESSAGE-REDACTION is not supported by this server.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return false;
    }

    _replaceMessageByMsgId(
      tabId: message.tabId,
      msgid: msgid,
      transform: (existing) => IrcMessage(
        id: existing.id,
        tabId: existing.tabId,
        sender: existing.sender,
        content: '[message deleted]',
        timestamp: existing.timestamp,
        tags: {
          ...existing.tags,
          'redacted': 'true',
        },
        isPlayback: existing.isPlayback,
        isOwn: existing.isOwn,
        kind: existing.kind,
      ),
    );
    unawaited(_persistState());
    notifyListeners();
    return true;
  }

  void _handleConnectionLifecycle(ConnectionSnapshot snapshot) {
    if (snapshot.phase == ConnectionPhase.connected) {
      _autoHistoryRequestedChannels.clear();
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
      _autoHistoryRequestedChannels.clear();
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
            await _ircService.sendPrivmsg(
              target: target,
              text: text,
            );
            if (!_ircService.enabledCapabilities.contains('echo-message')) {
              _appendMessage(
                tabId: tab.id,
                sender: _ircService.currentNick ?? network.nickname,
                content: text,
                isOwn: true,
              );
            }
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
            final tabId = _resolveOutgoingMessageTabId(target);
            if (!target.startsWith('#')) {
              _activeTabId = tabId;
            }
            await _ircService.sendNotice(target: target, text: text);
            if (!_ircService.enabledCapabilities.contains('echo-message')) {
              _appendMessage(
                tabId: tabId,
                sender: currentNick,
                content: text,
                isOwn: true,
              );
            }
            unawaited(_persistState());
            notifyListeners();
            return;
          }
        }
      case 'nickserv':
        if (rest.isNotEmpty) {
          await _sendServiceCommand('NickServ', rest);
          return;
        }
      case 'chanserv':
        if (rest.isNotEmpty) {
          await _sendServiceCommand('ChanServ', rest);
          return;
        }
      case 'hostserv':
        if (rest.isNotEmpty) {
          await _sendServiceCommand('HostServ', rest);
          return;
        }
      case 'operserv':
        if (rest.isNotEmpty) {
          await _sendServiceCommand('OperServ', rest);
          return;
        }
      case 'memoserv':
        if (rest.isNotEmpty) {
          await _sendServiceCommand('MemoServ', rest);
          return;
        }
      case 'botserv':
        if (rest.isNotEmpty) {
          await _sendServiceCommand('BotServ', rest);
          return;
        }
      case 'me':
        if (rest.isNotEmpty && activeTab.type != ChatTabType.server) {
          await _ircService.sendAction(target: activeTab.name, text: rest);
          if (!_ircService.enabledCapabilities.contains('echo-message')) {
            _appendMessage(
              tabId: activeTab.id,
              sender: _ircService.currentNick ?? network.nickname,
              content: '• $rest',
              isOwn: true,
            );
          }
          unawaited(_persistState());
          notifyListeners();
          return;
        }
      case 'ctcp':
        final segments = rest.split(RegExp(r'\s+'));
        if (segments.length >= 2) {
          final target = segments.first;
          final ctcpCommand = segments[1].toUpperCase();
          final args = segments.length > 2 ? segments.skip(2).join(' ') : null;
          await _ircService.sendCtcpRequest(
            target: target,
            command: ctcpCommand,
            args: args,
          );
          final tabId = _resolveOutgoingMessageTabId(target);
          if (!target.startsWith('#')) {
            _activeTabId = tabId;
          }
          if (!_ircService.enabledCapabilities.contains('echo-message')) {
            _appendMessage(
              tabId: tabId,
              sender: currentNick,
              content: _formatOutgoingCtcpMessage(ctcpCommand, args),
              isOwn: true,
              kind: IrcMessageKind.system,
            );
          }
          unawaited(_persistState());
          notifyListeners();
          return;
        }
      case 'dccchat':
        if (rest.isNotEmpty) {
          final nick = rest.split(RegExp(r'\s+')).first.trim();
          if (nick.isNotEmpty) {
            await _startOutgoingDccChat(nick);
            return;
          }
        }
      case 'dccsend':
        final separator = rest.indexOf(' ');
        if (separator != -1) {
          final nick = rest.substring(0, separator).trim();
          final filePath = rest.substring(separator + 1).trim();
          if (nick.isNotEmpty && filePath.isNotEmpty) {
            await _startOutgoingDccSend(nick: nick, filePath: filePath);
            return;
          }
        }
      case 'dccresume':
        await _handleDccResumeCommand(rest);
        return;
      case 'dccaccept':
        await _handleDccAcceptCommand(rest);
        return;
      case 'nick':
        if (rest.isNotEmpty) {
          await _ircService.sendRaw('NICK $rest');
          return;
        }
      case 'setname':
        if (rest.isNotEmpty) {
          final success = await _ircService.sendSetName(rest);
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: success ? '*' : 'error',
            content: success
                ? 'Requested realname change to: $rest'
                : 'SETNAME command is not supported by this server.',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
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
      case 'list':
        await _ircService.sendList(rest.isEmpty ? null : rest);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: rest.isEmpty ? 'Requested channel list.' : 'Requested channel list for: $rest',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'chathistory':
        if (activeTab.type == ChatTabType.server) {
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: 'error',
            content: 'Usage: open a channel or query tab, then use /chathistory [limit]',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
        final request = _parseChatHistoryRequest(rest);
        final success = await _ircService.sendChatHistory(
          target: activeTab.name,
          subcommand: request.subcommand,
          reference: request.reference,
          limit: request.limit,
        );
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: success ? '*' : 'error',
          content: success
              ? 'Requested CHATHISTORY ${request.subcommand} for ${activeTab.name} (${request.reference}, ${request.limit} messages).'
              : 'CHATHISTORY is not supported by this server.',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'motd':
        await _ircService.sendMotd();
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Requested MOTD.',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'time':
        await _ircService.sendTime(rest.isEmpty ? null : rest);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: rest.isEmpty ? 'Requested server time.' : 'Requested time for: $rest',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'version':
        await _ircService.sendVersion(rest.isEmpty ? null : rest);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: rest.isEmpty ? 'Requested server version.' : 'Requested version for: $rest',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'links':
        await _ircService.sendLinks(rest.isEmpty ? null : rest);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: rest.isEmpty ? 'Requested server links.' : 'Requested links for: $rest',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'ison':
        final nicks = rest.split(RegExp(r'\s+')).where((nick) => nick.trim().isNotEmpty).toList(growable: false);
        if (nicks.isNotEmpty) {
          await _ircService.sendIson(nicks);
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: '*',
            content: 'Requested ISON for ${nicks.join(', ')}.',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
      case 'userhost':
        final nicks = rest.split(RegExp(r'\s+')).where((nick) => nick.trim().isNotEmpty).toList(growable: false);
        if (nicks.isNotEmpty) {
          await _ircService.sendUserhost(nicks);
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: '*',
            content: 'Requested USERHOST for ${nicks.join(', ')}.',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
      case 'monitor':
        await _handleMonitorCommand(rest);
        return;
      case 'invite':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          await _ircService.sendInvite(
            nick: rest.split(' ').first,
            channel: activeTab.name,
          );
          return;
        }
      case 'ban':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          await _ircService.sendChannelMode(
            channel: activeTab.name,
            mode: '+b',
            target: rest.split(' ').first,
          );
          return;
        }
      case 'unban':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          await _ircService.sendChannelMode(
            channel: activeTab.name,
            mode: '-b',
            target: rest.split(' ').first,
          );
          return;
        }
      case 'op':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          await _ircService.sendChannelMode(
            channel: activeTab.name,
            mode: '+o',
            target: rest.split(' ').first,
          );
          return;
        }
      case 'deop':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          await _ircService.sendChannelMode(
            channel: activeTab.name,
            mode: '-o',
            target: rest.split(' ').first,
          );
          return;
        }
      case 'voice':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          await _ircService.sendChannelMode(
            channel: activeTab.name,
            mode: '+v',
            target: rest.split(' ').first,
          );
          return;
        }
      case 'devoice':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          await _ircService.sendChannelMode(
            channel: activeTab.name,
            mode: '-v',
            target: rest.split(' ').first,
          );
          return;
        }
      case 'banlist':
        if (activeTab.type == ChatTabType.channel) {
          await _ircService.sendBanList(activeTab.name);
          _appendMessage(
            tabId: activeTab.id,
            sender: '*',
            content: 'Requested ban list for ${activeTab.name}.',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
      case 'exceptlist':
        if (activeTab.type == ChatTabType.channel) {
          await _ircService.sendExceptList(activeTab.name);
          _appendMessage(
            tabId: activeTab.id,
            sender: '*',
            content: 'Requested exception list for ${activeTab.name}.',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
      case 'invitelist':
        if (activeTab.type == ChatTabType.channel) {
          await _ircService.sendInviteList(activeTab.name);
          _appendMessage(
            tabId: activeTab.id,
            sender: '*',
            content: 'Requested invite list for ${activeTab.name}.',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
      case 'quietlist':
        if (activeTab.type == ChatTabType.channel) {
          await _ircService.sendQuietList(activeTab.name);
          _appendMessage(
            tabId: activeTab.id,
            sender: '*',
            content: 'Requested quiet list for ${activeTab.name}.',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
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
      case 'metadata':
        await _handleMetadataCommand(rest);
        return;
      case 'rename':
        await _handleRenameCommand(rest);
        return;
      case 'cap':
        await _handleCapCommand(rest);
        return;
      case 'away':
        await _ircService.sendAway(rest.isEmpty ? null : rest);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: rest.isEmpty ? 'Away status cleared.' : 'Away: $rest',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'back':
        await _ircService.sendAway();
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Away status cleared.',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
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
      case '371':
      case '372':
      case '374':
      case '375':
      case '376':
      case '391':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing ?? frame.params.join(' '),
          kind: IrcMessageKind.system,
        );
      case '005':
        _handleIsupport(frame);
      case '221':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.params.length > 1
              ? 'User modes: ${frame.params[1]}'
              : (frame.trailing ?? frame.raw),
          kind: IrcMessageKind.system,
        );
      case '351':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing == null
              ? 'Server version: ${frame.params.skip(1).join(' ')}'.trim()
              : 'Server version: ${'${frame.params.skip(1).join(' ')} ${frame.trailing!}'.trim()}',
          kind: IrcMessageKind.system,
        );
      case '364':
        if (frame.params.length >= 3) {
          final server = frame.params[1];
          final hopCount = frame.params[2];
          final info = frame.trailing ?? '';
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: '*',
            content: info.isEmpty
                ? 'Link: $server ($hopCount)'
                : 'Link: $server ($hopCount) - $info',
            kind: IrcMessageKind.system,
          );
        }
      case '365':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing ?? 'End of LINKS.',
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
      case '328':
        if (frame.params.length >= 2 && frame.trailing != null) {
          final channel = frame.params[1];
          final tab = _ensureChannelTab(channel);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'Channel URL: ${frame.trailing!}',
            kind: IrcMessageKind.system,
          );
        }
      case '329':
        if (frame.params.length >= 3) {
          final channel = frame.params[1];
          final createdAt = int.tryParse(frame.params[2]);
          final tab = _ensureChannelTab(channel);
          final createdText = createdAt == null
              ? frame.params[2]
              : DateTime.fromMillisecondsSinceEpoch(createdAt * 1000, isUtc: true)
                  .toLocal()
                  .toString();
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'Channel created: $createdText',
            kind: IrcMessageKind.system,
          );
        }
      case '321':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Channel list started.',
          kind: IrcMessageKind.system,
        );
      case '322':
        if (frame.params.length >= 3) {
          final channel = frame.params[1];
          final visibleCount = frame.params[2];
          final topic = frame.trailing ?? '';
          final details = topic.isEmpty
              ? '$channel ($visibleCount users)'
              : '$channel ($visibleCount users) - $topic';
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: '*',
            content: details,
            kind: IrcMessageKind.system,
          );
        }
      case '323':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing ?? 'End of channel list.',
          kind: IrcMessageKind.system,
        );
      case '302':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing == null || frame.trailing!.trim().isEmpty
              ? 'USERHOST: no users returned.'
              : 'USERHOST: ${frame.trailing!}',
          kind: IrcMessageKind.system,
        );
      case '303':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing == null || frame.trailing!.trim().isEmpty
              ? 'ISON: nobody online.'
              : 'ISON online: ${frame.trailing!}',
          kind: IrcMessageKind.system,
        );
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
      case '301':
        _appendWhoisMessage(
          frame,
          frame.trailing == null
              ? frame.raw
              : 'WHOIS away: ${frame.params.length > 1 ? frame.params[1] : ''} ${frame.trailing!}'.trim(),
        );
      case '307':
      case '313':
      case '330':
      case '338':
      case '378':
      case '379':
      case '671':
        _appendWhoisMessage(
          frame,
          frame.trailing ?? frame.params.skip(1).join(' '),
        );
      case '760':
      case '761':
      case '762':
      case '765':
      case '766':
      case '767':
      case '768':
      case '769':
        _handleMetadataFrame(frame);
      case '317':
        _appendWhoisMessage(
          frame,
          'WHOIS idle: ${frame.params.length > 2 ? '${frame.params[1]} idle ${frame.params[2]}s' : frame.raw}',
        );
      case '305':
      case '306':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing ?? frame.raw,
          kind: IrcMessageKind.system,
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
          final flags = frame.params.length > 6 ? frame.params[6] : '';
          final whoTrailing = frame.trailing ?? '';
          final realName = whoTrailing.contains(' ')
              ? whoTrailing.substring(whoTrailing.indexOf(' ') + 1).trim()
              : whoTrailing.trim();
          _rememberNickState(
            nick,
            ident: frame.params[2],
            host: frame.params[3],
            realName: realName.isEmpty ? null : realName,
            awayMessage: flags.contains('G') ? '__away__' : null,
            clearAway: !flags.contains('G'),
          );
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
          final entries = frame.trailing!
              .split(RegExp(r'\s+'))
              .where((item) => item.isNotEmpty)
              .map(_parseNamesEntry)
              .where((entry) => entry.nick.isNotEmpty)
              .toList(growable: false);
          _channelUsers.putIfAbsent(tab.id, () => <String>{}).addAll(
            entries.map((entry) => entry.nick),
          );
          for (final entry in entries) {
            _rememberNickState(
              entry.nick,
              ident: entry.ident,
              host: entry.host,
            );
          }
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
          unawaited(_requestAutoHistoryOnJoin(channel));
        }
      case '367':
        if (frame.params.length >= 3) {
          final channel = frame.params[1];
          final mask = frame.params[2];
          final setBy = frame.params.length > 3 ? frame.params[3] : null;
          final tab = _ensureChannelTab(channel);
          final details = setBy == null ? 'Ban: $mask' : 'Ban: $mask set by $setBy';
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: details,
            kind: IrcMessageKind.system,
          );
        }
      case '730':
      case '731':
        final isOnline = frame.command == '730';
        final rawTargets = frame.trailing ?? (frame.params.length > 1 ? frame.params[1] : '');
        final nicknames = rawTargets
            .split(',')
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty)
            .toList(growable: false);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: nicknames.isEmpty
              ? (isOnline ? 'MONITOR online update.' : 'MONITOR offline update.')
              : 'MONITOR ${isOnline ? 'online' : 'offline'}: ${nicknames.join(', ')}',
          kind: IrcMessageKind.system,
        );
      case '732':
        final entries = (frame.trailing ?? (frame.params.length > 1 ? frame.params[1] : '')).trim();
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: entries.isEmpty ? 'MONITOR list is empty.' : 'MONITOR list: $entries',
          kind: IrcMessageKind.system,
        );
      case '733':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing ?? 'End of MONITOR list.',
          kind: IrcMessageKind.system,
        );
      case '734':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: 'error',
          content: frame.trailing ?? 'MONITOR list is full.',
          kind: IrcMessageKind.system,
        );
      case '346':
      case '348':
      case '728':
        _handleChannelListEntry(frame);
      case '341':
        if (frame.params.length >= 3) {
          final nick = frame.params[1];
          final channel = frame.params[2];
          final tab = _ensureChannelTab(channel);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'Invitation sent to $nick for $channel.',
            kind: IrcMessageKind.system,
          );
        }
      case '368':
        if (frame.params.length >= 2) {
          final channel = frame.params[1];
          final tab = _ensureChannelTab(channel);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: frame.trailing ?? 'End of ban list.',
            kind: IrcMessageKind.system,
          );
        }
      case '347':
      case '349':
      case '729':
        _handleChannelListEnd(frame);
      case 'INVITE':
        final channel = frame.trailing ?? (frame.params.length > 1 ? frame.params[1] : null);
        if (channel != null) {
          final inviter = frame.senderNick ?? '*';
          final invitee = frame.params.isNotEmpty ? frame.params.first : null;
          final tab = _ensureChannelTab(channel);
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: invitee == null || invitee.isEmpty || _isSelfNick(invitee)
                ? '$inviter invited you to $channel'
                : '$inviter invited $invitee to $channel',
            kind: IrcMessageKind.system,
          );
        }
      case 'RENAME':
        _handleChannelRename(frame);
      case 'JOIN':
        final channel = _firstOrNull(frame.params) ?? frame.trailing;
        if (channel != null) {
          final tab = _ensureChannelTab(channel);
          final nick = frame.senderNick ?? '*';
          _channelUsers.putIfAbsent(tab.id, () => <String>{}).add(nick);
          final identity = _senderIdentity(frame);
          final extendedJoinAccount =
              frame.params.length > 1 ? frame.params[1] : null;
          final extendedJoinRealname = frame.trailing ??
              (frame.params.length > 2 ? frame.params[2] : null);
          _rememberNickState(
            nick,
            account: extendedJoinAccount,
            realName: extendedJoinRealname,
            ident: identity.ident,
            host: identity.host,
          );
          final joinDetails = <String>[
            '$nick joined $channel',
            if (extendedJoinAccount != null &&
                extendedJoinAccount.isNotEmpty &&
                extendedJoinAccount != '*')
              'account: $extendedJoinAccount',
            if (extendedJoinRealname != null && extendedJoinRealname.isNotEmpty)
              'realname: $extendedJoinRealname',
          ].join(' • ');
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: joinDetails,
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
          final partingNick = frame.senderNick ?? '';
          _channelUsers.putIfAbsent(tab.id, () => <String>{}).remove(partingNick);
          if (_isSelfNick(partingNick)) {
            _autoHistoryRequestedChannels.remove(channel.toLowerCase());
          }
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content:
                '$partingNick left $channel${frame.trailing == null ? '' : ' (${frame.trailing})'}',
            kind: IrcMessageKind.system,
          );
        }
      case 'KICK':
        if (frame.params.length >= 2) {
          final channel = frame.params[0];
          final kickedNick = frame.params[1];
          final tab = _ensureChannelTab(channel);
          _channelUsers.putIfAbsent(tab.id, () => <String>{}).remove(kickedNick);
          if (_isSelfNick(kickedNick)) {
            _autoHistoryRequestedChannels.remove(channel.toLowerCase());
          }
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content:
                '$kickedNick was kicked from $channel by ${frame.senderNick ?? '*'}${frame.trailing == null ? '' : ' (${frame.trailing})'}',
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
      case 'CAP':
        _handleCapabilityFrame(frame);
      case 'ACCOUNT':
        _handleAccount(frame);
      case 'AWAY':
        _handleAway(frame);
      case 'CHGHOST':
        _handleChgHost(frame);
      case 'SETNAME':
        _handleSetName(frame);
      case 'METADATA':
        _handleMetadataFrame(frame);
      case 'FAIL':
      case 'WARN':
      case 'NOTE':
        _handleStandardReply(frame);
      case 'MARKREAD':
        _handleMarkRead(frame);
      case 'REDACT':
        _handleRedact(frame);
      case 'BATCH':
        _handleBatch(frame);
      case 'TAGMSG':
        _handleTagmsg(frame);
      case 'NOTICE':
        _handleNotice(frame);
      case 'TOPIC':
        _handleTopic(frame);
      case 'MODE':
        _handleMode(frame);
      case 'PRIVMSG':
        _handlePrivmsg(frame);
      case '401':
      case '263':
      case '381':
      case '396':
      case '471':
      case '473':
      case '474':
      case '475':
      case '476':
      case '477':
      case '482':
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

    _rememberFrameSenderState(frame);
    final contextualTarget = _messageContextTarget(target, frame.tags);
    _rememberContextualChannelUser(contextualTarget, frame.senderNick);

    final ctcp = parseCtcp(content);
    if (ctcp.isCtcp && ctcp.command != null) {
      _handleCtcpReply(frame, ctcp);
      return;
    }

    final tabId = _resolveNoticeTabId(
      target: contextualTarget,
      senderNick: frame.senderNick,
    );

    _appendMessage(
      tabId: tabId,
      sender: frame.senderNick ?? 'notice',
      content: content,
      timestamp: _timestampForFrame(frame),
      tags: frame.tags,
      isPlayback: _isPlaybackBatch(frame.tags['batch']),
      isOwn: _isSelfEcho(frame.senderNick),
    );
    _markActivityIfInactive(tabId);
  }

  void _handlePrivmsg(IrcMessageFrame frame) {
    final target = _firstOrNull(frame.params);
    final content = frame.trailing;
    if (target == null || content == null) {
      return;
    }

    _rememberFrameSenderState(frame);
    final contextualTarget = _messageContextTarget(target, frame.tags);
    _rememberContextualChannelUser(contextualTarget, frame.senderNick);

    final intentTag = frame.tags['draft/intent']?.toUpperCase();
    if (intentTag == 'ACTION') {
      final tabId = _resolveMessageTabId(
        target: contextualTarget,
        senderNick: frame.senderNick,
        preferServerForDirectMessages: false,
      );
      _appendMessage(
        tabId: tabId,
        sender: frame.senderNick ?? target,
        content: '• $content',
        timestamp: _timestampForFrame(frame),
        tags: frame.tags,
        isPlayback: _isPlaybackBatch(frame.tags['batch']),
        isOwn: _isSelfEcho(frame.senderNick),
      );
      _markActivityIfInactive(tabId);
      _incrementBatchCount(frame.tags['batch']);
      return;
    }

    final ctcp = parseCtcp(content);
    if (ctcp.isCtcp && ctcp.command != null) {
      if (ctcp.command == 'ACTION') {
        final tabId = _resolveMessageTabId(
          target: contextualTarget,
          senderNick: frame.senderNick,
          preferServerForDirectMessages: false,
        );
        _appendMessage(
          tabId: tabId,
          sender: frame.senderNick ?? target,
          content: '• ${ctcp.args ?? ''}'.trimRight(),
          timestamp: _timestampForFrame(frame),
          tags: frame.tags,
          isPlayback: _isPlaybackBatch(frame.tags['batch']),
          isOwn: _isSelfEcho(frame.senderNick),
        );
        _markActivityIfInactive(tabId);
        _incrementBatchCount(frame.tags['batch']);
        return;
      }

      _handleCtcpRequest(frame, ctcp);
      return;
    }

    final tabId = _resolveMessageTabId(
      target: contextualTarget,
      senderNick: frame.senderNick,
      preferServerForDirectMessages: false,
    );
    final assembledContent = _assembleMultilineContent(
      frame: frame,
      tabId: tabId,
      content: _normalizeContent(content),
    );
    if (assembledContent == null) {
      return;
    }

    _appendMessage(
      tabId: tabId,
      sender: frame.senderNick ?? target,
      content: assembledContent,
      timestamp: _timestampForFrame(frame),
      tags: frame.tags,
      isPlayback: _isPlaybackBatch(frame.tags['batch']),
      isOwn: _isSelfEcho(frame.senderNick),
    );
    _markActivityIfInactive(tabId);
    _incrementBatchCount(frame.tags['batch']);
  }

  void _handleTagmsg(IrcMessageFrame frame) {
    final target = _firstOrNull(frame.params);
    if (target == null) {
      return;
    }

    _rememberFrameSenderState(frame);
    final contextualTarget = _messageContextTarget(target, frame.tags);
    _rememberContextualChannelUser(contextualTarget, frame.senderNick);

    final tabId = _resolveMessageTabId(
      target: contextualTarget,
      senderNick: frame.senderNick,
      preferServerForDirectMessages: false,
    );
    final reactTag = frame.tags['+draft/react'] ?? frame.tags['+react'];
    final typingTag = frame.tags['+typing'] ?? frame.tags['+draft/typing'];

    if (reactTag != null && reactTag.contains(';')) {
      final separator = reactTag.indexOf(';');
      final referencedMsgid = reactTag.substring(0, separator).trim();
      final emoji = reactTag.substring(separator + 1).trim();
      if (referencedMsgid.isNotEmpty && emoji.isNotEmpty) {
        _recordReaction(referencedMsgid, emoji, frame.senderNick ?? 'unknown');
      }
    }

    if (typingTag != null && (frame.senderNick ?? '').trim().isNotEmpty) {
      _updateTypingState(
        tabId: tabId,
        nick: frame.senderNick!,
        state: typingTag,
      );
    }

    _appendMessage(
      tabId: tabId,
      sender: '*',
      content:
          'TAGMSG from ${frame.senderNick ?? target}${frame.tags.isEmpty ? '' : ' (${frame.tags.keys.join(', ')})'}',
      timestamp: _timestampForFrame(frame),
      tags: frame.tags,
      isPlayback: _isPlaybackBatch(frame.tags['batch']),
      kind: IrcMessageKind.system,
    );
    _markActivityIfInactive(tabId);
    _incrementBatchCount(frame.tags['batch']);
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

  void _handleIsupport(IrcMessageFrame frame) {
    final tokens = <String>[
      ...frame.params.skip(1),
      if (frame.trailing != null) frame.trailing!,
    ];
    for (final token in tokens) {
      if (token.startsWith('PREFIX=')) {
        final match = RegExp(r'^PREFIX=\(([^)]*)\)(.+)$').firstMatch(token);
        if (match != null && (match.group(2) ?? '').isNotEmpty) {
          _nickPrefixChars = match.group(2)!;
        }
      } else if (token.startsWith('CHANTYPES=')) {
        final value = token.substring('CHANTYPES='.length).trim();
        if (value.isNotEmpty) {
          _channelPrefixChars = value;
        }
      }
    }

    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: frame.trailing ?? frame.params.skip(1).join(' '),
      kind: IrcMessageKind.system,
    );
  }

  void _handleStandardReply(IrcMessageFrame frame) {
    final severity = frame.command.toLowerCase();
    final target = _firstOrNull(frame.params);
    final tabId = target != null && _isChannelName(target)
        ? _ensureChannelTab(target).id
        : _serverTabId(network.id);
    final details = <String>[
      if (frame.params.length > 1) frame.params[1],
      if (frame.params.length > 2) frame.params.skip(2).join(' '),
      if (frame.trailing != null) frame.trailing!,
    ].where((part) => part.trim().isNotEmpty).join(' • ');
    _appendMessage(
      tabId: tabId,
      sender: severity,
      content: details.isEmpty ? frame.raw : details,
      kind: IrcMessageKind.system,
    );
  }

  void _handleChannelListEntry(IrcMessageFrame frame) {
    if (frame.params.length < 3) {
      return;
    }

    final channel = frame.params[1];
    final mask = frame.params[2];
    final setBy = frame.params.length > 3 ? frame.params[3] : null;
    final tab = _ensureChannelTab(channel);
    final label = switch (frame.command) {
      '346' => 'Invite exception',
      '348' => 'Exception',
      '728' => 'Quiet',
      _ => 'List entry',
    };
    final details = setBy == null ? '$label: $mask' : '$label: $mask set by $setBy';
    _appendMessage(
      tabId: tab.id,
      sender: '*',
      content: details,
      kind: IrcMessageKind.system,
    );
  }

  void _handleChannelListEnd(IrcMessageFrame frame) {
    if (frame.params.length < 2) {
      return;
    }

    final channel = frame.params[1];
    final tab = _ensureChannelTab(channel);
    final fallback = switch (frame.command) {
      '347' => 'End of invite exception list.',
      '349' => 'End of exception list.',
      '729' => 'End of quiet list.',
      _ => 'End of channel list.',
    };
    _appendMessage(
      tabId: tab.id,
      sender: '*',
      content: frame.trailing ?? fallback,
      kind: IrcMessageKind.system,
    );
  }

  void _handleAccount(IrcMessageFrame frame) {
    final nick = frame.senderNick ?? 'unknown';
    final account = _firstOrNull(frame.params) ?? '*';
    _rememberNickState(nick, account: account);
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: account == '*'
          ? '$nick logged out'
          : '$nick logged in as $account',
      kind: IrcMessageKind.system,
    );
  }

  void _handleAway(IrcMessageFrame frame) {
    final nick = frame.senderNick ?? 'unknown';
    final awayMessage = frame.trailing ?? _firstOrNull(frame.params) ?? '';
    _rememberNickState(
      nick,
      awayMessage: awayMessage.isEmpty ? null : awayMessage,
      clearAway: awayMessage.isEmpty,
    );
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: awayMessage.isEmpty
          ? '$nick is no longer away'
          : '$nick is now away: $awayMessage',
      kind: IrcMessageKind.system,
    );
  }

  void _handleChgHost(IrcMessageFrame frame) {
    final nick = frame.senderNick ?? 'unknown';
    final newIdent = frame.params.isNotEmpty ? frame.params[0] : null;
    final newHost = frame.params.length > 1 ? frame.params[1] : frame.trailing ?? '';
    if (newHost.isEmpty) {
      return;
    }

    _rememberNickState(
      nick,
      ident: newIdent,
      host: newHost,
    );

    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: '$nick changed host to $newHost',
      kind: IrcMessageKind.system,
    );
  }

  void _handleSetName(IrcMessageFrame frame) {
    final nick = frame.senderNick ?? 'unknown';
    final newRealName = frame.trailing ?? _firstOrNull(frame.params) ?? '';
    if (newRealName.isEmpty) {
      return;
    }

    _rememberNickState(nick, realName: newRealName);

    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: '$nick changed realname to: $newRealName',
      kind: IrcMessageKind.system,
    );
  }

  void _handleMetadataFrame(IrcMessageFrame frame) {
    final isNumeric = int.tryParse(frame.command) != null;
    final target = isNumeric
        ? (frame.params.length > 1 ? frame.params[1] : null)
        : (frame.params.isNotEmpty ? frame.params.first : null);
    final key = isNumeric
        ? (frame.params.length > 2 ? frame.params[2] : null)
        : (frame.params.length > 1 ? frame.params[1] : null);
    final tabId = target != null && _isChannelName(target)
        ? _ensureChannelTab(target).id
        : _serverTabId(network.id);
    final details = <String>[
      if (target != null && target.isNotEmpty) target,
      if (key != null && key.isNotEmpty) key,
      if (frame.trailing != null && frame.trailing!.isNotEmpty) frame.trailing!,
    ].join(' • ');
    _appendMessage(
      tabId: tabId,
      sender: '*',
      content: details.isEmpty ? frame.raw : 'METADATA $details',
      kind: IrcMessageKind.system,
    );
  }

  void _handleChannelRename(IrcMessageFrame frame) {
    if (frame.params.length < 2) {
      return;
    }

    final oldName = frame.params[0];
    final newName = frame.params[1];
    final tab = _findTab(_channelTabId(network.id, oldName));
    if (tab == null) {
      return;
    }

    final renamedTab = tab.copyWith(
      id: _channelTabId(network.id, newName),
      name: newName,
    );
    _tabs = _tabs
        .map((item) => item.id == tab.id ? renamedTab : item)
        .toList(growable: false);

    final existingMessages = _messages.remove(tab.id);
    if (existingMessages != null) {
      _messages[renamedTab.id] = existingMessages
          .map((message) => IrcMessage(
                id: message.id,
                tabId: renamedTab.id,
                sender: message.sender,
                content: message.content,
                timestamp: message.timestamp,
                tags: message.tags,
                isPlayback: message.isPlayback,
                isOwn: message.isOwn,
                kind: message.kind,
              ))
          .toList(growable: true);
    }

    final users = _channelUsers.remove(tab.id);
    if (users != null) {
      _channelUsers[renamedTab.id] = users;
    }
    final topic = _channelTopics.remove(tab.id);
    if (topic != null) {
      _channelTopics[renamedTab.id] = topic;
    }
    final modes = _channelModes.remove(tab.id);
    if (modes != null) {
      _channelModes[renamedTab.id] = modes;
    }
    if (_activeTabId == tab.id) {
      _activeTabId = renamedTab.id;
    }

    _appendMessage(
      tabId: renamedTab.id,
      sender: '*',
      content:
          '${frame.senderNick ?? '*'} renamed $oldName to $newName${frame.trailing == null ? '' : ' (${frame.trailing})'}',
      kind: IrcMessageKind.system,
    );
  }

  void _handleMarkRead(IrcMessageFrame frame) {
    final target = _firstOrNull(frame.params);
    if (target == null) {
      return;
    }

    final timestampParam = frame.params.length > 1 ? frame.params[1] : '';
    final match = RegExp(r'timestamp=(\d+)').firstMatch(timestampParam);
    final markerTimestamp = match == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(int.parse(match.group(1)!));
    final tabId = _targetToTabId(target);
    if (tabId == null) {
      return;
    }

    _readMarkers[tabId] = markerTimestamp;
    _appendMessage(
      tabId: tabId,
      sender: '*',
      content:
          '${frame.senderNick ?? 'Someone'} marked $target as read at ${markerTimestamp.toLocal().toIso8601String()}',
      kind: IrcMessageKind.system,
    );
  }

  void _handleRedact(IrcMessageFrame frame) {
    if (frame.params.length < 2) {
      return;
    }

    final target = frame.params[0];
    final msgid = frame.params[1].trim();
    if (msgid.isEmpty) {
      return;
    }

    final tabId = _targetToTabId(target);
    if (tabId == null) {
      return;
    }

    final replaced = _replaceMessageByMsgId(
      tabId: tabId,
      msgid: msgid,
      transform: (existing) => IrcMessage(
        id: existing.id,
        tabId: existing.tabId,
        sender: existing.sender,
        content: '[message deleted]',
        timestamp: existing.timestamp,
        tags: {
          ...existing.tags,
          'redacted': 'true',
        },
        isPlayback: existing.isPlayback,
        isOwn: existing.isOwn,
        kind: existing.kind,
      ),
    );

    _appendMessage(
      tabId: tabId,
      sender: '*',
      content:
          '${frame.senderNick ?? 'Someone'} deleted a message${replaced ? '' : ' ($msgid)'}',
      kind: IrcMessageKind.system,
    );
    _markActivityIfInactive(tabId);
  }

  String? _assembleMultilineContent({
    required IrcMessageFrame frame,
    required String tabId,
    required String content,
  }) {
    final concatTag = frame.tags['draft/multiline-concat'];
    if (concatTag == null) {
      return content;
    }

    final sender = frame.senderNick ?? '';
    final target = _firstOrNull(frame.params) ?? '';
    final key = '${sender.toLowerCase()}|${target.toLowerCase()}|$tabId';
    final buffer = _multilineBuffers.putIfAbsent(key, () => <String>[]);
    buffer.add(content);
    final isLast = concatTag.isEmpty;
    if (!isLast) {
      return null;
    }

    _multilineBuffers.remove(key);
    return buffer.join('\n');
  }

  void _recordReaction(String msgid, String emoji, String nick) {
    final emojiUsers = _messageReactions.putIfAbsent(msgid, () => <String, Set<String>>{});
    emojiUsers.putIfAbsent(emoji, () => <String>{}).add(nick);
  }

  void _updateTypingState({
    required String tabId,
    required String nick,
    required String state,
  }) {
    final normalizedState = state.trim().toLowerCase();
    final users = _typingUsersByTab.putIfAbsent(tabId, () => <String>{});
    if (normalizedState == 'active' || normalizedState == 'composing') {
      users.add(nick);
    } else {
      users.remove(nick);
    }
    if (users.isEmpty) {
      _typingUsersByTab.remove(tabId);
    }
  }

  String _normalizeContent(String content) {
    const actionPrefix = '\u0001ACTION ';
    if (content.startsWith(actionPrefix) && content.endsWith('\u0001')) {
      return '• ${content.substring(actionPrefix.length, content.length - 1)}';
    }

    return content;
  }

  Future<void> _requestAutoHistoryOnJoin(String channel, {int limit = 50}) async {
    final normalizedChannel = channel.trim();
    if (normalizedChannel.isEmpty || !_ircService.supportsChatHistory) {
      return;
    }

    final key = normalizedChannel.toLowerCase();
    if (!_autoHistoryRequestedChannels.add(key)) {
      return;
    }

    final success = await _ircService.sendChatHistory(
      target: normalizedChannel,
      subcommand: 'LATEST',
      reference: '*',
      limit: limit,
    );
    if (!success) {
      _autoHistoryRequestedChannels.remove(key);
    }
  }

  Future<void> _sendReadMarkerForTab(String tabId) async {
    final target = _targetForTabId(tabId);
    if (target == null || !_ircService.supportsReadMarker) {
      return;
    }

    final latestTimestamp = _messages[tabId]
        ?.map((message) => message.timestamp.millisecondsSinceEpoch)
        .fold<int?>(null, (current, value) => current == null || value > current ? value : current);

    final success = await _ircService.sendReadMarker(
      target: target,
      timestampMillis: latestTimestamp,
    );
    if (success) {
      _readMarkers[tabId] = DateTime.fromMillisecondsSinceEpoch(
        latestTimestamp ?? DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  void _handleBatch(IrcMessageFrame frame) {
    if (frame.params.isEmpty) {
      return;
    }

    final batchToken = frame.params.first;
    if (batchToken.startsWith('+')) {
      final ref = batchToken.substring(1);
      final type = frame.params.length > 1 ? frame.params[1] : 'unknown';
      _activeBatches[ref] = (type: type, messageCount: 0);
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: '*',
        content: 'BATCH start: $type${frame.params.length > 2 ? ' ${frame.params.skip(2).join(' ')}' : ''}',
        timestamp: _timestampForFrame(frame),
        tags: frame.tags,
        kind: IrcMessageKind.system,
      );
      return;
    }

    if (batchToken.startsWith('-')) {
      final ref = batchToken.substring(1);
      final batch = _activeBatches.remove(ref);
      final type = batch?.type ?? 'unknown';
      final summary = switch (type) {
        'chathistory' || 'history' || 'znc.in/playback' =>
          'Playback batch completed: ${batch?.messageCount ?? 0} messages',
        'netsplit' => 'Netsplit batch completed: ${batch?.messageCount ?? 0} events',
        'netjoin' => 'Netjoin batch completed: ${batch?.messageCount ?? 0} events',
        _ => 'BATCH end: $type (${batch?.messageCount ?? 0} messages)',
      };
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: '*',
        content: summary,
        timestamp: _timestampForFrame(frame),
        tags: frame.tags,
        kind: IrcMessageKind.system,
      );
    }
  }

  void _handleCtcpRequest(IrcMessageFrame frame, CtcpMessage ctcp) {
    final target = _firstOrNull(frame.params);
    final senderNick = frame.senderNick;
    if (target == null || senderNick == null || ctcp.command == null) {
      return;
    }

    final tabId = _resolveMessageTabId(
      target: target,
      senderNick: senderNick,
      preferServerForDirectMessages: false,
    );
    final command = ctcp.command!;
    if (command == 'DCC') {
      final offer = parseDccOffer('DCC ${ctcp.args ?? ''}');
      if (offer?.command == 'RESUME' || offer?.command == 'ACCEPT') {
        final handled = _handleDccControlRequest(
          senderNick: senderNick,
          offer: offer!,
        );
        if (handled != null) {
          _activeTabId = handled;
          _markActivityIfInactive(handled);
          notifyListeners();
          return;
        }
      }
      final sessionTabId = _registerIncomingDccOffer(
        senderNick: senderNick,
        args: ctcp.args,
      );
      _appendMessage(
        tabId: sessionTabId,
        sender: '*',
        content: _formatIncomingCtcpRequest(senderNick, command, ctcp.args),
        kind: IrcMessageKind.system,
      );
      _activeTabId = sessionTabId;
      _markActivityIfInactive(sessionTabId);
      notifyListeners();
      return;
    }
    _appendMessage(
      tabId: tabId,
      sender: '*',
      content: _formatIncomingCtcpRequest(senderNick, command, ctcp.args),
      kind: IrcMessageKind.system,
    );
    _markActivityIfInactive(tabId);
    unawaited(_respondToCtcpRequest(senderNick, command, ctcp.args));
  }

  String _registerIncomingDccOffer({
    required String senderNick,
    required String? args,
  }) {
    final offer = parseDccOffer('DCC ${args ?? ''}');
    final now = DateTime.now().millisecondsSinceEpoch;
    final sessionId = '${senderNick.toLowerCase()}-$now';
    final type = switch (offer?.command) {
      'CHAT' => DccSessionType.chat,
      'SEND' => DccSessionType.send,
      _ => DccSessionType.unknown,
    };
    final tabName = switch (type) {
      DccSessionType.chat => 'DCC CHAT $senderNick',
      DccSessionType.send => 'DCC SEND ${offer?.filename ?? senderNick}',
      DccSessionType.unknown => 'DCC $senderNick',
    };
    final tab = _ensureDccTab(sessionId: sessionId, name: tabName);
    final session = DccSession(
      id: sessionId,
      tabId: tab.id,
      peerNick: senderNick,
      type: type,
      status: DccSessionStatus.pending,
      direction: 'incoming',
      filename: offer?.filename,
      host: offer?.host,
      port: offer?.port,
      size: offer?.size,
      token: offer?.token,
      resumeOffset: offer?.offset ?? 0,
      isReverse: offer?.isReverseSend ?? false,
    );
    _dccService.registerSession(session);
    _dccSessions[tab.id] = session;
    return tab.id;
  }

  String? _handleDccControlRequest({
    required String senderNick,
    required DccOffer offer,
  }) {
    DccSession? session;
    for (final candidate in _dccSessions.values) {
      final tokenMatches = (candidate.token ?? '').trim() == (offer.token ?? '').trim() ||
          (offer.token ?? '').trim().isEmpty;
      if (candidate.peerNick.toLowerCase() == senderNick.toLowerCase() &&
          candidate.type == DccSessionType.send &&
          (candidate.filename ?? '').toLowerCase() == (offer.filename ?? '').toLowerCase() &&
          candidate.port == offer.port &&
          tokenMatches) {
        session = candidate;
        break;
      }
    }
    if (session == null) {
      return null;
    }

    final updated = session.copyWith(resumeOffset: offer.offset ?? session.resumeOffset);
    _dccSessions[session.tabId] = updated;
    final content = offer.command == 'RESUME'
        ? '$senderNick requested DCC RESUME for ${offer.filename ?? 'file'} at offset ${offer.offset ?? 0}.'
        : '$senderNick acknowledged DCC RESUME for ${offer.filename ?? 'file'} at offset ${offer.offset ?? 0}.';
    _appendMessage(
      tabId: session.tabId,
      sender: '*',
      content: content,
      kind: IrcMessageKind.system,
    );
    return session.tabId;
  }

  void _handleCtcpReply(IrcMessageFrame frame, CtcpMessage ctcp) {
    final target = _firstOrNull(frame.params);
    final senderNick = frame.senderNick;
    if (target == null || senderNick == null || ctcp.command == null) {
      return;
    }

    final tabId = _resolveMessageTabId(
      target: target,
      senderNick: senderNick,
      preferServerForDirectMessages: false,
    );
    _appendMessage(
      tabId: tabId,
      sender: '*',
      content: _formatIncomingCtcpReply(senderNick, ctcp.command!, ctcp.args),
      kind: IrcMessageKind.system,
    );
    _markActivityIfInactive(tabId);
  }

  Future<void> _respondToCtcpRequest(String from, String command, String? args) async {
    switch (command) {
      case 'VERSION':
        await _ircService.sendCtcpReply(
          target: from,
          command: 'VERSION',
          args: _ctcpVersionReply,
        );
      case 'TIME':
        await _ircService.sendCtcpReply(
          target: from,
          command: 'TIME',
          args: DateTime.now().toUtc().toIso8601String(),
        );
      case 'PING':
        await _ircService.sendCtcpReply(
          target: from,
          command: 'PING',
          args: (args ?? '').trim().isEmpty
              ? DateTime.now().millisecondsSinceEpoch.toString()
              : args,
        );
      case 'CLIENTINFO':
        await _ircService.sendCtcpReply(
          target: from,
          command: 'CLIENTINFO',
          args: _ctcpClientInfoReply,
        );
      case 'USERINFO':
        await _ircService.sendCtcpReply(
          target: from,
          command: 'USERINFO',
          args: _ctcpUserInfoReply,
        );
      case 'SOURCE':
        await _ircService.sendCtcpReply(
          target: from,
          command: 'SOURCE',
          args: _ctcpSourceReply,
        );
      case 'FINGER':
        await _ircService.sendCtcpReply(
          target: from,
          command: 'FINGER',
          args: _ctcpFingerReply,
        );
      case 'DCC':
      case 'XDCC':
      case 'TDCC':
      case 'RDCC':
      case 'ACTION':
        return;
      default:
        return;
    }
  }

  String _formatOutgoingCtcpMessage(String command, String? args) {
    final suffix = (args ?? '').trim();
    if (suffix.isEmpty) {
      return 'Sent CTCP $command';
    }

    return 'Sent CTCP $command: $suffix';
  }

  String _formatIncomingCtcpRequest(String from, String command, String? args) {
    if (command == 'DCC') {
      final offer = parseDccOffer('DCC ${args ?? ''}');
      if (offer != null) {
        return switch (offer.command) {
          'CHAT' => 'DCC CHAT request from $from: ${offer.host ?? '?'}:${offer.port ?? 0}',
          'SEND' => offer.isReverseSend
              ? 'Reverse DCC SEND offer from $from: ${offer.filename ?? 'file'} (${offer.size ?? 0} bytes) token ${offer.token ?? '?'}'
              : 'DCC SEND offer from $from: ${offer.filename ?? 'file'} (${offer.size ?? 0} bytes) ${offer.host ?? '?'}:${offer.port ?? 0}',
          'RESUME' => 'DCC RESUME request from $from: ${offer.filename ?? 'file'} at ${offer.offset ?? 0}',
          'ACCEPT' => 'DCC ACCEPT reply from $from: ${offer.filename ?? 'file'} at ${offer.offset ?? 0}',
          _ => 'CTCP DCC request from $from: ${args ?? ''}',
        };
      }
    }
    if (command == 'XDCC' || command == 'TDCC' || command == 'RDCC') {
      final suffix = (args ?? '').trim();
      return suffix.isEmpty
          ? 'CTCP $command request from $from'
          : 'CTCP $command request from $from: $suffix';
    }

    final suffix = (args ?? '').trim();
    if (suffix.isEmpty) {
      return 'CTCP $command request from $from';
    }

    return 'CTCP $command request from $from: $suffix';
  }

  String _formatIncomingCtcpReply(String from, String command, String? args) {
    final suffix = (args ?? '').trim();
    if (suffix.isEmpty) {
      return 'CTCP $command reply from $from';
    }

    return 'CTCP $command reply from $from: $suffix';
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

  ChatTab _ensureNoticeTab() {
    final existing = _findTab(_noticeTabId(network.id));
    if (existing != null) {
      return existing;
    }

    final tab = ChatTab(
      id: _noticeTabId(network.id),
      name: 'Notices',
      type: ChatTabType.notice,
      networkId: network.id,
    );
    _tabs = [..._tabs, tab];
    _messages.putIfAbsent(tab.id, () => []);
    return tab;
  }

  ChatTab _ensureDccTab({
    required String sessionId,
    required String name,
  }) {
    final tabId = _dccTabId(network.id, sessionId);
    final existing = _findTab(tabId);
    if (existing != null) {
      return existing;
    }

    final tab = ChatTab(
      id: tabId,
      name: name,
      type: ChatTabType.dcc,
      networkId: network.id,
    );
    _tabs = [..._tabs, tab];
    _messages.putIfAbsent(tab.id, () => []);
    return tab;
  }

  void _appendDccStatusMessage({
    required DccSession? previous,
    required DccSession next,
  }) {
    if (previous?.status == next.status) {
      if (previous?.bytesTransferred == next.bytesTransferred) {
        return;
      }
      if (next.type != DccSessionType.send || next.bytesTransferred <= 0) {
        return;
      }
    }

    final content = switch (next.status) {
      DccSessionStatus.offering => next.type == DccSessionType.chat
          ? 'DCC CHAT offer created for ${next.peerNick}.'
          : 'DCC SEND offer created for ${next.peerNick}.',
      DccSessionStatus.connecting => next.type == DccSessionType.chat
          ? 'Connecting DCC CHAT session...'
          : 'Connecting DCC SEND transfer...',
      DccSessionStatus.connected => next.type == DccSessionType.chat
          ? 'DCC CHAT connected.'
          : next.direction == 'outgoing'
              ? 'DCC SEND transfer started for ${next.filename ?? 'file'}.'
              : 'Receiving ${next.filename ?? 'file'} to ${next.filePath ?? 'temporary storage'}.',
      DccSessionStatus.closed => next.type == DccSessionType.chat
          ? 'DCC CHAT session closed.'
          : next.direction == 'outgoing'
              ? 'DCC SEND finished (${next.bytesTransferred} bytes sent).'
              : 'DCC SEND finished (${next.bytesTransferred} bytes saved to ${next.filePath ?? 'temporary storage'}).',
      DccSessionStatus.failed =>
        'DCC ${next.type == DccSessionType.chat ? 'CHAT' : 'SEND'} failed: ${next.error ?? 'unknown error'}',
      DccSessionStatus.pending => null,
    };

    if (content == null) {
      return;
    }

    _appendMessage(
      tabId: next.tabId,
      sender: '*',
      content: content,
      kind: IrcMessageKind.system,
    );
  }

  String _resolveMessageTabId({
    required String target,
    required String? senderNick,
    required bool preferServerForDirectMessages,
  }) {
    if (target.startsWith('#')) {
      return _ensureChannelTab(target).id;
    }

    if (_isSelfEcho(senderNick) &&
        target != (_ircService.currentNick ?? network.nickname)) {
      return _ensureQueryTab(target).id;
    }

    final normalizedSender = _normalizeServiceNick(senderNick);
    if (normalizedSender != null && _isServiceNick(normalizedSender)) {
      return _ensureQueryTab(normalizedSender).id;
    }

    if (preferServerForDirectMessages) {
      return _serverTabId(network.id);
    }

    return _ensureQueryTab(senderNick ?? target).id;
  }

  String _resolveOutgoingMessageTabId(String target) {
    if (target.startsWith('#')) {
      return _ensureChannelTab(target).id;
    }

    return _ensureQueryTab(target).id;
  }

  String _resolveNoticeTabId({
    required String target,
    required String? senderNick,
  }) {
    switch (_settings.noticeRouting) {
      case NoticeRoutingMode.server:
        final normalizedSender = _normalizeServiceNick(senderNick);
        if (normalizedSender != null && _isServiceNick(normalizedSender)) {
          return _ensureQueryTab(normalizedSender).id;
        }
        return _serverTabId(network.id);
      case NoticeRoutingMode.active:
        return activeTab.id;
      case NoticeRoutingMode.notice:
        return _ensureNoticeTab().id;
      case NoticeRoutingMode.private:
        if (senderNick != null && senderNick.trim().isNotEmpty) {
          return _ensureQueryTab(senderNick).id;
        }
        return _ensureNoticeTab().id;
    }
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
    DateTime? timestamp,
    Map<String, String?> tags = const <String, String?>{},
    bool isPlayback = false,
    bool isOwn = false,
    IrcMessageKind kind = IrcMessageKind.chat,
  }) {
    final list = _messages.putIfAbsent(tabId, () => []);
    final msgid = tags['msgid'];
    if (msgid != null && list.any((item) => item.tags['msgid'] == msgid)) {
      return;
    }
    list.add(
      IrcMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}-${list.length}',
        tabId: tabId,
        sender: sender,
        content: content,
        timestamp: timestamp ?? DateTime.now(),
        tags: Map<String, String?>.unmodifiable(tags),
        isPlayback: isPlayback,
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

  Future<void> _sendServiceCommand(String service, String command) async {
    final tab = _ensureQueryTab(service);
    _activeTabId = tab.id;
    await _ircService.sendPrivmsg(target: service, text: command);
    if (!_ircService.enabledCapabilities.contains('echo-message')) {
      _appendMessage(
        tabId: tab.id,
        sender: currentNick,
        content: command,
        isOwn: true,
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> sendServiceShortcut(String service, String command) {
    return _sendServiceCommand(service, command);
  }

  void _handleCapabilityFrame(IrcMessageFrame frame) {
    if (frame.params.length < 2) {
      return;
    }

    final subcommandIndex = frame.params.first == '*' ? 1 : 0;
    if (subcommandIndex >= frame.params.length) {
      return;
    }

    final subcommand = frame.params[subcommandIndex].toUpperCase();
    final details = [
      ...frame.params.skip(subcommandIndex + 1).where((item) => item != '*'),
      if ((frame.trailing ?? '').trim().isNotEmpty) frame.trailing!.trim(),
    ].join(' ').trim();

    final message = switch (subcommand) {
      'LS' => 'CAP LS: ${details.isEmpty ? 'no capabilities reported' : details}',
      'ACK' => 'CAP ACK: ${details.isEmpty ? 'no capabilities acknowledged' : details}',
      'NAK' => 'CAP NAK: ${details.isEmpty ? 'request rejected' : details}',
      'NEW' => 'CAP NEW: ${details.isEmpty ? 'no new capabilities reported' : details}',
      'DEL' => 'CAP DEL: ${details.isEmpty ? 'no removed capabilities reported' : details}',
      'LIST' => 'CAP LIST: ${details.isEmpty ? 'no enabled capabilities reported' : details}',
      _ => 'CAP $subcommand${details.isEmpty ? '' : ': $details'}',
    };

    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: message,
      kind: IrcMessageKind.system,
    );
  }

  Future<void> _handleCapCommand(String rest) async {
    final trimmed = rest.trim();
    if (trimmed.isEmpty) {
      await _ircService.sendCapList();
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: '*',
        content: 'Requested CAP LIST.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    final subcommand = parts.first.toLowerCase();
    final args = parts.skip(1).join(' ').trim();

    switch (subcommand) {
      case 'status':
        final available = _sortedCapabilities(_ircService.availableCapabilities);
        final enabled = _sortedCapabilities(_ircService.enabledCapabilities);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Available capabilities: ${available.isEmpty ? 'none' : available.join(', ')}',
          kind: IrcMessageKind.system,
        );
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Enabled capabilities: ${enabled.isEmpty ? 'none' : enabled.join(', ')}',
          kind: IrcMessageKind.system,
        );
        break;
      case 'ls':
        await _ircService.sendCapLs();
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Requested CAP LS 302.',
          kind: IrcMessageKind.system,
        );
        break;
      case 'list':
        await _ircService.sendCapList();
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Requested CAP LIST.',
          kind: IrcMessageKind.system,
        );
        break;
      case 'req':
        if (args.isEmpty) {
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: 'error',
            content: 'Usage: /cap req <capabilities>',
            kind: IrcMessageKind.system,
          );
        } else {
          await _ircService.sendCapReq(args);
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: '*',
            content: 'Requested capabilities: $args',
            kind: IrcMessageKind.system,
          );
        }
        break;
      case 'end':
        await _ircService.sendCapEnd();
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Ended capability negotiation.',
          kind: IrcMessageKind.system,
        );
        break;
      default:
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: 'error',
          content: 'Usage: /cap <status|ls|list|req|end>',
          kind: IrcMessageKind.system,
        );
        break;
    }

    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _handleMonitorCommand(String rest) async {
    final segments = rest.split(RegExp(r'\s+')).where((part) => part.trim().isNotEmpty).toList(growable: false);
    if (segments.isEmpty) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Usage: /monitor <+|-|c|l|s> [nick[,nick...]]',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    final subcommand = segments.first.toUpperCase();
    final nicknameParts = segments.length > 1
        ? segments.skip(1).join(' ').split(RegExp(r'[\s,]+')).where((nick) => nick.trim().isNotEmpty).toList(growable: false)
        : const <String>[];
    await _ircService.sendMonitor(subcommand: subcommand, nicknames: nicknameParts);
    final detail = nicknameParts.isEmpty ? subcommand : '$subcommand ${nicknameParts.join(', ')}';
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: 'Requested MONITOR $detail.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _handleMetadataCommand(String rest) async {
    final segments = rest.split(RegExp(r'\s+'));
    if (segments.length < 2) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Usage: /metadata <target> <get|set|list|clear> [key] [value]',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    final target = segments[0];
    final subcommand = segments[1];
    final key = segments.length > 2 ? segments[2] : null;
    final value = segments.length > 3 ? segments.skip(3).join(' ') : null;
    await _ircService.sendMetadata(
      target: target,
      subcommand: subcommand,
      key: key,
      value: value,
    );
    _appendMessage(
      tabId: _isChannelName(target) ? _ensureChannelTab(target).id : _serverTabId(network.id),
      sender: '*',
      content: 'Requested METADATA ${subcommand.toUpperCase()} for $target${key == null ? '' : ' ($key)'}',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _handleRenameCommand(String rest) async {
    final segments = rest.split(RegExp(r'\s+'));
    if (segments.isEmpty || segments.first.trim().isEmpty) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'Usage: /rename <new-channel-name> [reason] from a channel tab.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }
    if (activeTab.type != ChatTabType.channel) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: '/rename can only be used from a channel tab.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    final newName = segments.first;
    final reason = segments.length > 1 ? segments.skip(1).join(' ') : null;
    await _ircService.sendChannelRename(
      oldName: activeTab.name,
      newName: newName,
      reason: reason,
    );
    _appendMessage(
      tabId: activeTab.id,
      sender: '*',
      content: 'Requested rename from ${activeTab.name} to $newName${(reason ?? '').trim().isEmpty ? '' : ' ($reason)'}',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  String _normalizeNickPrefix(String value) {
    var normalized = value.trim();
    while (normalized.isNotEmpty && _nickPrefixChars.contains(normalized[0])) {
      normalized = normalized.substring(1);
    }
    final bangIndex = normalized.indexOf('!');
    if (bangIndex != -1) {
      normalized = normalized.substring(0, bangIndex);
    }
    return normalized;
  }

  bool _isChannelName(String value) {
    if (value.isEmpty) {
      return false;
    }
    return _channelPrefixChars.contains(value[0]);
  }

  List<String> _sortedCapabilities(Set<String> values) {
    final list = values.toList(growable: false);
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String? _normalizeServiceNick(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  bool _isServiceNick(String nick) {
    switch (nick.toLowerCase()) {
      case 'nickserv':
      case 'chanserv':
      case 'hostserv':
      case 'memoserv':
      case 'botserv':
      case 'operserv':
        return true;
      default:
        return false;
    }
  }

  bool _isSelfEcho(String? senderNick) {
    final sender = senderNick?.trim();
    if (sender == null || sender.isEmpty) {
      return false;
    }

    return sender.toLowerCase() ==
        (_ircService.currentNick ?? network.nickname).toLowerCase();
  }

  DateTime? _timestampForFrame(IrcMessageFrame frame) {
    final timeTag = frame.tags['time'];
    if (timeTag == null || timeTag.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(timeTag);
  }

  bool _isPlaybackBatch(String? batchTag) {
    final batchId = (batchTag ?? '').trim();
    if (batchId.isEmpty) {
      return false;
    }

    final batch = _activeBatches[batchId];
    if (batch == null) {
      return false;
    }

    return switch (batch.type) {
      'chathistory' || 'history' || 'znc.in/playback' => true,
      _ => false,
    };
  }

  ({String subcommand, String reference, int limit}) _parseChatHistoryRequest(
    String rest,
  ) {
    final parts = rest
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return (subcommand: 'LATEST', reference: '*', limit: 50);
    }

    final keyword = parts.first.toUpperCase();
    if (keyword == 'LATEST') {
      final limit = parts.length > 1 ? int.tryParse(parts[1]) ?? 50 : 50;
      return (subcommand: 'LATEST', reference: '*', limit: limit.clamp(1, 200));
    }

    if (keyword == 'BEFORE' || keyword == 'AFTER' || keyword == 'AROUND') {
      final fallbackReference = _latestMsgIdForTab(activeTab.id) ?? '*';
      final second = parts.length > 1 ? parts[1] : null;
      final third = parts.length > 2 ? parts[2] : null;
      final secondAsLimit = second == null ? null : int.tryParse(second);
      final reference = second == null || secondAsLimit != null
          ? fallbackReference
          : second;
      final limit = third != null
          ? int.tryParse(third) ?? 50
          : secondAsLimit ?? 50;
      return (
        subcommand: keyword,
        reference: reference,
        limit: limit.clamp(1, 200),
      );
    }

    final limit = int.tryParse(parts.first) ?? 50;
    return (subcommand: 'LATEST', reference: '*', limit: limit.clamp(1, 200));
  }

  String? _latestMsgIdForTab(String tabId) {
    final messages = _messages[tabId];
    if (messages == null) {
      return null;
    }

    for (final message in messages.reversed) {
      final msgid = message.tags['msgid'];
      if (msgid != null && msgid.trim().isNotEmpty) {
        return msgid;
      }
    }

    return null;
  }

  String? _oldestMsgIdForTab(String tabId) {
    final messages = _messages[tabId];
    if (messages == null) {
      return null;
    }

    for (final message in messages) {
      final msgid = message.tags['msgid'];
      if (msgid != null && msgid.trim().isNotEmpty) {
        return msgid;
      }
    }

    return null;
  }

  bool _replaceMessageByMsgId({
    required String tabId,
    required String msgid,
    required IrcMessage Function(IrcMessage existing) transform,
  }) {
    final messages = _messages[tabId];
    if (messages == null) {
      return false;
    }

    final index = messages.indexWhere((message) => message.tags['msgid'] == msgid);
    if (index == -1) {
      return false;
    }

    messages[index] = transform(messages[index]);
    return true;
  }

  String? _targetForTabId(String tabId) {
    final tab = _findTab(tabId);
    if (tab == null || tab.type == ChatTabType.server) {
      return null;
    }

    return tab.name;
  }

  String? _targetToTabId(String target) {
    final trimmed = target.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.startsWith('#')) {
      return _ensureChannelTab(trimmed).id;
    }

    return _ensureQueryTab(trimmed).id;
  }

  bool _isSelfNick(String nick) {
    final normalized = nick.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    return normalized == (_ircService.currentNick ?? network.nickname).trim().toLowerCase();
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

    final oldKey = oldNick.trim().toLowerCase();
    final newKey = newNick.trim().toLowerCase();
    if (oldKey == newKey) {
      return;
    }
    void move(Map<String, String> values) {
      final value = values.remove(oldKey);
      if (value != null) {
        values[newKey] = value;
      }
    }

    move(_nickAccounts);
    move(_nickRealNames);
    move(_nickHosts);
    move(_nickIdents);
    move(_nickAwayMessages);
  }

  void _markActivityIfInactive(String tabId) {
    if (tabId == _activeTabId) {
      return;
    }

    _setTabActivity(tabId, true);
  }

  void _incrementBatchCount(String? batchTag) {
    final batchId = (batchTag ?? '').trim();
    if (batchId.isEmpty) {
      return;
    }

    final batch = _activeBatches[batchId];
    if (batch == null) {
      return;
    }

    _activeBatches[batchId] = (
      type: batch.type,
      messageCount: batch.messageCount + 1,
    );
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
    _dccService.dispose();
    _ircService.dispose();
    super.dispose();
  }
}

String _serverTabId(String networkId) => 'server::$networkId';
String _noticeTabId(String networkId) => 'notice::$networkId';
String _channelTabId(String networkId, String name) => 'channel::$networkId::$name';
String _queryTabId(String networkId, String nick) => 'query::$networkId::$nick';
String _dccTabId(String networkId, String sessionId) => 'dcc::$networkId::$sessionId';

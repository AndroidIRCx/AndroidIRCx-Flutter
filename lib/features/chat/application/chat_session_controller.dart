import 'dart:async';
import 'dart:math' as math;

import 'package:androidircx/core/app/app_version.dart';
import 'package:androidircx/core/models/chat_tab.dart';
import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/dcc_session.dart';
import 'package:androidircx/core/models/irc_message.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/dcc/services/dcc_service.dart';
import 'package:androidircx/features/chat/application/ban_mask_service.dart';
import 'package:androidircx/features/chat/application/command_service.dart';
import 'package:androidircx/features/chat/application/message_history_formatter.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_settings_repository.dart';
import 'package:androidircx/features/chat/data/chat_session_persistence.dart';
import 'package:androidircx/features/chat/data/message_history_repository.dart';
import 'package:androidircx/features/chat/data/user_list_entry.dart';
import 'package:androidircx/features/chat/data/user_lists_repository.dart';
import 'package:androidircx/features/chat/presentation/join_channel_dialog.dart';
import 'package:androidircx/core/models/channel_list_entry.dart';
import 'package:androidircx/core/security/certificate_store.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/sound/sound_service.dart';
import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/parser/ctcp.dart';
import 'package:androidircx/irc/parser/dcc_parser.dart';
import 'package:androidircx/irc/parser/irc_formatter.dart';
import 'package:androidircx/irc/parser/isupport_parser.dart';
import 'package:androidircx/irc/parser/message_content_parser.dart';
import 'package:androidircx/irc/services/irc_service.dart';
import 'package:androidircx/irc/services/irc_service_helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

enum ComposerAutocompleteSuggestionType { nick, channel }

class ComposerAutocompleteSuggestion {
  const ComposerAutocompleteSuggestion({
    required this.text,
    required this.type,
    required this.tokenStart,
    required this.tokenEnd,
  });

  final String text;
  final ComposerAutocompleteSuggestionType type;
  final int tokenStart;
  final int tokenEnd;
}

enum ChannelUserAction {
  whois,
  whowas,
  query,
  op,
  deop,
  voice,
  devoice,
  kick,
  ban,
  kickBan,
  ignoreToggle,
  ctcpPing,
  ctcpVersion,
  ctcpTime,
  dccChat,
}

enum ChannelModerationAction { kick, ban, kickBan, quiet }

typedef ChannelUserDetails = ({
  String nick,
  String details,
  String? prefix,
  int statusRank,
});

const channelUserStatusPrefixes = <String>['~', '&', '@', '%', '+'];

int channelUserStatusRank(String? prefix) {
  if (prefix == null || prefix.isEmpty) {
    return channelUserStatusPrefixes.length;
  }
  final rank = channelUserStatusPrefixes.indexOf(prefix);
  return rank == -1 ? channelUserStatusPrefixes.length : rank;
}

class IrcUserInfo {
  const IrcUserInfo({
    required this.nick,
    this.ident,
    this.host,
    this.realName,
    this.account,
    this.awayMessage,
    this.server,
    this.serverInfo,
    this.idleSeconds,
    this.signedOn,
    this.channels = const <String>[],
    this.isRegistered = false,
    this.isOper = false,
    this.isSecure = false,
    this.extra = const <String>[],
    this.fromWhowas = false,
  });

  final String nick;
  final String? ident;
  final String? host;
  final String? realName;
  final String? account;
  final String? awayMessage;
  final String? server;
  final String? serverInfo;
  final int? idleSeconds;
  final DateTime? signedOn;
  final List<String> channels;
  final bool isRegistered;
  final bool isOper;
  final bool isSecure;
  final List<String> extra;
  final bool fromWhowas;

  String get userhost {
    final user = (ident ?? '').trim();
    final hostValue = (host ?? '').trim();
    if (user.isEmpty && hostValue.isEmpty) {
      return '';
    }
    return '${user.isEmpty ? '*' : user}@${hostValue.isEmpty ? '*' : hostValue}';
  }

  String get hostmask {
    final uh = userhost;
    if (uh.isEmpty) {
      return '';
    }
    return '$nick!$uh';
  }

  IrcUserInfo copyWith({
    String? nick,
    String? ident,
    String? host,
    String? realName,
    String? account,
    String? awayMessage,
    String? server,
    String? serverInfo,
    int? idleSeconds,
    DateTime? signedOn,
    List<String>? channels,
    bool? isRegistered,
    bool? isOper,
    bool? isSecure,
    List<String>? extra,
    bool? fromWhowas,
    bool clearAway = false,
  }) {
    return IrcUserInfo(
      nick: nick ?? this.nick,
      ident: ident ?? this.ident,
      host: host ?? this.host,
      realName: realName ?? this.realName,
      account: account ?? this.account,
      awayMessage: clearAway ? null : (awayMessage ?? this.awayMessage),
      server: server ?? this.server,
      serverInfo: serverInfo ?? this.serverInfo,
      idleSeconds: idleSeconds ?? this.idleSeconds,
      signedOn: signedOn ?? this.signedOn,
      channels: channels ?? this.channels,
      isRegistered: isRegistered ?? this.isRegistered,
      isOper: isOper ?? this.isOper,
      isSecure: isSecure ?? this.isSecure,
      extra: extra ?? this.extra,
      fromWhowas: fromWhowas ?? this.fromWhowas,
    );
  }
}

class ChatSessionController extends ChangeNotifier {
  static const _historyPageSize = 200;
  static const _ctcpClientInfoReply =
      'ACTION CLIENTINFO DCC FINGER PING SOURCE TIME USERINFO VERSION';
  static const _ctcpUserInfoReply = 'AndroidIRCx Flutter user';
  static const _ctcpSourceReply =
      'https://github.com/AndroidIRCx/AndroidIRCx-Flutter';
  static const _ctcpFingerReply = 'AndroidIRCx Flutter';

  ChatSessionController({
    required this.network,
    IrcService? ircService,
    DccService? dccService,
    ChatSessionPersistence? persistence,
    MessageHistoryRepository? historyRepository,
    SettingsRepository? settingsRepository,
    CommandService? commandService,
    UserListsRepository? userListsRepository,
    SoundService? soundService,
    int maxReconnectAttempts = 6,
    Duration reconnectBaseDelay = const Duration(seconds: 2),
    Duration reconnectMaxDelay = const Duration(seconds: 60),
    double reconnectJitterFactor = 0.2,
    double Function()? reconnectJitterSampler,
  }) : _ircService =
           ircService ??
           IrcService(
             certificateStore: CertificateStore(FlutterSecureSecretStorage()),
           ),
       _dccService = dccService ?? DccService(),
       _persistence = persistence ?? ChatSessionPersistence(),
       _historyRepository = historyRepository,
       _settingsRepository =
           settingsRepository ?? SharedPrefsSettingsRepository(),
       _commandService = commandService ?? CommandService(),
       _userListsRepository = userListsRepository,
       _soundService = soundService,
       _maxReconnectAttempts = maxReconnectAttempts,
       _reconnectBaseDelay = reconnectBaseDelay,
       _reconnectMaxDelay = reconnectMaxDelay,
       _reconnectJitterFactor = reconnectJitterFactor.clamp(0, 1).toDouble(),
       _reconnectJitterSampler =
           reconnectJitterSampler ?? math.Random().nextDouble {
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
  final MessageHistoryRepository? _historyRepository;
  final SettingsRepository _settingsRepository;
  final CommandService _commandService;
  final UserListsRepository? _userListsRepository;
  final SoundService? _soundService;

  /// Last connection phase a sound was played for, so repeated snapshots in
  /// the same phase (or reconnect retries) do not re-trigger sounds.
  ConnectionPhase? _lastSoundedPhase;
  List<UserListEntry> _userListEntries = const <UserListEntry>[];
  bool _userListEntriesLoaded = false;
  final int _maxReconnectAttempts;
  final Duration _reconnectBaseDelay;
  final Duration _reconnectMaxDelay;
  final double _reconnectJitterFactor;
  final double Function() _reconnectJitterSampler;
  final Map<String, List<IrcMessage>> _messages = {};
  final Map<String, Set<String>> _channelUsers = {};
  final Map<String, String> _channelTopics = {};
  final Map<String, String> _channelModes = {};
  final Map<String, String> _nickAccounts = {};
  final Map<String, String> _nickRealNames = {};
  final Map<String, String> _nickHosts = {};
  final Map<String, String> _nickIdents = {};
  final Map<String, String> _nickAwayMessages = {};
  final Map<String, IrcUserInfo> _userInfoByNick = {};
  final Map<String, Map<String, Set<String>>> _channelUserModes = {};
  final Map<String, ({String type, int messageCount})> _activeBatches = {};
  final Set<String> _autoHistoryRequestedChannels = <String>{};
  final Map<String, DateTime> _readMarkers = {};
  final Map<String, Map<String, Set<String>>> _messageReactions = {};
  final Map<String, Set<String>> _typingUsersByTab = {};
  final Map<String, List<String>> _multilineBuffers = {};
  final Map<String, DccSession> _dccSessions = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final StreamController<ForegroundUserNotification> _notificationController =
      StreamController<ForegroundUserNotification>.broadcast(sync: true);
  Timer? _reconnectTimer;
  final List<Timer> _timedUnbanTimers = <Timer>[];
  final Set<String> _blacklistEnforcements = <String>{};
  Future<void>? _startInFlight;

  late List<ChatTab> _tabs;
  late String _activeTabId;
  AppSettings _settings = const AppSettings();
  bool _isBootstrapped = false;
  bool _manualDisconnectRequested = false;
  bool _isDisposed = false;
  bool _isNetworkAvailable = true;
  bool _autoJoinAttempted = false;
  bool _serviceAuthFallbackAttempted = false;
  int _reconnectAttempt = 0;
  Duration? _pendingReconnectDelay;
  IrcServerSupport _serverSupport = const IrcServerSupport.empty();
  String _nickPrefixChars = IrcServerSupport.defaultPrefixMapping.prefixes;
  String _channelPrefixChars = IrcServerSupport.defaultChannelTypes;
  ConnectionSnapshot _connection = const ConnectionSnapshot(
    networkId: '',
    phase: ConnectionPhase.idle,
  );

  List<ChatTab> get tabs => List<ChatTab>.unmodifiable(_tabs);
  String get activeTabId => _activeTabId;
  String get channelPrefixChars => _channelPrefixChars;
  String get nickPrefixChars => _nickPrefixChars;
  ConnectionSnapshot get connection => _connection;
  AppSettings get settings => _settings;
  List<CommandHistoryEntry> get commandHistory => _commandService.history;
  List<CommandSuggestion> commandSuggestionsForComposer(String input) {
    final suggestions = <CommandSuggestion>[];
    final seen = <String>{};

    void add(CommandSuggestion suggestion) {
      if (seen.add(suggestion.text.toLowerCase())) {
        suggestions.add(suggestion);
      }
    }

    for (final suggestion in _commandService.suggestCommands(
      input,
      limit: 20,
    )) {
      add(suggestion);
    }
    for (final suggestion in _commandService.suggestHistory(input, limit: 3)) {
      add(suggestion);
    }

    suggestions.sort((left, right) {
      final sourceOrder = _suggestionSourceOrder(
        left.source,
      ).compareTo(_suggestionSourceOrder(right.source));
      if (sourceOrder != 0) {
        return sourceOrder;
      }
      return left.text.toLowerCase().compareTo(right.text.toLowerCase());
    });

    return List<CommandSuggestion>.unmodifiable(suggestions.take(8));
  }

  List<ComposerAutocompleteSuggestion> autocompleteSuggestionsForComposer(
    String input, {
    int? cursorOffset,
    int limit = 8,
  }) {
    final token = _composerTokenAt(input, cursorOffset: cursorOffset);
    if (token == null) {
      return const [];
    }

    final rawToken = input.substring(token.start, token.end);
    if (rawToken.isEmpty || (token.start == 0 && rawToken.startsWith('/'))) {
      return const [];
    }

    final suggestions = <ComposerAutocompleteSuggestion>[];
    final seen = <String>{};

    void add(String value, ComposerAutocompleteSuggestionType type) {
      final normalized = value.trim();
      if (normalized.isEmpty ||
          !seen.add('${type.name}:${normalized.toLowerCase()}')) {
        return;
      }
      suggestions.add(
        ComposerAutocompleteSuggestion(
          text: normalized,
          type: type,
          tokenStart: token.start,
          tokenEnd: token.end,
        ),
      );
    }

    if (_isChannelToken(rawToken)) {
      final tokenLower = rawToken.toLowerCase();
      final channels =
          _tabs
              .where((tab) => tab.type == ChatTabType.channel)
              .map((tab) => tab.name)
              .where((name) => name.toLowerCase().startsWith(tokenLower))
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      for (final channel in channels) {
        add(channel, ComposerAutocompleteSuggestionType.channel);
        if (suggestions.length >= limit) {
          break;
        }
      }
      return List<ComposerAutocompleteSuggestion>.unmodifiable(suggestions);
    }

    final query = rawToken.startsWith('@') ? rawToken.substring(1) : rawToken;
    if (query.length < 2 || activeTab.type != ChatTabType.channel) {
      return const [];
    }

    final queryLower = query.toLowerCase();
    final users =
        activeChannelUsers
            .where((nick) => nick.toLowerCase().startsWith(queryLower))
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final nick in users) {
      add(nick, ComposerAutocompleteSuggestionType.nick);
      if (suggestions.length >= limit) {
        break;
      }
    }

    return List<ComposerAutocompleteSuggestion>.unmodifiable(suggestions);
  }

  String applyComposerAutocompleteSuggestion(
    String input,
    ComposerAutocompleteSuggestion suggestion,
  ) {
    final prefix = input.substring(0, suggestion.tokenStart);
    final suffix = input.substring(suggestion.tokenEnd);
    final currentToken = input.substring(
      suggestion.tokenStart,
      suggestion.tokenEnd,
    );
    final atPrefix =
        suggestion.type == ComposerAutocompleteSuggestionType.nick &&
        currentToken.startsWith('@');
    final replacement = '${atPrefix ? '@' : ''}${suggestion.text}';
    final needsSpace = suffix.isEmpty || !suffix.startsWith(RegExp(r'\s'));
    return '$prefix$replacement${needsSpace ? ' ' : ''}$suffix';
  }

  static int _suggestionSourceOrder(CommandSuggestionSource source) {
    return switch (source) {
      CommandSuggestionSource.alias => 0,
      CommandSuggestionSource.command => 1,
      CommandSuggestionSource.history => 2,
    };
  }

  ({int start, int end})? _composerTokenAt(String input, {int? cursorOffset}) {
    if (input.isEmpty) {
      return null;
    }
    final offset = (cursorOffset ?? input.length).clamp(0, input.length);
    if (offset == 0) {
      return null;
    }

    var start = offset;
    while (start > 0 && input[start - 1].trim().isNotEmpty) {
      start -= 1;
    }
    var end = offset;
    while (end < input.length && input[end].trim().isNotEmpty) {
      end += 1;
    }

    if (start == end) {
      return null;
    }
    return (start: start, end: end);
  }

  bool _isChannelToken(String token) {
    return token.length >= 2 && _channelPrefixChars.contains(token[0]);
  }

  bool get isReconnectScheduled => _reconnectTimer?.isActive ?? false;
  Duration? get pendingReconnectDelay => _pendingReconnectDelay;
  ChatTab get activeTab => _tabs.firstWhere((tab) => tab.id == _activeTabId);
  String get currentNick => _ircService.currentNick ?? network.nickname;

  /// IRCv3 capabilities negotiated with the server.
  Set<String> get enabledCapabilities => _ircService.enabledCapabilities;

  /// IRCv3 capabilities advertised by the server.
  Set<String> get availableCapabilities => _ircService.availableCapabilities;
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
  List<String> get activeTypingUsers => List<String>.unmodifiable(
    (_typingUsersByTab[activeTabId] ?? const <String>{}).toList()..sort(),
  );
  DccSession? get activeDccSession => _dccSessions[activeTabId];
  List<DccSession> get dccSessions =>
      List<DccSession>.unmodifiable(_dccSessions.values);
  Stream<ForegroundUserNotification> get notifications =>
      _notificationController.stream;
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

  bool get canModerateActiveChannel {
    if (activeTab.type != ChatTabType.channel) {
      return false;
    }
    final ownModes =
        _channelUserModes[activeTab.id]?[currentNick.trim().toLowerCase()] ??
        const <String>{};
    return ownModes.contains('o') ||
        ownModes.contains('a') ||
        ownModes.contains('q');
  }

  bool get canVoiceOrKickActiveChannel {
    if (activeTab.type != ChatTabType.channel) {
      return false;
    }
    final ownModes =
        _channelUserModes[activeTab.id]?[currentNick.trim().toLowerCase()] ??
        const <String>{};
    return canModerateActiveChannel || ownModes.contains('h');
  }

  List<String> get activeChannelUsers {
    final users = _channelUsers[activeTab.id];
    if (users == null) {
      return const [];
    }

    final sorted = users.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return List<String>.unmodifiable(sorted);
  }

  List<ChannelUserDetails> get activeChannelUserDetails {
    return List<ChannelUserDetails>.unmodifiable(
      activeChannelUsers.map((nick) {
        final prefix = _channelUserPrefixFor(activeTabId, nick);
        return (
          nick: nick,
          details: userDetailsForNick(nick),
          prefix: prefix,
          statusRank: channelUserStatusRank(prefix),
        );
      }),
    );
  }

  List<IrcMessage> get activeMessages {
    return messagesForTab(_activeTabId);
  }

  /// Whether persisted scrollback is available (an encrypted history repository
  /// is attached), so the UI can offer a "load earlier messages" affordance.
  bool get hasPersistentHistory => _historyRepository != null;

  /// Selects the next tab (for keyboard navigation), wrapping around.
  void selectNextTab() => _cycleTab(1);

  /// Selects the previous tab, wrapping around.
  void selectPreviousTab() => _cycleTab(-1);

  void _cycleTab(int delta) {
    if (_tabs.length < 2) {
      return;
    }
    final index = _tabs.indexWhere((tab) => tab.id == _activeTabId);
    if (index == -1) {
      return;
    }
    final next = (index + delta) % _tabs.length;
    selectTab(_tabs[next < 0 ? next + _tabs.length : next].id);
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
    final info = userInfoForNick(nick);
    if (info.nick.trim().isEmpty) {
      return '';
    }

    final details = <String>[
      if ((info.account ?? '').isNotEmpty) 'account: ${info.account}',
      if ((info.realName ?? '').isNotEmpty) 'realname: ${info.realName}',
      if (info.userhost.isNotEmpty) info.userhost,
      if ((info.awayMessage ?? '').isNotEmpty)
        info.awayMessage == '__away__' ? 'away' : 'away: ${info.awayMessage}',
      if (_activeTabId.isNotEmpty)
        if ((_channelUserPrefixFor(activeTabId, nick) ?? '').isNotEmpty)
          'mode: ${_channelUserPrefixFor(activeTabId, nick)}',
    ];
    return details.join(' • ');
  }

  IrcUserInfo userInfoForNick(String nick) {
    final trimmed = _stripModePrefix(nick).trim();
    final key = trimmed.toLowerCase();
    if (key.isEmpty) {
      return const IrcUserInfo(nick: '');
    }
    final cached = _userInfoByNick[key] ?? IrcUserInfo(nick: trimmed);
    return IrcUserInfo(
      nick: cached.nick.isEmpty ? trimmed : cached.nick,
      account: _nickAccounts[key],
      realName: _nickRealNames[key],
      ident: _nickIdents[key],
      host: _nickHosts[key],
      awayMessage: _nickAwayMessages[key],
      server: cached.server,
      serverInfo: cached.serverInfo,
      idleSeconds: cached.idleSeconds,
      signedOn: cached.signedOn,
      channels: cached.channels,
      isRegistered: cached.isRegistered,
      isOper: cached.isOper,
      isSecure: cached.isSecure,
      extra: cached.extra,
      fromWhowas: cached.fromWhowas,
    );
  }

  void _rememberFrameSenderState(IrcMessageFrame frame) {
    final nick = frame.senderNick;
    if (nick == null || nick.trim().isEmpty) {
      return;
    }

    final identity = _senderIdentity(frame);
    final accountTag =
        frame.tags['account'] ??
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

  String _messageContextTarget(
    String fallbackTarget,
    Map<String, String?> tags,
  ) {
    final context =
        (tags['draft/channel-context'] ??
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

    final previous = _userInfoByNick[key] ?? IrcUserInfo(nick: nick.trim());
    _userInfoByNick[key] = IrcUserInfo(
      nick: previous.nick.isEmpty ? nick.trim() : previous.nick,
      account: _nickAccounts[key],
      realName: _nickRealNames[key],
      ident: _nickIdents[key],
      host: _nickHosts[key],
      awayMessage: _nickAwayMessages[key],
      server: previous.server,
      serverInfo: previous.serverInfo,
      idleSeconds: previous.idleSeconds,
      signedOn: previous.signedOn,
      channels: previous.channels,
      isRegistered: previous.isRegistered,
      isOper: previous.isOper,
      isSecure: previous.isSecure,
      extra: previous.extra,
      fromWhowas: previous.fromWhowas,
    );
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

  ({String nick, String? ident, String? host, Set<String> modes})
  _parseNamesEntry(String entry) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) {
      return (nick: '', ident: null, host: null, modes: const <String>{});
    }

    var cursor = trimmed;
    final modes = <String>{};
    while (cursor.isNotEmpty && _nickPrefixChars.contains(cursor[0])) {
      final mode = _modeForPrefix(cursor[0]);
      if (mode != null) {
        modes.add(mode);
      }
      cursor = cursor.substring(1);
    }

    final bangIndex = cursor.indexOf('!');
    final atIndex = cursor.indexOf('@');
    if (bangIndex == -1 || atIndex == -1 || bangIndex > atIndex) {
      return (
        nick: _normalizeNickPrefix(trimmed),
        ident: null,
        host: null,
        modes: modes,
      );
    }

    final nick = cursor.substring(0, bangIndex).trim();
    final ident = cursor.substring(bangIndex + 1, atIndex).trim();
    final host = cursor.substring(atIndex + 1).trim();
    return (
      nick: nick,
      ident: ident.isEmpty ? null : ident,
      host: host.isEmpty ? null : host,
      modes: modes,
    );
  }

  String? _modeForPrefix(String prefix) {
    final mapping = _serverSupport.prefixMapping;
    final index = mapping.prefixes.indexOf(prefix);
    if (index == -1 || index >= mapping.modes.length) {
      return null;
    }
    return mapping.modes[index];
  }

  String? _prefixForMode(String mode) {
    if (mode.isEmpty) {
      return null;
    }
    final mapping = _serverSupport.prefixMapping;
    final index = mapping.modes.indexOf(mode[0]);
    if (index == -1 || index >= mapping.prefixes.length) {
      return null;
    }
    return mapping.prefixes[index];
  }

  String? _channelUserPrefixFor(String tabId, String nick) {
    final modes = _channelUserModes[tabId]?[nick.trim().toLowerCase()];
    if (modes == null || modes.isEmpty) {
      return null;
    }
    final mapping = _serverSupport.prefixMapping;
    for (var index = 0; index < mapping.modes.length; index += 1) {
      if (modes.contains(mapping.modes[index])) {
        return index < mapping.prefixes.length ? mapping.prefixes[index] : null;
      }
    }
    return null;
  }

  void _rememberChannelUserModes({
    required String tabId,
    required String nick,
    required Set<String> modes,
  }) {
    if (modes.isEmpty) {
      return;
    }
    final key = nick.trim().toLowerCase();
    if (key.isEmpty) {
      return;
    }
    final users = _channelUserModes.putIfAbsent(
      tabId,
      () => <String, Set<String>>{},
    );
    users.putIfAbsent(key, () => <String>{}).addAll(modes);
  }

  /// All locally managed user-list rules for this session.
  List<UserListEntry> get userListEntries =>
      List<UserListEntry>.unmodifiable(_userListEntries);

  /// Automatic-mode rules (auto-op / auto-halfop / auto-voice) applied when a
  /// matching user joins a channel where we hold the needed privilege.
  List<UserListEntry> get autoModeEntries => List<UserListEntry>.unmodifiable(
    _userListEntries.where((entry) => entry.type.isAutoMode),
  );

  List<UserListEntry> userListEntriesForType(UserListType type) =>
      List<UserListEntry>.unmodifiable(
        _userListEntries.where((entry) => entry.type == type),
      );

  List<UserListEntry> get blacklistEntries =>
      userListEntriesForType(UserListType.blacklist);

  Future<void> _loadAutoModeEntries() async {
    if (_userListEntriesLoaded) {
      return;
    }
    final repository = _userListsRepository;
    if (repository != null) {
      try {
        _userListEntries = await repository.loadAll();
      } catch (_) {
        _userListEntries = const <UserListEntry>[];
      }
    }
    _userListEntriesLoaded = true;
  }

  Future<void> addUserListEntry(UserListEntry entry) async {
    final repository = _userListsRepository;
    if (repository != null) {
      _userListEntries = await repository.add(entry);
    } else {
      _userListEntries = <UserListEntry>[
        ..._userListEntries.where((e) => e.key != entry.key),
        entry,
      ];
    }
    _userListEntriesLoaded = true;
    await _applyUserListSideEffect(entry, add: true);
    notifyListeners();
  }

  Future<void> removeUserListEntry(UserListEntry entry) async {
    final repository = _userListsRepository;
    if (repository != null) {
      _userListEntries = await repository.remove(entry);
    } else {
      _userListEntries = _userListEntries
          .where((e) => e.key != entry.key)
          .toList();
    }
    await _applyUserListSideEffect(entry, add: false);
    notifyListeners();
  }

  Future<void> addAutoModeEntry(UserListEntry entry) {
    assert(entry.type.isAutoMode);
    return addUserListEntry(entry);
  }

  Future<void> removeAutoModeEntry(UserListEntry entry) {
    return removeUserListEntry(entry);
  }

  Future<void> _applyUserListSideEffect(
    UserListEntry entry, {
    required bool add,
  }) async {
    if (entry.type != UserListType.notify) {
      return;
    }
    final nick = _bareNickForMonitor(entry.mask);
    if (nick == null) {
      return;
    }
    await _ircService.sendRaw('MONITOR ${add ? '+' : '-'} $nick');
  }

  String? _bareNickForMonitor(String mask) {
    final trimmed = mask.trim();
    if (trimmed.isEmpty || trimmed.contains('*') || trimmed.contains('?')) {
      return null;
    }
    final nick = trimmed.split('!').first.split('@').first.trim();
    return nick.isEmpty ? null : nick;
  }

  /// When [nick] joins [channel], grants the highest auto-mode we are entitled
  /// to and the user is listed for. No-op for our own joins or when we lack the
  /// needed channel privilege.
  void _maybeApplyAutoModes(
    String channel,
    String nick,
    String tabId, {
    String? ident,
    String? host,
  }) {
    if (autoModeEntries.isEmpty || _isSelfNick(nick)) {
      return;
    }
    final ownModes =
        _channelUserModes[tabId]?[currentNick.trim().toLowerCase()] ??
        const <String>{};
    final hasOp =
        ownModes.contains('o') ||
        ownModes.contains('q') ||
        ownModes.contains('a');
    final hasHalfOp = ownModes.contains('h');
    for (final type in UserListType.autoModeTypes) {
      final matched = autoModeEntries.any(
        (entry) =>
            entry.type == type &&
            entry.matches(
              nick: nick,
              ident: ident,
              host: host,
              channel: channel,
              networkId: network.id,
            ),
      );
      if (!matched) {
        continue;
      }
      final canApply = switch (type) {
        UserListType.autoOp || UserListType.autoHalfOp => hasOp,
        UserListType.autoVoice => hasOp || hasHalfOp,
        _ => false,
      };
      if (canApply) {
        unawaited(
          _ircService.sendRaw('MODE $channel +${type.modeChar!} $nick'),
        );
        return;
      }
    }
  }

  Future<void> start() {
    if (_isDisposed) {
      return Future<void>.value();
    }
    final inFlight = _startInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _startInternal();
    _startInFlight = future;
    future.whenComplete(() {
      if (identical(_startInFlight, future)) {
        _startInFlight = null;
      }
    });
    return future;
  }

  Future<void> _startInternal() async {
    if (!_isBootstrapped) {
      await _commandService.load();
      await _loadPersistedState();
      await _loadAutoModeEntries();
      if (_isDisposed) {
        return;
      }
      _isBootstrapped = true;
      notifyListeners();
    }

    if (_subscriptions.isEmpty) {
      _subscriptions.add(_ircService.frames.listen(_handleFrame));
      _subscriptions.add(
        _ircService.stateStream.listen((snapshot) {
          _connection = snapshot;
          _handleConnectionLifecycle(snapshot);
          notifyListeners();
        }),
      );
      _subscriptions.add(
        _ircService.rawEvents.listen((line) {
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: '*',
            content: line,
            kind: IrcMessageKind.raw,
          );
          unawaited(_persistState());
          notifyListeners();
        }),
      );
      _subscriptions.add(
        _ircService.labeledResponses.listen((event) {
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: '*',
            content:
                'Labeled response matched: ${event.command} [${event.label}]',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
        }),
      );
      _subscriptions.add(
        _dccService.sessions.listen((session) {
          final previous = _dccSessions[session.tabId];
          _dccSessions[session.tabId] = session;
          _appendDccStatusMessage(previous: previous, next: session);
          unawaited(_persistState());
          notifyListeners();
        }),
      );
      _subscriptions.add(
        _dccService.messages.listen((event) {
          _appendMessage(
            tabId: event.tabId,
            sender: event.sender,
            content: event.content,
            isOwn: event.isOwn,
          );
          unawaited(_persistState());
          notifyListeners();
        }),
      );
    }

    _manualDisconnectRequested = false;
    _autoJoinAttempted = false;
    _serviceAuthFallbackAttempted = false;
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
    _channelModes.remove(tabId);
    _channelUserModes.remove(tabId);
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
    _onUserActivity();

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
    _playSound(SoundEvent.send);
    if (!_ircService.enabledCapabilities.contains('echo-message')) {
      _appendMessage(
        tabId: activeTab.id,
        sender: _ircService.currentNick ?? network.nickname,
        content: text,
        tags: {if (normalizedReply.isNotEmpty) 'draft/reply': normalizedReply},
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
      await _dccService.acceptReverseSend(
        session: session,
        onOfferReady: (ctcpOffer) {
          unawaited(
            _ircService.sendRaw('PRIVMSG ${session.peerNick} :$ctcpOffer'),
          );
        },
      );
      final latest = _dccService.sessionForTab(session.tabId);
      if (latest != null) {
        _dccSessions[session.tabId] = latest;
      }
      _appendMessage(
        tabId: session.tabId,
        sender: '*',
        content: 'Reverse DCC SEND accept requested.',
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

  Future<void> sendDccFileToNick({
    required String nick,
    required String filePath,
  }) async {
    final normalizedNick = nick.trim();
    final normalizedPath = filePath.trim();
    if (normalizedNick.isEmpty || normalizedPath.isEmpty) {
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: 'DCC SEND requires a target nick and file path.',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    await _startOutgoingDccSend(nick: normalizedNick, filePath: normalizedPath);
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
    final tab = _ensureDccTab(sessionId: sessionId, name: 'DCC CHAT $nick');
    _activeTabId = tab.id;
    try {
      final session = await _dccService.startOutgoingChat(
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
        kind: IrcMessageKind.dcc,
        attachments: [_dccAttachmentForSession(session)],
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
    final tab = _ensureDccTab(sessionId: sessionId, name: 'DCC SEND $nick');
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
        kind: IrcMessageKind.dcc,
        attachments: [_dccAttachmentForSession(session)],
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
      kind: IrcMessageKind.dcc,
      attachments: [_dccAttachmentForSession(session)],
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
        if (effectiveKinds.isNotEmpty &&
            !effectiveKinds.contains(message.kind)) {
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
    return messages.map(formatIrcMessagePlainText).join('\n');
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
        content:
            'No recent history anchor is available yet for ${activeTab.name}.',
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
        content:
            'No recent history anchor is available yet for ${activeTab.name}.',
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
    _manualDisconnectRequested = false;
    _cancelReconnect();
    await start();
  }

  /// Announces a detected bouncer (ZNC/soju) once registration completes so the
  /// user knows playback/network-management semantics apply. Silent on generic
  /// servers.
  void _announceBouncerCompatibility() {
    final report = detectBouncerCompatibility(
      availableCapabilities: _ircService.availableCapabilities,
      enabledCapabilities: _ircService.enabledCapabilities,
      serverName: network.host,
      networkName: _serverSupport.networkName,
    );
    if (report.family == IrcBouncerFamily.generic) {
      return;
    }
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: 'Bouncer: ${report.summary}',
      kind: IrcMessageKind.system,
    );
  }

  /// Runs a user-list action against [nick] using the existing command paths so
  /// op/kick/ban resolve against the currently active channel and WHOIS/query
  /// behave exactly as their typed slash commands do.
  Future<void> performChannelUserAction(
    String nick,
    ChannelUserAction action,
  ) async {
    final bare = _stripModePrefix(nick).trim();
    if (bare.isEmpty) {
      return;
    }
    switch (action) {
      case ChannelUserAction.whois:
        await handleComposerSubmit('/whois $bare');
      case ChannelUserAction.whowas:
        await handleComposerSubmit('/whowas $bare');
      case ChannelUserAction.query:
        await handleComposerSubmit('/query $bare');
      case ChannelUserAction.op:
        await handleComposerSubmit('/op $bare');
      case ChannelUserAction.deop:
        await handleComposerSubmit('/deop $bare');
      case ChannelUserAction.voice:
        await handleComposerSubmit('/voice $bare');
      case ChannelUserAction.devoice:
        await handleComposerSubmit('/devoice $bare');
      case ChannelUserAction.kick:
        await handleComposerSubmit('/kick $bare');
      case ChannelUserAction.ban:
        await handleComposerSubmit('/ban $bare');
      case ChannelUserAction.kickBan:
        await handleComposerSubmit('/kickban $bare');
      case ChannelUserAction.ignoreToggle:
        if (_ignoreMasks.contains(bare.toLowerCase())) {
          await handleComposerSubmit('/unignore $bare');
        } else {
          await handleComposerSubmit('/ignore $bare');
        }
      case ChannelUserAction.ctcpPing:
        await handleComposerSubmit(
          '/ctcp $bare ping ${DateTime.now().millisecondsSinceEpoch}',
        );
      case ChannelUserAction.ctcpVersion:
        await handleComposerSubmit('/ctcp $bare version');
      case ChannelUserAction.ctcpTime:
        await handleComposerSubmit('/ctcp $bare time');
      case ChannelUserAction.dccChat:
        await handleComposerSubmit('/dccchat $bare');
    }
  }

  String banMaskPreviewForNick(String nick, int banMaskType) {
    final identity = _banIdentityForNickOrMask(nick, banMaskType);
    return identity.mask;
  }

  Future<void> performChannelModerationAction({
    required String nick,
    required ChannelModerationAction action,
    String? reason,
    int banMaskType = 10,
    Duration? timedRemoval,
  }) async {
    if (activeTab.type != ChatTabType.channel) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Moderation actions require an active channel tab.',
        kind: IrcMessageKind.error,
      );
      notifyListeners();
      return;
    }

    final channel = activeTab.name;
    final bare = _stripModePrefix(nick).trim();
    if (bare.isEmpty) {
      return;
    }
    final cleanReason = (reason ?? '').trim();

    switch (action) {
      case ChannelModerationAction.kick:
        await _ircService.sendKick(
          channel: channel,
          nick: bare,
          reason: cleanReason.isEmpty ? null : cleanReason,
        );
      case ChannelModerationAction.ban:
        final mask = _banIdentityForNickOrMask(bare, banMaskType).mask;
        await _ircService.sendChannelMode(
          channel: channel,
          mode: '+b',
          target: mask,
        );
        _scheduleTimedModeRemoval(
          channel: channel,
          mode: 'b',
          mask: mask,
          duration: timedRemoval,
        );
      case ChannelModerationAction.kickBan:
        final mask = _banIdentityForNickOrMask(bare, banMaskType).mask;
        await _ircService.sendChannelMode(
          channel: channel,
          mode: '+b',
          target: mask,
        );
        await _ircService.sendKick(
          channel: channel,
          nick: bare,
          reason: cleanReason.isEmpty ? null : cleanReason,
        );
        _scheduleTimedModeRemoval(
          channel: channel,
          mode: 'b',
          mask: mask,
          duration: timedRemoval,
        );
      case ChannelModerationAction.quiet:
        final mask = _banIdentityForNickOrMask(bare, banMaskType).mask;
        await _ircService.sendChannelMode(
          channel: channel,
          mode: '+q',
          target: mask,
        );
        _scheduleTimedModeRemoval(
          channel: channel,
          mode: 'q',
          mask: mask,
          duration: timedRemoval,
        );
    }
  }

  Future<void> handleNetworkAvailabilityChanged(bool isOnline) async {
    if (_isDisposed || _isNetworkAvailable == isOnline) {
      return;
    }

    _isNetworkAvailable = isOnline;
    if (!isOnline) {
      _cancelReconnect();
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: '*',
        content: 'Network unavailable. IRC reconnect is paused.',
        kind: IrcMessageKind.system,
      );
      if (_isConnectionActiveForNetworkChange(_connection.phase)) {
        await _ircService.disconnect('Network unavailable');
      }
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: 'Network available. Reconnecting IRC session.',
      kind: IrcMessageKind.system,
    );
    _manualDisconnectRequested = false;
    _cancelReconnect();
    unawaited(_persistState());
    await start();
    notifyListeners();
  }

  Future<void> flushState() {
    if (_isDisposed) {
      return Future<void>.value();
    }
    return _persistState();
  }

  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    if (_isDisposed) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        await flushState();
    }
  }

  Future<void> reloadSettings() async {
    _settings = await _settingsRepository.loadSettings();
    _applySettingsToServices();
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

    final success = await _ircService.redactMessage(
      target: target,
      msgid: msgid,
    );
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
        tags: {...existing.tags, 'redacted': 'true'},
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
    if (_isDisposed) {
      return;
    }

    if (snapshot.phase == ConnectionPhase.connecting) {
      _serverSupport = const IrcServerSupport.empty();
      _nickPrefixChars = IrcServerSupport.defaultPrefixMapping.prefixes;
      _channelPrefixChars = IrcServerSupport.defaultChannelTypes;
      _serviceAuthFallbackAttempted = false;
    }

    if (snapshot.phase == ConnectionPhase.connected) {
      if (_lastSoundedPhase != ConnectionPhase.connected) {
        _lastSoundedPhase = ConnectionPhase.connected;
        _playSound(SoundEvent.login);
      }
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
      // Only beep on the drop from an established connection, not on every
      // failed reconnect attempt.
      if (_lastSoundedPhase == ConnectionPhase.connected) {
        _lastSoundedPhase = snapshot.phase;
        _playSound(SoundEvent.disconnect);
      }
      _autoHistoryRequestedChannels.clear();
      _autoJoinAttempted = false;
      _serviceAuthFallbackAttempted = false;
      _scheduleReconnect();
    }
  }

  /// Fire-and-forget event sound; failures never affect message handling.
  void _playSound(SoundEvent event) {
    final service = _soundService;
    if (service == null) {
      return;
    }
    unawaited(service.playEvent(event));
  }

  Future<void> _runPostRegistrationActions() async {
    await _sendServiceAuthFallbackIfNeeded();
    await _autoJoinConfiguredChannels();
  }

  Future<void> _sendServiceAuthFallbackIfNeeded() async {
    if (_serviceAuthFallbackAttempted ||
        network.serviceAuthFallback == ServiceAuthFallback.disabled ||
        _connection.phase != ConnectionPhase.connected) {
      return;
    }

    if (!_shouldSendServiceAuthFallback()) {
      return;
    }

    final password = (network.saslPassword ?? '').trim();
    if (password.isEmpty) {
      return;
    }

    _serviceAuthFallbackAttempted = true;
    final identify = buildNickServIdentifyCommand(
      account: network.saslAccount,
      password: password,
      target: network.serviceAuthTarget,
    );
    await _ircService.sendRaw(
      'PRIVMSG ${identify.target} :${identify.command}',
      redactedLine: 'PRIVMSG ${identify.target} :${identify.redactedCommand}',
    );
    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content:
          'Sent ${identify.target} fallback identify because SASL ${_saslStatusDescription(_ircService.saslAuthStatus)}.',
      kind: IrcMessageKind.system,
    );
    unawaited(_persistState());
    notifyListeners();
  }

  bool _shouldSendServiceAuthFallback() {
    if (!_ircService.saslConfigured || _ircService.saslSucceeded) {
      return false;
    }

    return switch (_ircService.saslAuthStatus) {
      SaslAuthStatus.pending ||
      SaslAuthStatus.unavailable ||
      SaslAuthStatus.mechanismUnavailable ||
      SaslAuthStatus.requested ||
      SaslAuthStatus.failed ||
      SaslAuthStatus.aborted => true,
      SaslAuthStatus.idle ||
      SaslAuthStatus.notConfigured ||
      SaslAuthStatus.authenticating ||
      SaslAuthStatus.succeeded => false,
    };
  }

  String _saslStatusDescription(SaslAuthStatus status) {
    return switch (status) {
      SaslAuthStatus.pending => 'did not complete before registration',
      SaslAuthStatus.unavailable => 'is not advertised',
      SaslAuthStatus.mechanismUnavailable => 'mechanism is unavailable',
      SaslAuthStatus.requested =>
        'request did not complete before registration',
      SaslAuthStatus.failed => 'failed',
      SaslAuthStatus.aborted => 'was aborted',
      _ => 'is unavailable',
    };
  }

  Future<void> _autoJoinConfiguredChannels() async {
    if (_autoJoinAttempted || _connection.phase != ConnectionPhase.connected) {
      return;
    }

    final channels = _normalizedAutoJoinChannels();
    if (channels.isEmpty) {
      _autoJoinAttempted = true;
      return;
    }

    _autoJoinAttempted = true;
    for (final channel in channels) {
      if (_isDisposed || _connection.phase != ConnectionPhase.connected) {
        return;
      }
      final tab = _ensureChannelTab(channel);
      _messages.putIfAbsent(tab.id, () => <IrcMessage>[]);
      await _ircService.joinChannel(
        channel,
        network.autoJoinChannelKeys[channel],
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  List<String> _normalizedAutoJoinChannels() {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in network.autoJoinChannels) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final channel = _isChannelName(trimmed) ? trimmed : '#$trimmed';
      final key = channel.toLowerCase();
      if (seen.add(key)) {
        result.add(channel);
      }
    }
    return result;
  }

  void _scheduleReconnect() {
    if (_isDisposed || _manualDisconnectRequested || !_isNetworkAvailable) {
      return;
    }

    if (_reconnectTimer?.isActive ?? false) {
      return;
    }

    if (_maxReconnectAttempts > 0 &&
        _reconnectAttempt >= _maxReconnectAttempts) {
      _pendingReconnectDelay = null;
      return;
    }

    _reconnectAttempt += 1;
    _pendingReconnectDelay = _nextReconnectDelay();
    _connection = ConnectionSnapshot(
      networkId: network.id,
      phase: ConnectionPhase.reconnecting,
      message:
          'Reconnecting in ${_formatReconnectDelay(_pendingReconnectDelay!)}.',
    );
    _reconnectTimer = Timer(_pendingReconnectDelay!, () {
      _reconnectTimer = null;
      _pendingReconnectDelay = null;
      if (_isDisposed || _manualDisconnectRequested) {
        return;
      }
      unawaited(start());
      if (!_isDisposed) {
        notifyListeners();
      }
    });
  }

  bool _isConnectionActiveForNetworkChange(ConnectionPhase phase) {
    return switch (phase) {
      ConnectionPhase.connecting ||
      ConnectionPhase.registering ||
      ConnectionPhase.authenticating ||
      ConnectionPhase.connected ||
      ConnectionPhase.reconnecting => true,
      ConnectionPhase.idle ||
      ConnectionPhase.disconnecting ||
      ConnectionPhase.disconnected ||
      ConnectionPhase.error => false,
    };
  }

  Duration _nextReconnectDelay() {
    final baseMillis = math.max(0, _reconnectBaseDelay.inMilliseconds);
    final maxMillis = math.max(baseMillis, _reconnectMaxDelay.inMilliseconds);
    final multiplier = 1 << (_reconnectAttempt - 1).clamp(0, 30);
    final boundedMillis = (baseMillis * multiplier).clamp(
      baseMillis,
      maxMillis,
    );

    if (_reconnectJitterFactor <= 0 || boundedMillis <= 0) {
      return Duration(milliseconds: boundedMillis.toInt());
    }

    final jitterMillis = (boundedMillis * _reconnectJitterFactor).round();
    if (jitterMillis <= 0) {
      return Duration(milliseconds: boundedMillis.toInt());
    }

    final minMillis = math.max(baseMillis, boundedMillis - jitterMillis);
    final jitteredMaxMillis = math.min(maxMillis, boundedMillis + jitterMillis);
    final jitterRangeMillis = jitteredMaxMillis - minMillis;
    if (jitterRangeMillis <= 0) {
      return Duration(milliseconds: minMillis.toInt());
    }

    final sample = _reconnectJitterSampler().clamp(0.0, 1.0).toDouble();
    final jitteredMillis = minMillis + (jitterRangeMillis * sample).round();
    return Duration(milliseconds: jitteredMillis.toInt());
  }

  String _formatReconnectDelay(Duration delay) {
    if (delay.inSeconds > 0) {
      return '${delay.inSeconds}s';
    }
    return '${delay.inMilliseconds}ms';
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pendingReconnectDelay = null;
  }

  /// Called on user activity (sending). Returns from an auto-away state and
  /// restarts the idle countdown.
  void _onUserActivity() {
    if (_autoAwayActive) {
      _autoAwayActive = false;
      unawaited(_ircService.sendRaw('AWAY'));
    }
    _scheduleAutoAway();
  }

  void _scheduleAutoAway() {
    _autoAwayTimer?.cancel();
    if (!_settings.autoAwayEnabled) {
      return;
    }
    final minutes = _settings.autoAwayMinutes.clamp(1, 240);
    _autoAwayTimer = Timer(Duration(minutes: minutes), () {
      if (_settings.autoAwayEnabled &&
          _connection.phase == ConnectionPhase.connected &&
          !_autoAwayActive) {
        _autoAwayActive = true;
        final message = _settings.awayMessage.trim().isEmpty
            ? 'Away'
            : _settings.awayMessage.trim();
        unawaited(_ircService.sendRaw('AWAY :$message'));
      }
    });
  }

  final List<String> _ignoreMasks = <String>[];
  final List<String> _messageFilters = <String>[];
  final Map<String, Timer> _commandTimers = <String, Timer>{};
  final List<ChannelListEntry> _channelListing = <ChannelListEntry>[];
  bool _channelListInProgress = false;
  Timer? _autoAwayTimer;
  bool _autoAwayActive = false;
  Timer? _lagTimer;
  Duration? _lag;

  /// Round-trip lag to the server from the most recent PING/PONG, or null.
  Duration? get lag => _lag;

  /// Sends a timestamped PING so the next PONG can measure lag.
  Future<void> measureLag() async {
    if (_connection.phase != ConnectionPhase.connected) {
      return;
    }
    await _ircService.sendRaw(
      'PING :LAG${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  void _scheduleLagMeasurement() {
    _lagTimer?.cancel();
    _lagTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(measureLag()),
    );
    unawaited(measureLag());
  }

  /// Channels collected from the most recent server LIST (numeric 322).
  List<ChannelListEntry> get channelListing =>
      List<ChannelListEntry>.unmodifiable(_channelListing);

  /// Whether a LIST response is currently streaming in.
  bool get channelListInProgress => _channelListInProgress;

  /// The ignore masks currently active for this session.
  List<String> get ignoreMasks => List<String>.unmodifiable(_ignoreMasks);

  /// Requests the server channel list (LIST).
  Future<void> requestChannelList() async {
    _channelListing.clear();
    _channelListInProgress = true;
    notifyListeners();
    await _ircService.sendRaw('LIST');
  }

  /// Adds an ignore mask programmatically (used by the ignore manager UI).
  void addIgnoreMask(String mask) => _handleIgnoreCommand(mask);

  /// Removes an ignore mask programmatically.
  void removeIgnoreMask(String mask) => _handleUnignoreCommand(mask);

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
      case 'action':
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
            await sendDccFileToNick(nick: nick, filePath: filePath);
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
        await _ircService.sendWho(
          rest.isEmpty && activeTab.type == ChatTabType.channel
              ? activeTab.name
              : rest,
        );
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
          content: rest.isEmpty
              ? 'Requested channel list.'
              : 'Requested channel list for: $rest',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'chathistory':
        final request = _parseChatHistoryRequest(rest);
        final isTargetsRequest = request.subcommand == 'TARGETS';
        if (request.reference.isEmpty ||
            (request.subcommand == 'BETWEEN' &&
                (request.endReference ?? '').isEmpty) ||
            (isTargetsRequest && (request.endReference ?? '').isEmpty)) {
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: 'error',
            content:
                'Usage: /chathistory [latest|before|after|around|between|targets] ...',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
        if (activeTab.type == ChatTabType.server && !isTargetsRequest) {
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: 'error',
            content:
                'Usage: open a channel or query tab, then use /chathistory [limit]',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
        final success = await _ircService.sendChatHistory(
          target: isTargetsRequest ? '*' : activeTab.name,
          subcommand: request.subcommand,
          reference: request.reference,
          endReference: request.endReference,
          limit: request.limit,
        );
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: success ? '*' : 'error',
          content: success
              ? _formatChatHistoryRequestMessage(request)
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
          content: rest.isEmpty
              ? 'Requested server time.'
              : 'Requested time for: $rest',
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
          content: rest.isEmpty
              ? 'Requested server version.'
              : 'Requested version for: $rest',
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
          content: rest.isEmpty
              ? 'Requested server links.'
              : 'Requested links for: $rest',
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'ison':
        final nicks = rest
            .split(RegExp(r'\s+'))
            .where((nick) => nick.trim().isNotEmpty)
            .toList(growable: false);
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
        final nicks = rest
            .split(RegExp(r'\s+'))
            .where((nick) => nick.trim().isNotEmpty)
            .toList(growable: false);
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
      case 'kickban':
        if (rest.isNotEmpty && activeTab.type == ChatTabType.channel) {
          final parts = rest.split(' ');
          final nick = parts.first;
          final reason = parts.length > 1 ? parts.skip(1).join(' ') : null;
          final mask = _banMaskForNickOrMask(nick);
          await _ircService.sendChannelMode(
            channel: activeTab.name,
            mode: '+b',
            target: mask,
          );
          await _ircService.sendKick(
            channel: activeTab.name,
            nick: nick,
            reason: reason,
          );
          return;
        }
      case 'topic':
        if (activeTab.type == ChatTabType.channel) {
          await _ircService.sendTopic(
            channel: activeTab.name,
            topic: rest.isEmpty ? null : rest,
          );
          return;
        }
      case 'mode':
        if (rest.isNotEmpty) {
          final args = activeTab.type == ChatTabType.channel
              ? '${activeTab.name} $rest'
              : rest;
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
      case 'lusers':
      case 'admin':
      case 'info':
      case 'stats':
      case 'ping':
      case 'trace':
      case 'rules':
      case 'servlist':
      case 'userip':
      case 'users':
      case 'watch':
      case 'knock':
      case 'squery':
      case 'cnotice':
      case 'cprivmsg':
      case 'oper':
      case 'rehash':
      case 'squit':
      case 'kill':
      case 'connect':
      case 'die':
      case 'wallops':
      case 'locops':
      case 'globops':
      case 'adchat':
        await _sendRegisteredRawSlashCommand(commandLine);
        return;
      case 'clear':
        _messages[activeTab.id] = [];
        if (activeTab.type == ChatTabType.channel) {
          _channelUsers.putIfAbsent(activeTab.id, () => <String>{});
        }
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'close':
        if (activeTab.type == ChatTabType.server) {
          _appendMessage(
            tabId: _serverTabId(network.id),
            sender: 'error',
            content: 'The server tab cannot be closed.',
            kind: IrcMessageKind.system,
          );
          unawaited(_persistState());
          notifyListeners();
          return;
        }
        closeTab(activeTab.id);
        return;
      case 'echo':
        _appendMessage(
          tabId: activeTab.id,
          sender: rest.isEmpty ? 'error' : '*',
          content: rest.isEmpty ? 'Usage: /echo <message>' : rest,
          kind: IrcMessageKind.system,
        );
        unawaited(_persistState());
        notifyListeners();
        return;
      case 'help':
        _handleHelpCommand(rest);
        return;
      case 'ignore':
        _handleIgnoreCommand(rest);
        return;
      case 'unignore':
        _handleUnignoreCommand(rest);
        return;
      case 'amsg':
        await _handleAllChannelsMessage(rest, asAction: false);
        return;
      case 'ame':
        await _handleAllChannelsMessage(rest, asAction: true);
        return;
      case 'dns':
        await _handleDnsCommand(rest);
        return;
      case 'clones':
      case 'detectclones':
      case 'clonesdetect':
        _handleClonesCommand(rest);
        return;
      case 'reconnect':
        _appendMessage(
          tabId: activeTab.id,
          sender: '*',
          content: 'Reconnecting to ${network.name}…',
          kind: IrcMessageKind.system,
        );
        notifyListeners();
        await reconnectNow();
        return;
      case 'filter':
        _handleFilterCommand(rest);
        return;
      case 'unfilter':
        _handleUnfilterCommand(rest);
        return;
      case 'window':
        await _handleWindowCommand(rest);
        return;
      case 'timer':
        _handleTimerCommand(rest);
        return;
      case 'quit':
      case 'disconnect':
        await _ircService.disconnect(rest.isEmpty ? null : rest);
        return;
      case 'autovoice':
        await _handleAutoModeCommand(
          UserListType.autoVoice,
          rest,
          remove: false,
        );
        return;
      case 'unautovoice':
        await _handleAutoModeCommand(
          UserListType.autoVoice,
          rest,
          remove: true,
        );
        return;
      case 'autoop':
        await _handleAutoModeCommand(UserListType.autoOp, rest, remove: false);
        return;
      case 'unautoop':
        await _handleAutoModeCommand(UserListType.autoOp, rest, remove: true);
        return;
      case 'autohalfop':
        await _handleAutoModeCommand(
          UserListType.autoHalfOp,
          rest,
          remove: false,
        );
        return;
      case 'unautohalfop':
        await _handleAutoModeCommand(
          UserListType.autoHalfOp,
          rest,
          remove: true,
        );
        return;
      case 'autolist':
      case 'autolists':
        _handleAutoListCommand();
        return;
      case 'notify':
        await _handleUserListCommand(UserListType.notify, rest, remove: false);
        return;
      case 'unnotify':
        await _handleUserListCommand(UserListType.notify, rest, remove: true);
        return;
      case 'protect':
        await _handleUserListCommand(
          UserListType.protectedUser,
          rest,
          remove: false,
        );
        return;
      case 'unprotect':
        await _handleUserListCommand(
          UserListType.protectedUser,
          rest,
          remove: true,
        );
        return;
      case 'otherlist':
        await _handleUserListCommand(UserListType.other, rest, remove: false);
        return;
      case 'unotherlist':
        await _handleUserListCommand(UserListType.other, rest, remove: true);
        return;
      case 'blacklist':
        await _handleBlacklistCommand(rest, remove: false);
        return;
      case 'unblacklist':
        await _handleBlacklistCommand(rest, remove: true);
        return;
      case 'userlist':
      case 'userlists':
        _handleUserListReport(rest);
        return;
      default:
        await _ircService.sendRaw(commandLine);
        return;
    }
  }

  Future<void> _handleAutoModeCommand(
    UserListType type,
    String rest, {
    required bool remove,
  }) async {
    final tokens = rest
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content:
            'Usage: /${remove ? 'un' : ''}${type.id} <nick|mask> [#chan,#chan]',
        kind: IrcMessageKind.error,
      );
      return;
    }
    final mask = tokens.first;
    final channels = tokens.length > 1
        ? tokens[1]
              .split(',')
              .map((c) => c.trim())
              .where((c) => c.isNotEmpty)
              .toList()
        : const <String>[];

    if (remove) {
      final normalized = UserListEntry(
        type: type,
        mask: mask,
      ).normalizedMask.toLowerCase();
      final matches = autoModeEntries
          .where(
            (entry) =>
                entry.type == type &&
                entry.normalizedMask.toLowerCase() == normalized &&
                (entry.network == null || entry.network == network.id),
          )
          .toList();
      for (final match in matches) {
        await removeAutoModeEntry(match);
      }
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: matches.isEmpty
            ? '$mask was not on ${type.label}.'
            : 'Removed $mask from ${type.label}.',
        kind: IrcMessageKind.system,
      );
      return;
    }

    await addAutoModeEntry(
      UserListEntry(
        type: type,
        mask: mask,
        channels: channels,
        network: network.id,
      ),
    );
    _appendMessage(
      tabId: activeTab.id,
      sender: '*',
      content: channels.isEmpty
          ? 'Added $mask to ${type.label}.'
          : 'Added $mask to ${type.label} (${channels.join(', ')}).',
      kind: IrcMessageKind.system,
    );
  }

  void _handleAutoListCommand() {
    if (autoModeEntries.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: 'No auto-mode rules configured.',
        kind: IrcMessageKind.system,
      );
      return;
    }
    for (final entry in autoModeEntries) {
      final scope = entry.channels.isEmpty
          ? 'all channels'
          : entry.channels.join(', ');
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: '${entry.type.label}: ${entry.mask} · $scope',
        kind: IrcMessageKind.system,
      );
    }
  }

  Future<void> _handleUserListCommand(
    UserListType type,
    String rest, {
    required bool remove,
  }) async {
    final tokens = rest
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    final mask = tokens.isEmpty ? '' : tokens.first;
    if (mask.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Usage: /${remove ? 'un' : ''}${type.id} <nick|mask>',
        kind: IrcMessageKind.error,
      );
      notifyListeners();
      return;
    }

    if (remove) {
      final normalized = UserListEntry(
        type: type,
        mask: mask,
      ).normalizedMask.toLowerCase();
      final matches = userListEntriesForType(type)
          .where(
            (entry) =>
                entry.normalizedMask.toLowerCase() == normalized &&
                (entry.network == null || entry.network == network.id),
          )
          .toList();
      for (final entry in matches) {
        await removeUserListEntry(entry);
      }
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: matches.isEmpty
            ? '$mask was not on ${type.label}.'
            : 'Removed $mask from ${type.label}.',
        kind: IrcMessageKind.system,
      );
      return;
    }

    await addUserListEntry(
      UserListEntry(type: type, mask: mask, network: network.id),
    );
    _appendMessage(
      tabId: activeTab.id,
      sender: '*',
      content: 'Added $mask to ${type.label}.',
      kind: IrcMessageKind.system,
    );
  }

  Future<void> _handleBlacklistCommand(
    String rest, {
    required bool remove,
  }) async {
    final tokens = rest
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: remove ? 'error' : '*',
        content: remove
            ? 'Usage: /unblacklist <nick|mask>'
            : _formatUserListReport(UserListType.blacklist),
        kind: remove ? IrcMessageKind.error : IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }
    final mask = tokens.first;
    if (remove) {
      await _handleUserListCommand(UserListType.blacklist, mask, remove: true);
      return;
    }

    final maybeAction = tokens.length > 1
        ? BlacklistAction.fromId(tokens[1].toLowerCase())
        : null;
    final reasonStart = maybeAction == null ? 1 : 2;
    final reason = tokens.length > reasonStart
        ? tokens.skip(reasonStart).join(' ')
        : null;
    await addUserListEntry(
      UserListEntry(
        type: UserListType.blacklist,
        mask: mask,
        network: network.id,
        blacklistAction: maybeAction ?? BlacklistAction.ignore,
        reason: reason,
      ),
    );
    _appendMessage(
      tabId: activeTab.id,
      sender: '*',
      content:
          'Added $mask to Blacklist (${(maybeAction ?? BlacklistAction.ignore).label}).',
      kind: IrcMessageKind.system,
    );
  }

  void _handleUserListReport(String rest) {
    final requested = rest.trim();
    if (requested.isNotEmpty) {
      final type = UserListType.fromId(requested);
      _appendMessage(
        tabId: activeTab.id,
        sender: type == null ? 'error' : '*',
        content: type == null
            ? 'Unknown user list: $requested'
            : _formatUserListReport(type),
        kind: type == null ? IrcMessageKind.error : IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    for (final type in UserListType.managementTypes) {
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: _formatUserListReport(type),
        kind: IrcMessageKind.system,
      );
    }
    notifyListeners();
  }

  String _formatUserListReport(UserListType type) {
    final entries = userListEntriesForType(type);
    if (entries.isEmpty) {
      return '${type.label}: empty';
    }
    return '${type.label}: ${entries.map((entry) => entry.mask).join(', ')}';
  }

  void _handleHelpCommand(String rest) {
    final requested = rest.trim();
    if (requested.isNotEmpty) {
      final name = requested.split(RegExp(r'\s+')).first.toLowerCase();
      final command = _commandService.getCommand(name);
      _appendMessage(
        tabId: activeTab.id,
        sender: command == null ? 'error' : '*',
        content: command == null
            ? 'No help available for /$name'
            : 'Help /${command.name}: ${command.usage} — ${command.description}',
        kind: IrcMessageKind.system,
      );
    } else {
      final names = _commandService.commands
          .map((command) => '/${command.name}')
          .join(' ');
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: 'Commands: $names',
        kind: IrcMessageKind.system,
      );
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: 'Use /help <command> for details.',
        kind: IrcMessageKind.system,
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  void _handleIgnoreCommand(String rest) {
    final mask = rest.trim();
    if (mask.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: _ignoreMasks.isEmpty
            ? 'Ignore list is empty.'
            : 'Ignoring: ${_ignoreMasks.join(', ')}',
        kind: IrcMessageKind.system,
      );
    } else {
      final normalized = mask.toLowerCase();
      final alreadyIgnored = _ignoreMasks.contains(normalized);
      if (!alreadyIgnored) {
        _ignoreMasks.add(normalized);
      }
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: alreadyIgnored
            ? 'Already ignoring $mask'
            : 'Now ignoring $mask',
        kind: IrcMessageKind.system,
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  void _handleUnignoreCommand(String rest) {
    final mask = rest.trim();
    if (mask.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Usage: /unignore <mask>',
        kind: IrcMessageKind.system,
      );
    } else {
      final removed = _ignoreMasks.remove(mask.toLowerCase());
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: removed ? 'No longer ignoring $mask' : 'Not ignoring $mask',
        kind: IrcMessageKind.system,
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _handleAllChannelsMessage(
    String rest, {
    required bool asAction,
  }) async {
    final text = rest.trim();
    if (text.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: asAction ? 'Usage: /ame <action>' : 'Usage: /amsg <message>',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    final channelTabs = tabs
        .where((tab) => tab.type == ChatTabType.channel)
        .toList(growable: false);
    if (channelTabs.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'No channels joined for this network.',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    final echoEnabled = _ircService.enabledCapabilities.contains(
      'echo-message',
    );
    for (final tab in channelTabs) {
      if (asAction) {
        await _ircService.sendAction(target: tab.name, text: text);
      } else {
        await _ircService.sendPrivmsg(target: tab.name, text: text);
      }
      if (!echoEnabled) {
        _appendMessage(
          tabId: tab.id,
          sender: _ircService.currentNick ?? network.nickname,
          content: asAction ? '• $text' : text,
          isOwn: true,
        );
      }
    }
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _handleDnsCommand(String rest) async {
    final nick = rest.trim().isEmpty
        ? ''
        : rest.trim().split(RegExp(r'\s+')).first;
    if (nick.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Usage: /dns <nick>',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    final host = _nickHosts[nick.toLowerCase()];
    if (host != null && host.isNotEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: '$nick resolves to $host',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    _appendMessage(
      tabId: activeTab.id,
      sender: '*',
      content: 'Looking up host for $nick…',
      kind: IrcMessageKind.system,
    );
    notifyListeners();
    await _ircService.sendRaw('USERHOST $nick');
  }

  void _handleClonesCommand(String rest) {
    final requested = rest.trim().isEmpty
        ? (activeTab.type == ChatTabType.channel ? activeTab.name : null)
        : rest.trim().split(RegExp(r'\s+')).first;
    if (requested == null || !_isChannelName(requested)) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Usage: /clones <channel>',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    ChatTab? channelTab;
    for (final tab in tabs) {
      if (tab.type == ChatTabType.channel &&
          tab.name.toLowerCase() == requested.toLowerCase()) {
        channelTab = tab;
        break;
      }
    }
    final users = channelTab == null ? null : _channelUsers[channelTab.id];
    if (users == null || users.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: 'No known users to scan in $requested',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    final byHost = <String, List<String>>{};
    for (final entry in users) {
      final bare = _stripModePrefix(entry);
      final host = _nickHosts[bare.toLowerCase()];
      if (host == null || host.isEmpty) {
        continue;
      }
      byHost.putIfAbsent(host, () => <String>[]).add(bare);
    }
    final clones =
        byHost.entries.where((entry) => entry.value.length > 1).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    if (clones.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: 'No clones detected in $requested',
        kind: IrcMessageKind.system,
      );
    } else {
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: 'Clones detected in $requested:',
        kind: IrcMessageKind.system,
      );
      for (final entry in clones) {
        _appendMessage(
          tabId: activeTab.id,
          sender: '*',
          content: '  ${entry.key}: ${(entry.value..sort()).join(', ')}',
          kind: IrcMessageKind.system,
        );
      }
    }
    unawaited(_persistState());
    notifyListeners();
  }

  static String _stripModePrefix(String nick) {
    const prefixes = '@+%~&';
    var index = 0;
    while (index < nick.length && prefixes.contains(nick[index])) {
      index++;
    }
    return nick.substring(index);
  }

  /// Whether an incoming frame comes from a sender matched by the ignore list.
  ///
  /// Masks may be nick-only (matched against the sender nick) or full
  /// `nick!user@host` globs with `*`/`?` wildcards. Self-echo is never ignored.
  bool _shouldIgnoreSender(IrcMessageFrame frame) {
    if (_ignoreMasks.isEmpty || _isSelfEcho(frame.senderNick)) {
      return false;
    }
    for (final mask in _ignoreMasks) {
      if (_matchesIgnoreMask(
        mask,
        prefix: frame.prefix,
        nick: frame.senderNick,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _enforceBlacklist(IrcMessageFrame frame, String target) {
    if (blacklistEntries.isEmpty || _isSelfEcho(frame.senderNick)) {
      return false;
    }
    final parsedPrefix = _parseHostmask(frame.prefix ?? '');
    final nick = frame.senderNick ?? parsedPrefix?.nick;
    if (nick == null || nick.trim().isEmpty) {
      return false;
    }
    final identity = _senderIdentity(frame);
    final ident = identity.ident ?? parsedPrefix?.ident;
    final host = identity.host ?? parsedPrefix?.host;
    final channel = _isChannelName(target) ? target : '';

    for (final entry in blacklistEntries) {
      if (!entry.matches(
        nick: nick,
        ident: ident,
        host: host,
        channel: channel,
        networkId: network.id,
      )) {
        continue;
      }
      _runBlacklistAction(
        entry: entry,
        nick: nick,
        userhost: '${ident ?? '*'}@${host ?? '*'}',
        hostmask: frame.prefix ?? '$nick!${ident ?? '*'}@${host ?? '*'}',
        channel: channel,
      );
      return true;
    }
    return false;
  }

  void _runBlacklistAction({
    required UserListEntry entry,
    required String nick,
    required String userhost,
    required String hostmask,
    required String channel,
  }) {
    final action = entry.effectiveBlacklistAction;
    final key = '${entry.key}|$channel|${nick.toLowerCase()}|${action.id}';
    final firstHit = _blacklistEnforcements.add(key);
    if (!firstHit) {
      return;
    }

    final targetTabId = channel.isEmpty
        ? _serverTabId(network.id)
        : _ensureChannelTab(channel).id;
    final reason = (entry.reason ?? 'Blacklisted').trim();
    final mask = entry.normalizedMask;

    switch (action) {
      case BlacklistAction.ignore:
        break;
      case BlacklistAction.ban:
        if (channel.isNotEmpty) {
          unawaited(
            _ircService.sendChannelMode(
              channel: channel,
              mode: '+b',
              target: mask,
            ),
          );
          _scheduleTimedModeRemoval(
            channel: channel,
            mode: 'b',
            mask: mask,
            duration: entry.duration,
          );
        }
      case BlacklistAction.kickBan:
        if (channel.isNotEmpty) {
          unawaited(
            _ircService.sendChannelMode(
              channel: channel,
              mode: '+b',
              target: mask,
            ),
          );
          unawaited(
            _ircService.sendKick(channel: channel, nick: nick, reason: reason),
          );
          _scheduleTimedModeRemoval(
            channel: channel,
            mode: 'b',
            mask: mask,
            duration: entry.duration,
          );
        }
      case BlacklistAction.quiet:
        if (channel.isNotEmpty) {
          unawaited(
            _ircService.sendChannelMode(
              channel: channel,
              mode: '+q',
              target: mask,
            ),
          );
          _scheduleTimedModeRemoval(
            channel: channel,
            mode: 'q',
            mask: mask,
            duration: entry.duration,
          );
        }
      case BlacklistAction.custom:
        final raw = _formatBlacklistRawTemplate(
          entry.customRaw,
          nick: nick,
          userhost: userhost,
          hostmask: hostmask,
          mask: mask,
          channel: channel,
          reason: reason,
          duration: entry.duration,
        );
        if (raw != null) {
          unawaited(_ircService.sendRaw(raw));
        }
    }

    _appendMessage(
      tabId: targetTabId,
      sender: '*',
      content:
          'Blacklist ${action.label.toLowerCase()} matched $nick ($mask)${reason.isEmpty ? '' : ': $reason'}',
      kind: IrcMessageKind.system,
    );
  }

  String? _formatBlacklistRawTemplate(
    String? template, {
    required String nick,
    required String userhost,
    required String hostmask,
    required String mask,
    required String channel,
    required String reason,
    Duration? duration,
  }) {
    var raw = (template ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    final replacements = <String, String>{
      '{nick}': nick,
      '{user}': userhost.split('@').first,
      '{host}': userhost.contains('@') ? userhost.split('@').last : '',
      '{userhost}': userhost,
      '{hostmask}': hostmask,
      '{mask}': mask,
      '{usermask}': mask,
      '{channel}': channel,
      '{reason}': reason,
      '{duration}': duration == null ? '' : '${duration.inMinutes}m',
    };
    for (final entry in replacements.entries) {
      raw = raw.replaceAll(entry.key, entry.value);
    }
    return raw;
  }

  static bool _matchesIgnoreMask(String mask, {String? prefix, String? nick}) {
    final hasHostMask = mask.contains('!') || mask.contains('@');
    final target = hasHostMask ? (prefix ?? nick) : (nick ?? prefix);
    if (target == null || target.isEmpty) {
      return false;
    }
    return _globToRegExp(mask).hasMatch(target);
  }

  static RegExp _globToRegExp(String glob) {
    final buffer = StringBuffer('^');
    for (final rune in glob.runes) {
      final char = String.fromCharCode(rune);
      if (char == '*') {
        buffer.write('.*');
      } else if (char == '?') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }

  void _handleFilterCommand(String rest) {
    final trimmed = rest.trim();
    // `-g` (global) is accepted for RN parity; filtering here is per-session.
    final text = trimmed.startsWith('-g')
        ? trimmed.substring(2).trim()
        : trimmed;
    if (text.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: _messageFilters.isEmpty
            ? 'No message filters set.'
            : 'Filtering: ${_messageFilters.join(', ')}',
        kind: IrcMessageKind.system,
      );
    } else {
      final normalized = text.toLowerCase();
      final already = _messageFilters.contains(normalized);
      if (!already) {
        _messageFilters.add(normalized);
      }
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: already
            ? 'Already filtering "$text"'
            : 'Now filtering messages containing "$text"',
        kind: IrcMessageKind.system,
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  void _handleUnfilterCommand(String rest) {
    final text = rest.trim();
    if (text.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Usage: /unfilter <text>',
        kind: IrcMessageKind.system,
      );
    } else {
      final removed = _messageFilters.remove(text.toLowerCase());
      _appendMessage(
        tabId: activeTab.id,
        sender: '*',
        content: removed
            ? 'No longer filtering "$text"'
            : 'Not filtering "$text"',
        kind: IrcMessageKind.system,
      );
    }
    unawaited(_persistState());
    notifyListeners();
  }

  Future<void> _handleWindowCommand(String rest) async {
    final parts = rest
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Usage: /window [-a] <name>',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    if (parts.first == '-a') {
      if (parts.length < 2) {
        _appendMessage(
          tabId: activeTab.id,
          sender: 'error',
          content: 'Usage: /window -a <name>',
          kind: IrcMessageKind.system,
        );
        notifyListeners();
        return;
      }
      final name = parts[1];
      ChatTab? match;
      for (final tab in tabs) {
        if (tab.name.toLowerCase() == name.toLowerCase()) {
          match = tab;
          break;
        }
      }
      if (match == null) {
        _appendMessage(
          tabId: activeTab.id,
          sender: 'error',
          content: 'No window named $name',
          kind: IrcMessageKind.system,
        );
        notifyListeners();
        return;
      }
      selectTab(match.id);
      return;
    }

    final name = parts.first;
    if (_isChannelName(name)) {
      await joinChannel(JoinChannelRequest(channel: name));
      return;
    }
    final tab = _ensureQueryTab(name);
    _activeTabId = tab.id;
    unawaited(_persistState());
    notifyListeners();
  }

  void _handleTimerCommand(String rest) {
    final parts = rest
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (parts.length == 2 && parts[1].toLowerCase() == 'off') {
      final name = parts[0];
      final cancelled = _commandTimers.remove(name);
      cancelled?.cancel();
      _appendMessage(
        tabId: activeTab.id,
        sender: cancelled == null ? 'error' : '*',
        content: cancelled == null
            ? 'No timer named $name'
            : 'Timer "$name" cancelled',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    if (parts.length < 4) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Usage: /timer <name> <delay_ms> <repetitions> <command>',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    final name = parts[0];
    final delayMs = int.tryParse(parts[1]);
    final repetitions = int.tryParse(parts[2]);
    final command = parts.skip(3).join(' ');
    if (delayMs == null ||
        delayMs <= 0 ||
        repetitions == null ||
        repetitions < 0) {
      _appendMessage(
        tabId: activeTab.id,
        sender: 'error',
        content: 'Usage: /timer <name> <delay_ms> <repetitions> <command>',
        kind: IrcMessageKind.system,
      );
      notifyListeners();
      return;
    }

    _commandTimers.remove(name)?.cancel();
    var remaining = repetitions;
    _commandTimers[name] = Timer.periodic(Duration(milliseconds: delayMs), (
      timer,
    ) {
      unawaited(handleComposerSubmit(command));
      if (repetitions != 0) {
        remaining--;
        if (remaining <= 0) {
          timer.cancel();
          _commandTimers.remove(name);
        }
      }
    });
    _appendMessage(
      tabId: activeTab.id,
      sender: '*',
      content:
          'Timer "$name" set: ${delayMs}ms x ${repetitions == 0 ? '∞' : repetitions} → $command',
      kind: IrcMessageKind.system,
    );
    notifyListeners();
  }

  bool _shouldFilterContent(String content) {
    if (_messageFilters.isEmpty) {
      return false;
    }
    final lower = content.toLowerCase();
    for (final filter in _messageFilters) {
      if (lower.contains(filter)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _sendRegisteredRawSlashCommand(String commandLine) async {
    final command = commandLine.split(RegExp(r'\s+')).first.toLowerCase();
    final currentTarget = activeTab.type == ChatTabType.server
        ? null
        : activeTab.name;
    final raw = _commandService.toRawCommand(
      '/$commandLine',
      currentTarget: currentTarget,
    );
    if (raw == null) {
      final usage = _commandService.getCommand(command)?.usage;
      _appendMessage(
        tabId: _serverTabId(network.id),
        sender: 'error',
        content: usage == null
            ? 'Unsupported command: /$command'
            : 'Usage: $usage',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
      return;
    }

    await _ircService.sendRaw(raw);
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
      case '422':
      case '391':
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: frame.trailing ?? frame.params.join(' '),
          kind: IrcMessageKind.system,
        );
        if (frame.command == '001') {
          unawaited(_sendServiceAuthFallbackIfNeeded());
          _announceBouncerCompatibility();
          _scheduleAutoAway();
          _scheduleLagMeasurement();
        }
        if (frame.command == '376' || frame.command == '422') {
          unawaited(_runPostRegistrationActions());
        }
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
              : DateTime.fromMillisecondsSinceEpoch(
                  createdAt * 1000,
                  isUtc: true,
                ).toLocal().toString();
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content: 'Channel created: $createdText',
            kind: IrcMessageKind.system,
          );
        }
      case '321':
        _channelListing.clear();
        _channelListInProgress = true;
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
          _channelListing.add(
            ChannelListEntry(
              name: channel,
              userCount: int.tryParse(visibleCount) ?? 0,
              topic: topic,
            ),
          );
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
        _channelListInProgress = false;
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
        if (frame.params.length > 3) {
          _rememberNickState(
            frame.params[1],
            ident: frame.params[2],
            host: frame.params[3],
            realName: frame.trailing,
          );
        }
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
        if (frame.params.length > 2) {
          _mergeUserInfo(
            frame.params[1],
            (info) => info.copyWith(
              server: frame.params[2],
              serverInfo: frame.trailing,
            ),
          );
        }
        _appendWhoisMessage(
          frame,
          'WHOIS server: ${frame.params.length > 2 ? '${frame.params[1]} on ${frame.params[2]} ${frame.trailing ?? ''}'.trim() : frame.raw}',
        );
      case '301':
        if (frame.params.length > 1) {
          _rememberNickState(frame.params[1], awayMessage: frame.trailing);
        }
        _appendWhoisMessage(
          frame,
          frame.trailing == null
              ? frame.raw
              : 'WHOIS away: ${frame.params.length > 1 ? frame.params[1] : ''} ${frame.trailing!}'
                    .trim(),
        );
      case '307':
        if (frame.params.length > 1) {
          _mergeUserInfo(
            frame.params[1],
            (info) => info.copyWith(isRegistered: true),
          );
        }
        _appendWhoisMessage(
          frame,
          frame.trailing ?? frame.params.skip(1).join(' '),
        );
      case '313':
        if (frame.params.length > 1) {
          _mergeUserInfo(
            frame.params[1],
            (info) => info.copyWith(isOper: true),
          );
        }
        _appendWhoisMessage(
          frame,
          frame.trailing ?? frame.params.skip(1).join(' '),
        );
      case '330':
        if (frame.params.length > 2) {
          _rememberNickState(frame.params[1], account: frame.params[2]);
          _mergeUserInfo(
            frame.params[1],
            (info) => info.copyWith(isRegistered: true),
          );
        }
        _appendWhoisMessage(
          frame,
          frame.trailing ?? frame.params.skip(1).join(' '),
        );
      case '338':
      case '378':
      case '379':
        if (frame.params.length > 1) {
          _appendUserInfoExtra(frame.params[1], frame.trailing);
        }
        _appendWhoisMessage(
          frame,
          frame.trailing ?? frame.params.skip(1).join(' '),
        );
      case '671':
        if (frame.params.length > 1) {
          _mergeUserInfo(
            frame.params[1],
            (info) => info.copyWith(isSecure: true),
          );
        }
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
        if (frame.params.length > 2) {
          final idle = int.tryParse(frame.params[2]);
          final signedOnSeconds = frame.params.length > 3
              ? int.tryParse(frame.params[3])
              : null;
          _mergeUserInfo(
            frame.params[1],
            (info) => info.copyWith(
              idleSeconds: idle,
              signedOn: signedOnSeconds == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      signedOnSeconds * 1000,
                      isUtc: true,
                    ).toLocal(),
            ),
          );
        }
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
        if (frame.params.length > 1) {
          _mergeUserInfo(
            frame.params[1],
            (info) => info.copyWith(
              channels: _parseWhoisChannels(frame.trailing ?? ''),
            ),
          );
        }
        _appendWhoisMessage(
          frame,
          'WHOIS channels: ${frame.params.length > 1 ? '${frame.params[1]} ${frame.trailing ?? ''}'.trim() : frame.raw}',
        );
      case '318':
        _appendWhoisMessage(
          frame,
          'End of WHOIS for ${frame.params.length > 1 ? frame.params[1] : ''}'
              .trim(),
        );
      case '314':
        if (frame.params.length > 3) {
          _rememberNickState(
            frame.params[1],
            ident: frame.params[2],
            host: frame.params[3],
            realName: frame.trailing,
          );
          _mergeUserInfo(
            frame.params[1],
            (info) => info.copyWith(fromWhowas: true),
          );
        }
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
          'End of WHOWAS for ${frame.params.length > 1 ? frame.params[1] : ''}'
              .trim(),
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
          _channelUsers
              .putIfAbsent(tab.id, () => <String>{})
              .addAll(entries.map((entry) => entry.nick));
          for (final entry in entries) {
            _rememberChannelUserModes(
              tabId: tab.id,
              nick: entry.nick,
              modes: entry.modes,
            );
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
          final details = setBy == null
              ? 'Ban: $mask'
              : 'Ban: $mask set by $setBy';
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
        final rawTargets =
            frame.trailing ?? (frame.params.length > 1 ? frame.params[1] : '');
        final nicknames = rawTargets
            .split(',')
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty)
            .toList(growable: false);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: nicknames.isEmpty
              ? (isOnline
                    ? 'MONITOR online update.'
                    : 'MONITOR offline update.')
              : 'MONITOR ${isOnline ? 'online' : 'offline'}: ${nicknames.join(', ')}',
          kind: IrcMessageKind.system,
        );
      case '732':
        final entries =
            (frame.trailing ?? (frame.params.length > 1 ? frame.params[1] : ''))
                .trim();
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: entries.isEmpty
              ? 'MONITOR list is empty.'
              : 'MONITOR list: $entries',
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
        final channel =
            frame.trailing ??
            (frame.params.length > 1 ? frame.params[1] : null);
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
          final extendedJoinAccount = frame.params.length > 1
              ? frame.params[1]
              : null;
          final extendedJoinRealname =
              frame.trailing ??
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
            kind: IrcMessageKind.event,
          );
          if (nick == (_ircService.currentNick ?? network.nickname)) {
            _activeTabId = tab.id;
          } else {
            _playSound(SoundEvent.join);
            _maybeApplyAutoModes(
              channel,
              nick,
              tab.id,
              ident: identity.ident,
              host: identity.host,
            );
          }
        }
      case 'PART':
        final channel = _firstOrNull(frame.params);
        if (channel != null) {
          final tab = _ensureChannelTab(channel);
          final partingNick = frame.senderNick ?? '';
          _channelUsers
              .putIfAbsent(tab.id, () => <String>{})
              .remove(partingNick);
          if (_isSelfNick(partingNick)) {
            _autoHistoryRequestedChannels.remove(channel.toLowerCase());
          }
          _appendMessage(
            tabId: tab.id,
            sender: '*',
            content:
                '$partingNick left $channel${frame.trailing == null ? '' : ' (${frame.trailing})'}',
            kind: IrcMessageKind.event,
          );
        }
      case 'KICK':
        if (frame.params.length >= 2) {
          final channel = frame.params[0];
          final kickedNick = frame.params[1];
          final tab = _ensureChannelTab(channel);
          _channelUsers
              .putIfAbsent(tab.id, () => <String>{})
              .remove(kickedNick);
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
          if (_isSelfNick(kickedNick)) {
            _playSound(SoundEvent.kick);
          }
          if (_isSelfNick(kickedNick) &&
              _settings.autoRejoinOnKick &&
              _connection.phase == ConnectionPhase.connected) {
            final key = network.autoJoinChannelKeys[channel];
            unawaited(
              _ircService.sendRaw(
                key == null || key.isEmpty
                    ? 'JOIN $channel'
                    : 'JOIN $channel $key',
              ),
            );
            _appendMessage(
              tabId: tab.id,
              sender: '*',
              content: 'Auto-rejoining $channel…',
              kind: IrcMessageKind.event,
            );
          }
        }
      case 'QUIT':
        _removeUserFromAllChannels(frame.senderNick);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content:
              '${frame.senderNick ?? '*'} quit${frame.trailing == null ? '' : ' (${frame.trailing})'}',
          kind: IrcMessageKind.event,
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
          kind: IrcMessageKind.event,
        );
      case 'PONG':
        final token =
            (frame.trailing ?? (frame.params.isEmpty ? '' : frame.params.last))
                .trim();
        if (token.startsWith('LAG')) {
          final sentMs = int.tryParse(token.substring(3));
          if (sentMs != null) {
            final elapsed = DateTime.now().millisecondsSinceEpoch - sentMs;
            if (elapsed >= 0) {
              _lag = Duration(milliseconds: elapsed);
              notifyListeners();
            }
          }
        }
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
        final message = _appendMessage(
          tabId: _serverTabId(network.id),
          sender: 'error',
          content: frame.trailing ?? frame.raw,
          kind: IrcMessageKind.system,
        );
        _emitErrorNotification(
          tabId: _serverTabId(network.id),
          title: '${network.name} server reply',
          body: frame.trailing ?? frame.raw,
          messageId: message?.id,
        );
      case 'ERROR':
        final message = _appendMessage(
          tabId: _serverTabId(network.id),
          sender: 'error',
          content: frame.trailing ?? frame.raw,
          kind: IrcMessageKind.system,
        );
        _emitErrorNotification(
          tabId: _serverTabId(network.id),
          title: '${network.name} connection error',
          body: frame.trailing ?? frame.raw,
          messageId: message?.id,
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
    if (_shouldIgnoreSender(frame) || _shouldFilterContent(content)) {
      return;
    }

    final contextualTarget = _messageContextTarget(target, frame.tags);
    if (_enforceBlacklist(frame, contextualTarget)) {
      return;
    }

    _rememberFrameSenderState(frame);
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

    final message = _appendMessage(
      tabId: tabId,
      sender: frame.senderNick ?? 'notice',
      content: content,
      timestamp: _timestampForFrame(frame),
      tags: frame.tags,
      isPlayback: _isPlaybackBatch(frame.tags['batch']),
      isOwn: _isSelfEcho(frame.senderNick),
      kind: IrcMessageKind.notice,
    );
    _emitIncomingMessageNotification(message);
    _markActivityIfInactive(tabId);
  }

  void _handlePrivmsg(IrcMessageFrame frame) {
    final target = _firstOrNull(frame.params);
    final content = frame.trailing;
    if (target == null || content == null) {
      return;
    }
    if (_shouldIgnoreSender(frame) || _shouldFilterContent(content)) {
      return;
    }

    final contextualTarget = _messageContextTarget(target, frame.tags);
    if (_enforceBlacklist(frame, contextualTarget)) {
      return;
    }

    _rememberFrameSenderState(frame);
    _rememberContextualChannelUser(contextualTarget, frame.senderNick);

    final intentTag = frame.tags['draft/intent']?.toUpperCase();
    if (intentTag == 'ACTION') {
      final tabId = _resolveMessageTabId(
        target: contextualTarget,
        senderNick: frame.senderNick,
        preferServerForDirectMessages: false,
      );
      final message = _appendMessage(
        tabId: tabId,
        sender: frame.senderNick ?? target,
        content: '• $content',
        timestamp: _timestampForFrame(frame),
        tags: frame.tags,
        isPlayback: _isPlaybackBatch(frame.tags['batch']),
        isOwn: _isSelfEcho(frame.senderNick),
        kind: IrcMessageKind.action,
      );
      _emitIncomingMessageNotification(message);
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
        final message = _appendMessage(
          tabId: tabId,
          sender: frame.senderNick ?? target,
          content: '• ${ctcp.args ?? ''}'.trimRight(),
          timestamp: _timestampForFrame(frame),
          tags: frame.tags,
          isPlayback: _isPlaybackBatch(frame.tags['batch']),
          isOwn: _isSelfEcho(frame.senderNick),
          kind: IrcMessageKind.action,
        );
        _emitIncomingMessageNotification(message);
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

    final message = _appendMessage(
      tabId: tabId,
      sender: frame.senderNick ?? target,
      content: assembledContent,
      timestamp: _timestampForFrame(frame),
      tags: frame.tags,
      isPlayback: _isPlaybackBatch(frame.tags['batch']),
      isOwn: _isSelfEcho(frame.senderNick),
    );
    _emitIncomingMessageNotification(message);
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
    final modeText = [
      ...frame.params.skip(1),
      if (frame.trailing != null) frame.trailing!,
    ].join(' ');
    final tabId = target.startsWith('#')
        ? _ensureChannelTab(target).id
        : _serverTabId(network.id);
    if (target.startsWith('#')) {
      _applyChannelModeChange(tabId: tabId, modeText: modeText);
      _channelModes[tabId] = _mergeChannelModeString(
        _channelModes[tabId],
        modeText,
      );
    }
    _appendMessage(
      tabId: tabId,
      sender: '*',
      content: '${frame.senderNick ?? '*'} set mode $modeText on $target',
      kind: IrcMessageKind.system,
    );
    _markActivityIfInactive(tabId);
  }

  void _applyChannelModeChange({
    required String tabId,
    required String modeText,
  }) {
    final tokens = modeText
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return;
    }

    final arguments = tokens.skip(1).toList(growable: false);
    var argumentIndex = 0;
    var adding = true;

    final modeToken = tokens.first;
    if (!modeToken.startsWith('+') && !modeToken.startsWith('-')) {
      return;
    }

    for (final codeUnit in modeToken.runes) {
      final char = String.fromCharCode(codeUnit);
      if (char == '+') {
        adding = true;
        continue;
      }
      if (char == '-') {
        adding = false;
        continue;
      }

      final isUserMode = _prefixForMode(char) != null;
      final consumesArgument =
          isUserMode || _channelModeConsumesParameter(char, adding);
      final argument = consumesArgument && argumentIndex < arguments.length
          ? arguments[argumentIndex++]
          : null;
      if (!isUserMode || argument == null || argument.trim().isEmpty) {
        continue;
      }

      final nick = _normalizeNickPrefix(argument);
      _channelUsers.putIfAbsent(tabId, () => <String>{}).add(nick);
      final modes = _channelUserModes
          .putIfAbsent(tabId, () => <String, Set<String>>{})
          .putIfAbsent(nick.toLowerCase(), () => <String>{});
      if (adding) {
        modes.add(char);
      } else {
        modes.remove(char);
      }
    }
  }

  String _mergeChannelModeString(String? current, String modeText) {
    final existing = <String>{
      for (final char in (current ?? '').runes.map(String.fromCharCode))
        if (char != '+') char,
    };
    var adding = true;
    var changed = false;
    for (final codeUnit in modeText.runes) {
      final char = String.fromCharCode(codeUnit);
      if (char == '+') {
        adding = true;
        continue;
      }
      if (char == '-') {
        adding = false;
        continue;
      }
      if (char.trim().isEmpty) {
        break;
      }
      if (_prefixForMode(char) != null ||
          _channelModeConsumesParameter(char, adding)) {
        continue;
      }
      changed = true;
      if (adding) {
        existing.add(char);
      } else {
        existing.remove(char);
      }
    }
    if (!changed) {
      return current ?? '';
    }
    final ordered = existing.toList()..sort();
    return ordered.isEmpty ? '' : '+${ordered.join()}';
  }

  bool _channelModeConsumesParameter(String mode, bool adding) {
    final chanModes = _serverSupport.channelModes;
    final groups = chanModes.isEmpty
        ? const <String>['b', 'k', 'l', 'imnpst']
        : chanModes.split(',');
    if (groups.isNotEmpty && groups[0].contains(mode)) {
      return true;
    }
    if (groups.length > 1 && groups[1].contains(mode)) {
      return true;
    }
    if (groups.length > 2 && groups[2].contains(mode)) {
      return adding;
    }
    return false;
  }

  void _handleIsupport(IrcMessageFrame frame) {
    _serverSupport = _serverSupport.mergeFrame(frame);
    _nickPrefixChars = _serverSupport.nickPrefixSymbols;
    _channelPrefixChars = _serverSupport.channelTypes;
    _dedupeEquivalentTabs();
    final tokens = isupportTokensFromFrame(frame);
    final supportText = tokens.join(' ');

    _appendMessage(
      tabId: _serverTabId(network.id),
      sender: '*',
      content: supportText.isEmpty
          ? (frame.trailing ?? frame.raw)
          : supportText,
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
    final message = _appendMessage(
      tabId: tabId,
      sender: severity,
      content: details.isEmpty ? frame.raw : details,
      kind: IrcMessageKind.system,
    );
    if (frame.command == 'FAIL' || frame.command == 'WARN') {
      _emitErrorNotification(
        tabId: tabId,
        title: '${network.name} ${frame.command}',
        body: details.isEmpty ? frame.raw : details,
        messageId: message?.id,
      );
    }
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
    final details = setBy == null
        ? '$label: $mask'
        : '$label: $mask set by $setBy';
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
    final newHost = frame.params.length > 1
        ? frame.params[1]
        : frame.trailing ?? '';
    if (newHost.isEmpty) {
      return;
    }

    _rememberNickState(nick, ident: newIdent, host: newHost);

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
          .map(
            (message) => IrcMessage(
              id: message.id,
              tabId: renamedTab.id,
              sender: message.sender,
              content: message.content,
              timestamp: message.timestamp,
              tags: message.tags,
              isPlayback: message.isPlayback,
              isOwn: message.isOwn,
              kind: message.kind,
            ),
          )
          .toList(growable: true);
    }

    final users = _channelUsers.remove(tab.id);
    if (users != null) {
      _channelUsers[renamedTab.id] = users;
    }
    final userModes = _channelUserModes.remove(tab.id);
    if (userModes != null) {
      _channelUserModes[renamedTab.id] = userModes;
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

    final tabId = _targetToTabId(target);
    if (tabId == null) {
      return;
    }

    final timestampParam = frame.params.length > 1 ? frame.params[1] : '*';
    if (timestampParam.trim() == '*') {
      _readMarkers.remove(tabId);
      _appendMessage(
        tabId: tabId,
        sender: '*',
        content:
            '${frame.senderNick ?? 'Someone'} has no read marker for $target',
        kind: IrcMessageKind.system,
      );
      return;
    }

    final markerTimestamp = _parseIrcv3TimestampParam(timestampParam);
    if (markerTimestamp == null) {
      _appendMessage(
        tabId: tabId,
        sender: 'error',
        content: 'Invalid MARKREAD timestamp for $target: $timestampParam',
        kind: IrcMessageKind.system,
      );
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
      transform: (existing) => existing.copyWith(
        content: '[message deleted]',
        tags: {...existing.tags, 'redacted': 'true'},
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
    final emojiUsers = _messageReactions.putIfAbsent(
      msgid,
      () => <String, Set<String>>{},
    );
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

  Future<void> _requestAutoHistoryOnJoin(
    String channel, {
    int limit = 50,
  }) async {
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

    final latestTimestamp = _latestServerTimeForTab(tabId);
    if (latestTimestamp == null) {
      return;
    }

    final success = await _ircService.sendReadMarker(
      target: target,
      timestamp: latestTimestamp,
    );
    if (success) {
      _readMarkers[tabId] = latestTimestamp;
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
        content:
            'BATCH start: $type${frame.params.length > 2 ? ' ${frame.params.skip(2).join(' ')}' : ''}',
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
        'netsplit' =>
          'Netsplit batch completed: ${batch?.messageCount ?? 0} events',
        'netjoin' =>
          'Netjoin batch completed: ${batch?.messageCount ?? 0} events',
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
      final session = _dccSessions[sessionTabId];
      final message = _appendMessage(
        tabId: sessionTabId,
        sender: '*',
        content: _formatIncomingCtcpRequest(senderNick, command, ctcp.args),
        kind: IrcMessageKind.dcc,
        attachments: session == null
            ? const <IrcMessageAttachment>[]
            : [_dccAttachmentForSession(session)],
      );
      if (message != null) {
        _emitNotification(
          channelKind: ForegroundNotificationChannelKind.dccTransfers,
          tabId: sessionTabId,
          title: 'DCC request from $senderNick',
          body: _notificationBodyFor(message.content),
          messageId: message.id,
        );
      }
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
    _playSound(SoundEvent.ctcp);
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
      final tokenMatches =
          (candidate.token ?? '').trim() == (offer.token ?? '').trim() ||
          (offer.token ?? '').trim().isEmpty;
      if (candidate.peerNick.toLowerCase() == senderNick.toLowerCase() &&
          candidate.type == DccSessionType.send &&
          (candidate.filename ?? '').toLowerCase() ==
              (offer.filename ?? '').toLowerCase() &&
          candidate.port == offer.port &&
          tokenMatches) {
        session = candidate;
        break;
      }
    }
    if (session == null) {
      return null;
    }

    final updated = session.copyWith(
      resumeOffset: offer.offset ?? session.resumeOffset,
    );
    _dccSessions[session.tabId] = updated;
    final content = offer.command == 'RESUME'
        ? '$senderNick requested DCC RESUME for ${offer.filename ?? 'file'} at offset ${offer.offset ?? 0}.'
        : '$senderNick acknowledged DCC RESUME for ${offer.filename ?? 'file'} at offset ${offer.offset ?? 0}.';
    _appendMessage(
      tabId: session.tabId,
      sender: '*',
      content: content,
      kind: IrcMessageKind.dcc,
      attachments: [_dccAttachmentForSession(updated)],
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

  Future<void> _respondToCtcpRequest(
    String from,
    String command,
    String? args,
  ) async {
    switch (command) {
      case 'VERSION':
        await _ircService.sendCtcpReply(
          target: from,
          command: 'VERSION',
          args: ctcpVersionReply,
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
          'CHAT' =>
            'DCC CHAT request from $from: ${offer.host ?? '?'}:${offer.port ?? 0}',
          'SEND' =>
            offer.isReverseSend
                ? 'Reverse DCC SEND offer from $from: ${offer.filename ?? 'file'} (${offer.size ?? 0} bytes) token ${offer.token ?? '?'}'
                : 'DCC SEND offer from $from: ${offer.filename ?? 'file'} (${offer.size ?? 0} bytes) ${offer.host ?? '?'}:${offer.port ?? 0}',
          'RESUME' =>
            'DCC RESUME request from $from: ${offer.filename ?? 'file'} at ${offer.offset ?? 0}',
          'ACCEPT' =>
            'DCC ACCEPT reply from $from: ${offer.filename ?? 'file'} at ${offer.offset ?? 0}',
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
    final normalizedChannel = channel.trim();
    final existing =
        _findTab(_channelTabId(network.id, normalizedChannel)) ??
        _findEquivalentTab(ChatTabType.channel, normalizedChannel);
    if (existing != null) {
      return existing;
    }

    final tab = ChatTab(
      id: _channelTabId(network.id, normalizedChannel),
      name: normalizedChannel,
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
    final normalizedNick = nick.trim();
    final existing =
        _findTab(_queryTabId(network.id, normalizedNick)) ??
        _findEquivalentTab(ChatTabType.query, normalizedNick);
    if (existing != null) {
      return existing;
    }

    final tab = ChatTab(
      id: _queryTabId(network.id, normalizedNick),
      name: normalizedNick,
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

  ChatTab _ensureDccTab({required String sessionId, required String name}) {
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
      DccSessionStatus.offering =>
        next.type == DccSessionType.chat
            ? 'DCC CHAT offer created for ${next.peerNick}.'
            : 'DCC SEND offer created for ${next.peerNick}.',
      DccSessionStatus.connecting =>
        next.type == DccSessionType.chat
            ? 'Connecting DCC CHAT session...'
            : 'Connecting DCC SEND transfer...',
      DccSessionStatus.connected =>
        next.type == DccSessionType.chat
            ? 'DCC CHAT connected.'
            : next.direction == 'outgoing'
            ? 'DCC SEND transfer started for ${next.filename ?? 'file'}.'
            : 'Receiving ${next.filename ?? 'file'} to local storage.',
      DccSessionStatus.closed =>
        next.type == DccSessionType.chat
            ? 'DCC CHAT session closed.'
            : next.direction == 'outgoing'
            ? 'DCC SEND finished (${next.bytesTransferred} bytes sent).'
            : 'DCC SEND finished (${next.bytesTransferred} bytes saved locally).',
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
      kind: IrcMessageKind.dcc,
      attachments: [_dccAttachmentForSession(next)],
    );
  }

  IrcMessageAttachment _dccAttachmentForSession(DccSession session) {
    final type = switch (session.type) {
      DccSessionType.chat => IrcMessageAttachmentType.dccChat,
      DccSessionType.send ||
      DccSessionType.unknown => IrcMessageAttachmentType.dccSend,
    };
    final label = switch (session.type) {
      DccSessionType.chat => 'DCC CHAT',
      DccSessionType.send => 'DCC SEND',
      DccSessionType.unknown => 'DCC',
    };
    return IrcMessageAttachment(
      type: type,
      label: label,
      transferId: session.id,
      peerNick: session.peerNick,
      fileName: session.filename,
      size: session.size,
      direction: session.direction,
      status: session.status.name,
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

  ChatTab? _findEquivalentTab(ChatTabType type, String name) {
    final key = _ircCasefold(name);
    for (final tab in _tabs) {
      if (tab.type == type && _ircCasefold(tab.name) == key) {
        return tab;
      }
    }
    return null;
  }

  void _dedupeEquivalentTabs() {
    final canonicalByKey = <String, ChatTab>{};
    final aliases = <String, String>{};
    final nextTabs = <ChatTab>[];

    for (final tab in _tabs) {
      if (tab.type != ChatTabType.channel && tab.type != ChatTabType.query) {
        nextTabs.add(tab);
        continue;
      }

      final key = '${tab.type.name}:${_ircCasefold(tab.name)}';
      final canonical = canonicalByKey[key];
      if (canonical == null) {
        canonicalByKey[key] = tab;
        nextTabs.add(tab);
        continue;
      }

      aliases[tab.id] = canonical.id;
      final canonicalIndex = nextTabs.indexWhere(
        (item) => item.id == canonical.id,
      );
      if (canonicalIndex != -1) {
        nextTabs[canonicalIndex] = canonical.copyWith(
          hasActivity: canonical.hasActivity || tab.hasActivity,
          unreadCount: canonical.unreadCount + tab.unreadCount,
          isEncrypted: canonical.isEncrypted || tab.isEncrypted,
        );
        canonicalByKey[key] = nextTabs[canonicalIndex];
      }
    }

    if (aliases.isEmpty) {
      return;
    }

    _tabs = nextTabs;
    _activeTabId = aliases[_activeTabId] ?? _activeTabId;
    _rekeyMessages(aliases);
    _rekeySetMap(_channelUsers, aliases);
    _rekeyStringMap(_channelTopics, aliases);
    _rekeyStringMap(_channelModes, aliases);
    _rekeyNestedSetMap(_channelUserModes, aliases);
    _rekeyDateTimeMap(_readMarkers, aliases);
    _rekeyNestedSetMap(_messageReactions, aliases);
    _rekeySetMap(_typingUsersByTab, aliases);
  }

  String _ircCasefold(String value) {
    final lower = value.trim().toLowerCase();
    return switch (_serverSupport.caseMapping.toLowerCase()) {
      'ascii' => lower,
      'strict-rfc1459' =>
        lower.replaceAll('[', '{').replaceAll(']', '}').replaceAll(r'\', '|'),
      _ =>
        lower
            .replaceAll('[', '{')
            .replaceAll(']', '}')
            .replaceAll(r'\', '|')
            .replaceAll('^', '~'),
    };
  }

  void _rekeyMessages(Map<String, String> aliases) {
    final next = <String, List<IrcMessage>>{};
    for (final entry in _messages.entries) {
      final tabId = aliases[entry.key] ?? entry.key;
      final messages = next.putIfAbsent(tabId, () => <IrcMessage>[]);
      messages.addAll(
        entry.value.map(
          (message) =>
              message.tabId == tabId ? message : message.copyWith(tabId: tabId),
        ),
      );
    }
    _messages
      ..clear()
      ..addAll(next);
  }

  void _rekeySetMap(Map<String, Set<String>> map, Map<String, String> aliases) {
    final next = <String, Set<String>>{};
    for (final entry in map.entries) {
      next
          .putIfAbsent(aliases[entry.key] ?? entry.key, () => <String>{})
          .addAll(entry.value);
    }
    map
      ..clear()
      ..addAll(next);
  }

  void _rekeyStringMap(Map<String, String> map, Map<String, String> aliases) {
    final next = <String, String>{};
    for (final entry in map.entries) {
      final tabId = aliases[entry.key] ?? entry.key;
      final existing = next[tabId];
      next[tabId] = existing == null || existing.trim().isEmpty
          ? entry.value
          : existing;
    }
    map
      ..clear()
      ..addAll(next);
  }

  void _rekeyNestedSetMap(
    Map<String, Map<String, Set<String>>> map,
    Map<String, String> aliases,
  ) {
    final next = <String, Map<String, Set<String>>>{};
    for (final entry in map.entries) {
      final tabId = aliases[entry.key] ?? entry.key;
      final nested = next.putIfAbsent(tabId, () => <String, Set<String>>{});
      for (final nestedEntry in entry.value.entries) {
        nested
            .putIfAbsent(nestedEntry.key, () => <String>{})
            .addAll(nestedEntry.value);
      }
    }
    map
      ..clear()
      ..addAll(next);
  }

  void _rekeyDateTimeMap(
    Map<String, DateTime> map,
    Map<String, String> aliases,
  ) {
    final next = <String, DateTime>{};
    for (final entry in map.entries) {
      final tabId = aliases[entry.key] ?? entry.key;
      final existing = next[tabId];
      next[tabId] = existing == null || entry.value.isAfter(existing)
          ? entry.value
          : existing;
    }
    map
      ..clear()
      ..addAll(next);
  }

  IrcMessage? _appendMessage({
    required String tabId,
    required String sender,
    required String content,
    DateTime? timestamp,
    Map<String, String?> tags = const <String, String?>{},
    bool isPlayback = false,
    bool isOwn = false,
    IrcMessageKind kind = IrcMessageKind.chat,
    List<IrcMessageAttachment>? attachments,
    String? rawFrame,
  }) {
    final list = _messages.putIfAbsent(tabId, () => []);
    final msgid = tags['msgid'];
    if (msgid != null && list.any((item) => item.tags['msgid'] == msgid)) {
      return null;
    }
    final resolvedAttachments =
        attachments ?? _attachmentsForMessageContent(content, kind);
    final resolvedKind =
        kind == IrcMessageKind.chat && resolvedAttachments.isNotEmpty
        ? IrcMessageKind.media
        : kind;
    final now = DateTime.now();
    list.add(
      IrcMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}-${list.length}',
        networkId: network.id,
        tabId: tabId,
        sender: sender,
        content: content,
        timestamp: timestamp ?? now,
        receivedTimestamp: now,
        rawFrame: rawFrame,
        tags: Map<String, String?>.unmodifiable(tags),
        isPlayback: isPlayback,
        isOwn: isOwn,
        kind: resolvedKind,
        attachments: List<IrcMessageAttachment>.unmodifiable(
          resolvedAttachments,
        ),
      ),
    );
    final appended = list.last;
    final repository = _historyRepository;
    if (repository != null) {
      unawaited(repository.append(networkId: network.id, message: appended));
    }
    return appended;
  }

  void _emitIncomingMessageNotification(IrcMessage? message) {
    if (message == null || message.isOwn || message.isPlayback) {
      return;
    }
    final tab = _findTab(message.tabId);
    if (tab == null) {
      return;
    }

    final plainContent = _notificationBodyFor(message.content);
    if (plainContent.isEmpty) {
      return;
    }

    final channelKind = _notificationKindForMessage(message, tab);
    if (channelKind == null) {
      return;
    }

    // Sounds are independent of the notification permission gating below.
    _playSound(switch (channelKind) {
      ForegroundNotificationChannelKind.highlights => SoundEvent.mention,
      ForegroundNotificationChannelKind.dccTransfers => SoundEvent.ring,
      _ when tab.type == ChatTabType.notice => SoundEvent.notice,
      _ => SoundEvent.privateMessage,
    });

    _emitNotification(
      channelKind: channelKind,
      tabId: message.tabId,
      title: _notificationTitleForMessage(message, tab, channelKind),
      body: '${message.sender}: $plainContent',
      messageId: message.tags['msgid'] ?? message.id,
    );
  }

  void _emitErrorNotification({
    required String tabId,
    required String title,
    required String body,
    String? messageId,
  }) {
    final normalizedBody = _notificationBodyFor(body);
    if (normalizedBody.isEmpty) {
      return;
    }
    _playSound(SoundEvent.fail);
    _emitNotification(
      channelKind: ForegroundNotificationChannelKind.errors,
      tabId: tabId,
      title: title,
      body: normalizedBody,
      messageId: messageId,
    );
  }

  bool _notificationEnabledFor(ForegroundNotificationChannelKind kind) {
    // The ongoing connection/foreground-service notice is always attempted so
    // the app is reachable from the background; the OS shows it once the user
    // has granted notification permission.
    if (kind == ForegroundNotificationChannelKind.connection) {
      return true;
    }
    // Every other alert requires the user to have opted into notifications.
    if (!_settings.notificationsEnabled) {
      return false;
    }
    switch (kind) {
      case ForegroundNotificationChannelKind.highlights:
        return _settings.notifyHighlights;
      case ForegroundNotificationChannelKind.queries:
        return _settings.notifyPrivateMessages;
      case ForegroundNotificationChannelKind.dccTransfers:
        return _settings.notifyDccOffers;
      case ForegroundNotificationChannelKind.errors:
        return _settings.notifyErrors;
      case ForegroundNotificationChannelKind.connection:
      case ForegroundNotificationChannelKind.mediaTransfers:
        return true;
    }
  }

  void _emitNotification({
    required ForegroundNotificationChannelKind channelKind,
    required String tabId,
    required String title,
    required String body,
    String? messageId,
  }) {
    if (_notificationController.isClosed ||
        !_notificationEnabledFor(channelKind)) {
      return;
    }
    final normalizedBody = _truncateNotificationText(body);
    final normalizedTitle = _truncateNotificationText(title, maxLength: 80);
    final stableMessageId =
        (messageId ?? '${DateTime.now().microsecondsSinceEpoch}')
            .trim()
            .replaceAll(RegExp(r'\s+'), '-');
    _notificationController.add(
      ForegroundUserNotification(
        id: '${network.id}:$tabId:${channelKind.name}:$stableMessageId',
        channelKind: channelKind,
        networkId: network.id,
        tabId: tabId,
        title: normalizedTitle,
        body: normalizedBody,
      ),
    );
  }

  ForegroundNotificationChannelKind? _notificationKindForMessage(
    IrcMessage message,
    ChatTab tab,
  ) {
    if (tab.type == ChatTabType.channel &&
        _containsHighlight(message.content)) {
      return ForegroundNotificationChannelKind.highlights;
    }
    if (_hasMediaNotificationAttachment(message)) {
      return ForegroundNotificationChannelKind.mediaTransfers;
    }
    if (tab.type == ChatTabType.query || tab.type == ChatTabType.notice) {
      return ForegroundNotificationChannelKind.queries;
    }
    if (tab.type == ChatTabType.dcc) {
      return ForegroundNotificationChannelKind.dccTransfers;
    }
    return null;
  }

  String _notificationTitleForMessage(
    IrcMessage message,
    ChatTab tab,
    ForegroundNotificationChannelKind channelKind,
  ) {
    return switch (channelKind) {
      ForegroundNotificationChannelKind.highlights =>
        '${message.sender} mentioned you in ${tab.name}',
      ForegroundNotificationChannelKind.queries =>
        'Message from ${message.sender}',
      ForegroundNotificationChannelKind.mediaTransfers =>
        'Media shared in ${tab.name}',
      ForegroundNotificationChannelKind.dccTransfers => 'DCC activity',
      ForegroundNotificationChannelKind.errors => '${network.name} error',
      ForegroundNotificationChannelKind.connection => network.name,
    };
  }

  bool _containsHighlight(String content) {
    final plain = formatIrcPlainText(content).toLowerCase();
    final nick = (_ircService.currentNick ?? network.nickname).trim();
    final terms = <String>[
      if (nick.isNotEmpty) nick,
      ..._settings.highlightWords,
    ];
    for (final term in terms) {
      final normalized = term.trim().toLowerCase();
      if (normalized.isEmpty) {
        continue;
      }
      final escaped = RegExp.escape(normalized);
      if (RegExp(
        '(^|[^A-Za-z0-9_\\-])$escaped([^A-Za-z0-9_\\-]|\$)',
      ).hasMatch(plain)) {
        return true;
      }
    }
    return false;
  }

  bool _hasMediaNotificationAttachment(IrcMessage message) {
    if (message.kind == IrcMessageKind.media) {
      return true;
    }
    return message.attachments.any((attachment) {
      return switch (attachment.type) {
        IrcMessageAttachmentType.image ||
        IrcMessageAttachmentType.video ||
        IrcMessageAttachmentType.audio ||
        IrcMessageAttachmentType.file ||
        IrcMessageAttachmentType.media => true,
        IrcMessageAttachmentType.url ||
        IrcMessageAttachmentType.dccChat ||
        IrcMessageAttachmentType.dccSend => false,
      };
    });
  }

  String _notificationBodyFor(String content) {
    return _truncateNotificationText(formatIrcPlainText(content).trim());
  }

  String _truncateNotificationText(String value, {int maxLength = 180}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 1)}…';
  }

  List<IrcMessageAttachment> _attachmentsForMessageContent(
    String content,
    IrcMessageKind kind,
  ) {
    if (kind == IrcMessageKind.raw || kind == IrcMessageKind.error) {
      return const <IrcMessageAttachment>[];
    }

    return parseMessageContent(formatIrcPlainText(content))
        .where((part) => part.type != ParsedMessagePartType.text)
        .map(_attachmentForParsedPart)
        .toList(growable: false);
  }

  IrcMessageAttachment _attachmentForParsedPart(ParsedMessagePart part) {
    final type = switch (part.type) {
      ParsedMessagePartType.image => IrcMessageAttachmentType.image,
      ParsedMessagePartType.video => IrcMessageAttachmentType.video,
      ParsedMessagePartType.audio => IrcMessageAttachmentType.audio,
      ParsedMessagePartType.file => IrcMessageAttachmentType.file,
      ParsedMessagePartType.media => IrcMessageAttachmentType.media,
      ParsedMessagePartType.url ||
      ParsedMessagePartType.text => IrcMessageAttachmentType.url,
    };
    final label = switch (part.type) {
      ParsedMessagePartType.image => 'Image',
      ParsedMessagePartType.video => 'Video',
      ParsedMessagePartType.audio => 'Audio',
      ParsedMessagePartType.file => 'File',
      ParsedMessagePartType.media => 'Encrypted media',
      ParsedMessagePartType.url || ParsedMessagePartType.text => 'Link',
    };
    return IrcMessageAttachment(
      type: type,
      label: label,
      uri: part.url,
      mediaId: part.mediaId,
    );
  }

  Future<void> _loadPersistedState() async {
    _settings = await _settingsRepository.loadSettings();
    _applySettingsToServices();
    final snapshot = await _persistence.load(network.id);
    if (snapshot == null) {
      await _restoreHistoryFromRepository();
      return;
    }

    if (snapshot.tabs.isNotEmpty) {
      _tabs = snapshot.tabs;
    }

    _messages
      ..clear()
      ..addAll(snapshot.messagesByTab);
    _dedupeEquivalentTabs();

    for (final tab in _tabs) {
      _messages.putIfAbsent(tab.id, () => []);
      if (tab.type == ChatTabType.channel) {
        _channelUsers.putIfAbsent(tab.id, () => <String>{});
        _channelTopics.putIfAbsent(tab.id, () => '');
        _channelModes.putIfAbsent(tab.id, () => '');
      }
    }

    if (snapshot.activeTabId.isNotEmpty &&
        _findTab(snapshot.activeTabId) != null) {
      _activeTabId = snapshot.activeTabId;
    }

    await _restoreHistoryFromRepository();
  }

  /// When an encrypted history repository is present, this makes it the source
  /// of truth for message bodies: any plaintext bodies still in the session
  /// snapshot are migrated into the repository (once), retention is enforced,
  /// and each tab's scrollback is reloaded from the repository. Persisting
  /// afterwards clears chat bodies out of the plaintext snapshot.
  Future<void> _restoreHistoryFromRepository() async {
    final repository = _historyRepository;
    if (repository == null) {
      return;
    }

    for (final entry in _messages.entries) {
      if (entry.value.isNotEmpty) {
        await repository.appendAll(
          networkId: network.id,
          messages: entry.value,
        );
      }
    }

    if (_settings.historyRetentionPerTab > 0) {
      await repository.enforceRetention(
        networkId: network.id,
        maxMessages: _settings.historyRetentionPerTab,
      );
    }

    for (final tab in _tabs) {
      final loaded = await repository.loadTabHistory(
        networkId: network.id,
        tabId: tab.id,
        limit: _historyPageSize,
      );
      _messages[tab.id] = List<IrcMessage>.of(loaded);
    }

    unawaited(_persistState());
  }

  /// Prepends an older page of scrollback for [tabId] from the encrypted
  /// history repository. No-op without a repository or when nothing older
  /// remains. Returns true if any messages were prepended.
  Future<bool> loadOlderHistory(String tabId) async {
    final repository = _historyRepository;
    if (repository == null) {
      return false;
    }

    final current = _messages[tabId];
    final anchor = (current == null || current.isEmpty)
        ? null
        : current.first.id;
    final older = await repository.loadTabHistory(
      networkId: network.id,
      tabId: tabId,
      limit: _historyPageSize,
      beforeMessageId: anchor,
    );
    if (older.isEmpty) {
      return false;
    }

    final list = _messages.putIfAbsent(tabId, () => <IrcMessage>[]);
    final existingIds = list.map((message) => message.id).toSet();
    final toPrepend = older
        .where((message) => !existingIds.contains(message.id))
        .toList(growable: false);
    if (toPrepend.isEmpty) {
      return false;
    }

    list.insertAll(0, toPrepend);
    notifyListeners();
    return true;
  }

  void _applySettingsToServices() {
    _dccService.updateDownloadDirectory(_settings.dccDownloadDirectoryPath);
  }

  Future<void> _persistState() {
    // With an encrypted repository, message bodies live only in that repository;
    // the plaintext session snapshot keeps just the tab shape.
    return _persistence.save(
      networkId: network.id,
      tabs: _tabs,
      messagesByTab: _historyRepository == null
          ? _messages
          : const <String, List<IrcMessage>>{},
      activeTabId: _activeTabId,
    );
  }

  String? _firstOrNull(List<String> values) {
    if (values.isEmpty) {
      return null;
    }

    return values.first;
  }

  void _mergeUserInfo(String nick, IrcUserInfo Function(IrcUserInfo) update) {
    final normalized = _stripModePrefix(nick).trim();
    final key = normalized.toLowerCase();
    if (key.isEmpty) {
      return;
    }
    _userInfoByNick[key] = update(userInfoForNick(normalized));
  }

  void _appendUserInfoExtra(String nick, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return;
    }
    _mergeUserInfo(nick, (info) {
      if (info.extra.contains(text)) {
        return info;
      }
      return info.copyWith(extra: <String>[...info.extra, text]);
    });
  }

  List<String> _parseWhoisChannels(String value) {
    final channels = <String>[];
    for (final raw in value.split(RegExp(r'\s+'))) {
      var token = raw.trim();
      while (token.isNotEmpty && !_isChannelName(token)) {
        token = token.substring(1);
      }
      if (token.isNotEmpty && _isChannelName(token)) {
        channels.add(token);
      }
    }
    channels.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return channels;
  }

  void _appendWhoisMessage(IrcMessageFrame frame, String content) {
    final nick = frame.params.length > 1 ? frame.params[1] : null;
    final targetTabId = nick == null
        ? _serverTabId(network.id)
        : _ensureQueryTab(nick).id;
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

    final subcommandIndex = frame.params.indexWhere(
      (param) => const {
        'LS',
        'LIST',
        'REQ',
        'ACK',
        'NAK',
        'NEW',
        'DEL',
        'END',
      }.contains(param.toUpperCase()),
    );
    if (subcommandIndex == -1) {
      return;
    }

    final subcommand = frame.params[subcommandIndex].toUpperCase();
    final details = [
      ...frame.params.skip(subcommandIndex + 1).where((item) => item != '*'),
      if ((frame.trailing ?? '').trim().isNotEmpty) frame.trailing!.trim(),
    ].join(' ').trim();

    final message = switch (subcommand) {
      'LS' =>
        'CAP LS: ${details.isEmpty ? 'no capabilities reported' : details}',
      'ACK' =>
        'CAP ACK: ${details.isEmpty ? 'no capabilities acknowledged' : details}',
      'NAK' => 'CAP NAK: ${details.isEmpty ? 'request rejected' : details}',
      'NEW' =>
        'CAP NEW: ${details.isEmpty ? 'no new capabilities reported' : details}',
      'DEL' =>
        'CAP DEL: ${details.isEmpty ? 'no removed capabilities reported' : details}',
      'LIST' =>
        'CAP LIST: ${details.isEmpty ? 'no enabled capabilities reported' : details}',
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
        final available = _sortedCapabilities(
          _ircService.availableCapabilities,
        );
        final enabled = _sortedCapabilities(_ircService.enabledCapabilities);
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content:
              'Available capabilities: ${available.isEmpty ? 'none' : available.join(', ')}',
          kind: IrcMessageKind.system,
        );
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content:
              'Enabled capabilities: ${enabled.isEmpty ? 'none' : enabled.join(', ')}',
          kind: IrcMessageKind.system,
        );
        final report = detectBouncerCompatibility(
          availableCapabilities: _ircService.availableCapabilities,
          enabledCapabilities: _ircService.enabledCapabilities,
          serverName: network.host,
          networkName: _serverSupport.networkName,
        );
        _appendMessage(
          tabId: _serverTabId(network.id),
          sender: '*',
          content: 'Compatibility: ${report.summary}',
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
    final segments = rest
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
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
        ? segments
              .skip(1)
              .join(' ')
              .split(RegExp(r'[\s,]+'))
              .where((nick) => nick.trim().isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    await _ircService.sendMonitor(
      subcommand: subcommand,
      nicknames: nicknameParts,
    );
    final detail = nicknameParts.isEmpty
        ? subcommand
        : '$subcommand ${nicknameParts.join(', ')}';
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
      tabId: _isChannelName(target)
          ? _ensureChannelTab(target).id
          : _serverTabId(network.id),
      sender: '*',
      content:
          'Requested METADATA ${subcommand.toUpperCase()} for $target${key == null ? '' : ' ($key)'}',
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
        content:
            'Usage: /rename <new-channel-name> [reason] from a channel tab.',
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
      content:
          'Requested rename from ${activeTab.name} to $newName${(reason ?? '').trim().isEmpty ? '' : ' ($reason)'}',
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

  String _banMaskForNickOrMask(String value) {
    return value.contains('!') || value.contains('@') ? value : '$value!*@*';
  }

  ({String nick, String mask}) _banIdentityForNickOrMask(
    String value,
    int banMaskType,
  ) {
    final trimmed = _stripModePrefix(value).trim();
    final parsed = _parseHostmask(trimmed);
    if (parsed != null) {
      return (
        nick: parsed.nick,
        mask: const BanMaskService().generateBanMask(
          nick: parsed.nick,
          ident: parsed.ident,
          host: parsed.host,
          type: banMaskType,
        ),
      );
    }

    final info = userInfoForNick(trimmed);
    final ident = (info.ident ?? '').trim();
    final host = (info.host ?? '').trim();
    final effectiveType = ident.isEmpty || host.isEmpty ? 10 : banMaskType;
    return (
      nick: trimmed,
      mask: const BanMaskService().generateBanMask(
        nick: trimmed,
        ident: ident.isEmpty ? '*' : ident,
        host: host.isEmpty ? '*' : host,
        type: effectiveType,
      ),
    );
  }

  ({String nick, String ident, String host})? _parseHostmask(String value) {
    final bang = value.indexOf('!');
    final at = value.indexOf('@');
    if (bang <= 0 || at <= bang + 1 || at >= value.length - 1) {
      return null;
    }
    return (
      nick: value.substring(0, bang),
      ident: value.substring(bang + 1, at),
      host: value.substring(at + 1),
    );
  }

  void _scheduleTimedModeRemoval({
    required String channel,
    required String mode,
    required String mask,
    Duration? duration,
  }) {
    if (duration == null || duration <= Duration.zero) {
      return;
    }
    late final Timer timer;
    timer = Timer(duration, () {
      _timedUnbanTimers.remove(timer);
      unawaited(
        _ircService.sendChannelMode(
          channel: channel,
          mode: '-$mode',
          target: mask,
        ),
      );
      _appendMessage(
        tabId: _ensureChannelTab(channel).id,
        sender: '*',
        content: 'Timed ${mode == 'q' ? 'quiet' : 'ban'} removed: $mask',
        kind: IrcMessageKind.system,
      );
      unawaited(_persistState());
      notifyListeners();
    });
    _timedUnbanTimers.add(timer);
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

  DateTime? _parseIrcv3TimestampParam(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final timestamp = trimmed.toLowerCase().startsWith('timestamp=')
        ? trimmed.substring('timestamp='.length)
        : trimmed;
    return DateTime.tryParse(timestamp);
  }

  DateTime? _latestServerTimeForTab(String tabId) {
    final messages = _messages[tabId];
    if (messages == null) {
      return null;
    }

    for (final message in messages.reversed) {
      final rawTime = message.tags['time'];
      if (rawTime == null || rawTime.trim().isEmpty) {
        continue;
      }
      final parsed = DateTime.tryParse(rawTime);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
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

  ({String subcommand, String reference, String? endReference, int limit})
  _parseChatHistoryRequest(String rest) {
    final parts = rest
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return (
        subcommand: 'LATEST',
        reference: '*',
        endReference: null,
        limit: 50,
      );
    }

    final keyword = parts.first.toUpperCase();
    if (keyword == 'TARGETS') {
      final limit = parts.length > 3 ? int.tryParse(parts[3]) ?? 50 : 50;
      return (
        subcommand: 'TARGETS',
        reference: parts.length > 1 ? parts[1] : '',
        endReference: parts.length > 2 ? parts[2] : '',
        limit: limit.clamp(1, 200),
      );
    }

    if (keyword == 'BETWEEN') {
      final limit = parts.length > 3 ? int.tryParse(parts[3]) ?? 50 : 50;
      return (
        subcommand: 'BETWEEN',
        reference: parts.length > 1 ? parts[1] : '',
        endReference: parts.length > 2 ? parts[2] : '',
        limit: limit.clamp(1, 200),
      );
    }

    if (keyword == 'LATEST') {
      if (parts.length == 1) {
        return (
          subcommand: 'LATEST',
          reference: '*',
          endReference: null,
          limit: 50,
        );
      }
      final secondAsLimit = int.tryParse(parts[1]);
      if (secondAsLimit != null) {
        return (
          subcommand: 'LATEST',
          reference: '*',
          endReference: null,
          limit: secondAsLimit.clamp(1, 200),
        );
      }
      final limit = parts.length > 2 ? int.tryParse(parts[2]) ?? 50 : 50;
      return (
        subcommand: 'LATEST',
        reference: parts[1],
        endReference: null,
        limit: limit.clamp(1, 200),
      );
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
        endReference: null,
        limit: limit.clamp(1, 200),
      );
    }

    final limit = int.tryParse(parts.first) ?? 50;
    return (
      subcommand: 'LATEST',
      reference: '*',
      endReference: null,
      limit: limit.clamp(1, 200),
    );
  }

  String _formatChatHistoryRequestMessage(
    ({String subcommand, String reference, String? endReference, int limit})
    request,
  ) {
    if (request.subcommand == 'TARGETS') {
      return 'Requested CHATHISTORY TARGETS (${request.reference}, ${request.endReference}, ${request.limit} targets).';
    }
    if (request.subcommand == 'BETWEEN') {
      return 'Requested CHATHISTORY BETWEEN for ${activeTab.name} (${request.reference}, ${request.endReference}, ${request.limit} messages).';
    }
    return 'Requested CHATHISTORY ${request.subcommand} for ${activeTab.name} (${request.reference}, ${request.limit} messages).';
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

    final index = messages.indexWhere(
      (message) => message.tags['msgid'] == msgid,
    );
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

    return normalized ==
        (_ircService.currentNick ?? network.nickname).trim().toLowerCase();
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
    if (oldNick == null ||
        oldNick.isEmpty ||
        newNick == null ||
        newNick.isEmpty) {
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

    _setTabActivity(tabId, true, incrementUnread: true);
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

  void _setTabActivity(
    String tabId,
    bool hasActivity, {
    bool incrementUnread = false,
  }) {
    _tabs = _tabs
        .map(
          (tab) => tab.id == tabId
              ? tab.copyWith(
                  hasActivity: hasActivity,
                  unreadCount: hasActivity
                      ? (incrementUnread
                            ? tab.unreadCount + 1
                            : tab.unreadCount)
                      : 0,
                )
              : tab,
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelReconnect();
    for (final timer in _commandTimers.values) {
      timer.cancel();
    }
    _commandTimers.clear();
    for (final timer in _timedUnbanTimers) {
      timer.cancel();
    }
    _timedUnbanTimers.clear();
    _autoAwayTimer?.cancel();
    _lagTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _dccService.dispose();
    _ircService.dispose();
    _notificationController.close();
    super.dispose();
  }
}

String _serverTabId(String networkId) => 'server::$networkId';
String _noticeTabId(String networkId) => 'notice::$networkId';
String _channelTabId(String networkId, String name) =>
    'channel::$networkId::${name.trim().toLowerCase()}';
String _queryTabId(String networkId, String nick) =>
    'query::$networkId::${nick.trim().toLowerCase()}';
String _dccTabId(String networkId, String sessionId) =>
    'dcc::$networkId::$sessionId';

import 'dart:async';
import 'dart:convert';

import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/parser/ctcp.dart';
import 'package:androidircx/irc/parser/irc_capability_parser.dart';
import 'package:androidircx/irc/parser/irc_message_parser.dart';
import 'package:androidircx/irc/parser/irc_sts_parser.dart';
import 'package:androidircx/irc/parser/isupport_parser.dart';
import 'package:androidircx/irc/sasl/scram_sha256_session.dart';
import 'package:androidircx/irc/services/irc_sts_policy_store.dart';
import 'package:androidircx/irc/services/irc_transport.dart';

typedef IrcTransportConnector =
    Future<IrcTransport> Function(NetworkConfig network);

enum SaslAuthStatus {
  idle,
  notConfigured,
  pending,
  unavailable,
  mechanismUnavailable,
  requested,
  authenticating,
  succeeded,
  failed,
  aborted,
}

class IrcService {
  static const Set<String> _preferredCapabilities = <String>{
    'account-notify',
    'account-tag',
    'away-notify',
    'batch',
    'bot',
    'cap-notify',
    'chghost',
    'draft/account-registration',
    'draft/channel-rename',
    'draft/multiline',
    'draft/read-marker',
    'draft/typing',
    'draft/message-redaction',
    'echo-message',
    'event-playback',
    'extended-join',
    'extended-monitor',
    'invite-notify',
    'labeled-response',
    'message-tags',
    'monitor',
    'multi-prefix',
    'server-time',
    'setname',
    'standard-replies',
    'typing',
    'userhost-in-names',
    'utf8only',
  };
  static const int _maxCapReqLineLength = 480;
  static const Set<String> _capSubcommands = <String>{
    'LS',
    'LIST',
    'REQ',
    'ACK',
    'NAK',
    'NEW',
    'DEL',
    'END',
  };

  IrcService({
    IrcTransportConnector? transportConnector,
    String Function()? scramNonceGenerator,
    IrcStsPolicyStore? stsPolicyStore,
    DateTime Function()? now,
  }) : _transportConnector = transportConnector ?? defaultIrcTransportConnector,
       _scramNonceGenerator = scramNonceGenerator,
       _stsPolicyStore = stsPolicyStore ?? SharedPrefsIrcStsPolicyStore(),
       _now = now ?? DateTime.now,
       _state = const ConnectionSnapshot(
         networkId: '',
         phase: ConnectionPhase.idle,
       );

  final IrcTransportConnector _transportConnector;
  final String Function()? _scramNonceGenerator;
  final IrcStsPolicyStore _stsPolicyStore;
  final DateTime Function() _now;
  final StreamController<String> _rawEventsController =
      StreamController<String>.broadcast();
  final StreamController<IrcMessageFrame> _framesController =
      StreamController<IrcMessageFrame>.broadcast();
  final StreamController<ConnectionSnapshot> _stateController =
      StreamController<ConnectionSnapshot>.broadcast();
  final StreamController<
    ({String label, String command, IrcMessageFrame frame})
  >
  _labeledResponsesController =
      StreamController<
        ({String label, String command, IrcMessageFrame frame})
      >.broadcast();

  IrcTransport? _transport;
  StreamSubscription<String>? _linesSubscription;
  ConnectionSnapshot _state;
  String? _currentNick;
  final Set<String> _capAvailable = <String>{};
  final Set<String> _capEnabled = <String>{};
  final Set<String> _capRequested = <String>{};
  final Map<String, String> _capValues = <String, String>{};
  IrcServerSupport _serverSupport = const IrcServerSupport.empty();
  bool _capNegotiationActive = false;
  bool _capEnded = false;
  bool _stsUpgradeInProgress = false;
  bool _saslInProgress = false;
  SaslAuthStatus _saslAuthStatus = SaslAuthStatus.idle;
  SaslMechanism? _activeSaslMechanism;
  NetworkConfig? _network;
  String? _primaryNick;
  String? _altNickBase;
  int _altNickAttempt = 0;
  ScramSha256Session? _scramSession;
  bool _scramAwaitingServerFinal = false;
  int _labelCounter = 0;
  final Map<String, String> _pendingLabels = <String, String>{};
  Future<void>? _connectInFlight;
  int _connectGeneration = 0;
  bool _isDisposed = false;

  ConnectionSnapshot get state => _state;
  String? get currentNick => _currentNick;
  Set<String> get enabledCapabilities => Set<String>.unmodifiable(_capEnabled);
  Set<String> get availableCapabilities =>
      Set<String>.unmodifiable(_capAvailable);
  Map<String, String> get capabilityValues =>
      Map<String, String>.unmodifiable(_capValues);
  IrcServerSupport get serverSupport => _serverSupport;
  Set<String> get availableSaslMechanisms =>
      parseIrcCapabilityValueList(_capValues['sasl']);
  SaslAuthStatus get saslAuthStatus => _saslAuthStatus;
  bool get saslConfigured => _shouldUseSasl(_network);
  bool get saslSucceeded => _saslAuthStatus == SaslAuthStatus.succeeded;
  Stream<String> get rawEvents => _rawEventsController.stream;
  Stream<IrcMessageFrame> get frames => _framesController.stream;
  Stream<ConnectionSnapshot> get stateStream => _stateController.stream;
  Stream<({String label, String command, IrcMessageFrame frame})>
  get labeledResponses => _labeledResponsesController.stream;
  bool get supportsChatHistory =>
      _capEnabled.contains('chathistory') ||
      _capEnabled.contains('draft/chathistory');
  bool get supportsReadMarker => _capEnabled.contains('draft/read-marker');
  bool get supportsMessageRedaction =>
      _capEnabled.contains('draft/message-redaction');
  bool get supportsMultiline => _capEnabled.contains('draft/multiline');
  bool get supportsTyping =>
      _capEnabled.contains('typing') || _capEnabled.contains('draft/typing');
  bool get supportsSetName => _capEnabled.contains('setname');

  Future<void> connect(NetworkConfig network) {
    if (_isDisposed) {
      return Future<void>.value();
    }
    if (_isConnectionActive(_state.phase)) {
      return _connectInFlight ?? Future<void>.value();
    }

    final future = _connectInternal(network);
    _connectInFlight = future;
    future.whenComplete(() {
      if (identical(_connectInFlight, future)) {
        _connectInFlight = null;
      }
    });
    return future;
  }

  Future<void> _connectInternal(NetworkConfig network) async {
    final generation = _connectGeneration + 1;
    _connectGeneration = generation;
    final effectiveNetwork = await _networkWithActiveStsPolicy(network);
    if (_isDisposed || generation != _connectGeneration) {
      return;
    }
    _primaryNick = effectiveNetwork.nickname.trim();
    _altNickBase = _resolveAltNickBase(effectiveNetwork);
    _altNickAttempt = 0;
    _currentNick = _primaryNick;
    _network = effectiveNetwork;
    _capAvailable.clear();
    _capEnabled.clear();
    _capRequested.clear();
    _capValues.clear();
    _serverSupport = const IrcServerSupport.empty();
    _capNegotiationActive = false;
    _capEnded = false;
    _stsUpgradeInProgress = false;
    _saslInProgress = false;
    _saslAuthStatus = _shouldUseSasl(effectiveNetwork)
        ? SaslAuthStatus.pending
        : SaslAuthStatus.notConfigured;
    _activeSaslMechanism = null;
    _scramSession = null;
    _scramAwaitingServerFinal = false;
    _updateState(
      ConnectionSnapshot(
        networkId: effectiveNetwork.id,
        phase: ConnectionPhase.connecting,
        message:
            'Opening socket to ${effectiveNetwork.host}:${effectiveNetwork.port}',
      ),
    );

    try {
      _transport = await _transportConnector(effectiveNetwork);
      if (!_isCurrentConnect(generation, effectiveNetwork.id)) {
        final staleTransport = _transport;
        _transport = null;
        await staleTransport?.close();
        return;
      }
      _linesSubscription = _transport!.lines.listen(
        _handleIncomingLine,
        onError: _handleTransportError,
        onDone: _handleTransportDone,
      );

      _updateState(
        ConnectionSnapshot(
          networkId: effectiveNetwork.id,
          phase: ConnectionPhase.registering,
          message: 'Registering with server.',
        ),
      );
      await sendCapLs();
      if ((effectiveNetwork.password ?? '').isNotEmpty) {
        await sendRaw('PASS ${effectiveNetwork.password}');
      }
      await _sendNick(_primaryNick!);
      await sendRaw(
        'USER ${effectiveNetwork.username} 0 * :${effectiveNetwork.realName}',
      );
    } catch (error) {
      if (!_isCurrentConnect(generation, effectiveNetwork.id)) {
        return;
      }
      await _cleanupTransport();
      _updateState(
        ConnectionSnapshot(
          networkId: effectiveNetwork.id,
          phase: ConnectionPhase.error,
          message: error.toString(),
        ),
      );
    }
  }

  Future<NetworkConfig> _networkWithActiveStsPolicy(
    NetworkConfig network,
  ) async {
    final policy = await _stsPolicyStore.loadPolicy(network.host);
    if (policy == null) {
      return network;
    }

    final now = _now().toUtc();
    if (!policy.isActive(now)) {
      await _stsPolicyStore.deletePolicy(network.host);
      return network;
    }

    if (network.useTls) {
      return network;
    }

    _emitRawEvent(
      '** STS policy active: using TLS ${network.host}:${policy.port}',
    );
    return network.copyWith(useTls: true, port: policy.port);
  }

  Future<void> disconnect([String? reason]) async {
    if (_isDisposed) {
      return;
    }
    if (_state.networkId.isEmpty) {
      return;
    }

    _connectGeneration += 1;
    _updateState(_state.copyWith(phase: ConnectionPhase.disconnecting));
    try {
      if (_transport != null) {
        await sendRaw('QUIT :${reason ?? 'Client disconnected'}');
      }
    } catch (_) {
      // Best effort quit.
    }

    await _cleanupTransport();

    _updateState(
      const ConnectionSnapshot(
        networkId: '',
        phase: ConnectionPhase.disconnected,
        message: 'Disconnected.',
      ),
    );
  }

  Future<void> sendRaw(String line, {String? redactedLine}) async {
    if (_isDisposed) {
      return;
    }
    final transport = _transport;
    if (transport == null) {
      return;
    }

    _emitRawEvent('>> ${redactedLine ?? line}');
    await transport.sendLine(line);
  }

  Future<String> sendRawLabeled(String line) async {
    if (_capEnabled.contains('labeled-response') ||
        _capEnabled.contains('draft/labeled-response')) {
      _labelCounter += 1;
      final label =
          'androidircx-${DateTime.now().millisecondsSinceEpoch}-$_labelCounter';
      _pendingLabels[label] = line;
      await sendRaw('@label=$label $line');
      return label;
    }

    await sendRaw(line);
    return '';
  }

  Future<void> joinChannel(String channel, [String? key]) async {
    final normalizedKey = (key ?? '').trim();
    if (normalizedKey.isEmpty) {
      await sendRaw('JOIN $channel');
      return;
    }

    await sendRaw(
      'JOIN $channel $normalizedKey',
      redactedLine: 'JOIN $channel [REDACTED]',
    );
  }

  Future<void> sendPrivmsg({
    required String target,
    required String text,
    String? replyTo,
  }) async {
    if (text.contains('\n')) {
      await _sendMultilinePrivmsg(target: target, text: text, replyTo: replyTo);
      return;
    }

    final normalizedReply = (replyTo ?? '').trim();
    if (normalizedReply.isEmpty) {
      await sendRaw('PRIVMSG $target :$text');
      return;
    }

    await sendRaw('@+draft/reply=$normalizedReply PRIVMSG $target :$text');
  }

  Future<void> _sendMultilinePrivmsg({
    required String target,
    required String text,
    String? replyTo,
  }) async {
    final lines = text.split('\n');
    if (!supportsMultiline || lines.length <= 1) {
      for (final line in lines) {
        await sendPrivmsg(target: target, text: line, replyTo: replyTo);
      }
      return;
    }

    final concatTag =
        'androidircx-multiline-${DateTime.now().millisecondsSinceEpoch}';
    final normalizedReply = (replyTo ?? '').trim();
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      final isLast = index == lines.length - 1;
      final tags = <String>[
        'draft/multiline-concat=${isLast ? '' : concatTag}',
        if (normalizedReply.isNotEmpty && isLast)
          '+draft/reply=$normalizedReply',
      ];
      await sendRaw('@${tags.join(';')} PRIVMSG $target :$line');
    }
  }

  Future<void> sendNotice({
    required String target,
    required String text,
  }) async {
    await sendRaw('NOTICE $target :$text');
  }

  Future<void> sendWhois(String nick) async {
    await sendRaw('WHOIS $nick $nick');
  }

  Future<bool> sendSetName(String realName) async {
    if (!supportsSetName) {
      return false;
    }

    await sendRaw('SETNAME :$realName');
    return true;
  }

  Future<void> sendWho(String mask) async {
    final value = mask.trim();
    await sendRaw(value.isEmpty ? 'WHO' : 'WHO $value');
  }

  Future<void> sendWhowas(String nick) async {
    await sendRaw('WHOWAS $nick');
  }

  Future<void> sendNames(String channel) async {
    await sendRaw('NAMES $channel');
  }

  Future<void> sendList([String? filter]) async {
    final value = (filter ?? '').trim();
    await sendRaw(value.isEmpty ? 'LIST' : 'LIST $value');
  }

  Future<bool> sendChatHistory({
    required String target,
    String subcommand = 'LATEST',
    String reference = '*',
    String? endReference,
    int limit = 50,
  }) async {
    if (!supportsChatHistory) {
      return false;
    }

    final command = _formatChatHistoryCommand(
      target: target,
      subcommand: subcommand,
      reference: reference,
      endReference: endReference,
      limit: limit,
    );
    if (command == null) {
      return false;
    }

    await sendRawLabeled(command);
    return true;
  }

  Future<bool> sendReadMarker({
    required String target,
    DateTime? timestamp,
    int? timestampMillis,
  }) async {
    if (!supportsReadMarker) {
      return false;
    }

    final effectiveTimestamp =
        timestamp ??
        (timestampMillis == null
            ? DateTime.now().toUtc()
            : DateTime.fromMillisecondsSinceEpoch(
                timestampMillis,
                isUtc: true,
              ));
    await sendRaw(
      'MARKREAD $target timestamp=${_formatIrcv3Timestamp(effectiveTimestamp)}',
    );
    return true;
  }

  String? _formatChatHistoryCommand({
    required String target,
    required String subcommand,
    required String reference,
    required String? endReference,
    required int limit,
  }) {
    final normalizedSubcommand = subcommand.toUpperCase();
    return switch (normalizedSubcommand) {
      'BETWEEN' =>
        endReference == null || endReference.trim().isEmpty
            ? null
            : 'CHATHISTORY BETWEEN $target ${_normalizeChatHistoryReference(reference)} ${_normalizeChatHistoryReference(endReference)} $limit',
      'TARGETS' =>
        endReference == null || endReference.trim().isEmpty
            ? null
            : 'CHATHISTORY TARGETS ${_normalizeChatHistoryTimestampReference(reference)} ${_normalizeChatHistoryTimestampReference(endReference)} $limit',
      _ =>
        'CHATHISTORY $normalizedSubcommand $target ${_normalizeChatHistoryReference(reference)} $limit',
    };
  }

  String _normalizeChatHistoryReference(String reference) {
    final trimmed = reference.trim();
    if (trimmed.isEmpty || trimmed == '*') {
      return '*';
    }
    final normalized = trimmed.toLowerCase();
    if (normalized.startsWith('msgid=') ||
        normalized.startsWith('timestamp=')) {
      return trimmed;
    }
    if (DateTime.tryParse(trimmed) != null) {
      return 'timestamp=$trimmed';
    }
    return 'msgid=$trimmed';
  }

  String _normalizeChatHistoryTimestampReference(String reference) {
    final trimmed = reference.trim();
    if (trimmed.toLowerCase().startsWith('timestamp=')) {
      return trimmed;
    }
    return 'timestamp=$trimmed';
  }

  String _formatIrcv3Timestamp(DateTime timestamp) {
    final utc = timestamp.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${two(utc.month)}-${two(utc.day)}T'
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}.'
        '${three(utc.millisecond)}Z';
  }

  Future<bool> redactMessage({
    required String target,
    required String msgid,
  }) async {
    if (!supportsMessageRedaction) {
      return false;
    }

    await sendRaw('REDACT $target $msgid');
    return true;
  }

  Future<void> sendMotd() async {
    await sendRaw('MOTD');
  }

  Future<void> sendTime([String? server]) async {
    final value = (server ?? '').trim();
    await sendRaw(value.isEmpty ? 'TIME' : 'TIME $value');
  }

  Future<void> sendVersion([String? server]) async {
    final value = (server ?? '').trim();
    await sendRaw(value.isEmpty ? 'VERSION' : 'VERSION $value');
  }

  Future<void> sendLinks([String? mask]) async {
    final value = (mask ?? '').trim();
    await sendRaw(value.isEmpty ? 'LINKS' : 'LINKS $value');
  }

  Future<void> sendIson(List<String> nicknames) async {
    final filtered = nicknames
        .map((nick) => nick.trim())
        .where((nick) => nick.isNotEmpty)
        .toList(growable: false);
    if (filtered.isEmpty) {
      return;
    }
    await sendRaw('ISON ${filtered.join(' ')}');
  }

  Future<void> sendUserhost(List<String> nicknames) async {
    final filtered = nicknames
        .map((nick) => nick.trim())
        .where((nick) => nick.isNotEmpty)
        .toList(growable: false);
    if (filtered.isEmpty) {
      return;
    }
    await sendRaw('USERHOST ${filtered.join(' ')}');
  }

  Future<void> sendMonitor({
    required String subcommand,
    List<String> nicknames = const <String>[],
  }) async {
    final normalizedSubcommand = subcommand.trim().toUpperCase();
    if (normalizedSubcommand.isEmpty) {
      return;
    }

    final filtered = nicknames
        .map((nick) => nick.trim())
        .where((nick) => nick.isNotEmpty)
        .toList(growable: false);
    if (filtered.isEmpty) {
      await sendRaw('MONITOR $normalizedSubcommand');
      return;
    }

    await sendRaw('MONITOR $normalizedSubcommand ${filtered.join(',')}');
  }

  Future<void> sendInvite({
    required String nick,
    required String channel,
  }) async {
    await sendRaw('INVITE $nick $channel');
  }

  Future<void> sendKick({
    required String channel,
    required String nick,
    String? reason,
  }) async {
    final suffix = (reason ?? '').trim().isEmpty ? '' : ' :${reason!.trim()}';
    await sendRaw('KICK $channel $nick$suffix');
  }

  Future<void> sendChannelMode({
    required String channel,
    required String mode,
    required String target,
  }) async {
    await sendRaw('MODE $channel $mode $target');
  }

  Future<void> sendBanList(String channel) async {
    await sendRaw('MODE $channel +b');
  }

  Future<void> sendExceptList(String channel) async {
    await sendRaw('MODE $channel +e');
  }

  Future<void> sendInviteList(String channel) async {
    await sendRaw('MODE $channel +I');
  }

  Future<void> sendQuietList(String channel) async {
    await sendRaw('MODE $channel +q');
  }

  Future<void> sendTopic({required String channel, String? topic}) async {
    if ((topic ?? '').trim().isEmpty) {
      await sendRaw('TOPIC $channel');
      return;
    }

    await sendRaw('TOPIC $channel :$topic');
  }

  Future<void> sendMode(String args) async {
    await sendRaw('MODE $args');
  }

  Future<void> sendMetadata({
    required String target,
    required String subcommand,
    String? key,
    String? value,
  }) async {
    final normalizedSubcommand = subcommand.trim().toUpperCase();
    final normalizedKey = (key ?? '').trim();
    final normalizedValue = (value ?? '').trim();
    final parts = <String>[
      'METADATA',
      target,
      normalizedSubcommand,
      if (normalizedKey.isNotEmpty) normalizedKey,
    ];
    var line = parts.join(' ');
    if (normalizedValue.isNotEmpty) {
      line = '$line :$normalizedValue';
    }
    await sendRaw(line);
  }

  Future<void> sendChannelRename({
    required String oldName,
    required String newName,
    String? reason,
  }) async {
    final normalizedReason = (reason ?? '').trim();
    final suffix = normalizedReason.isEmpty ? '' : ' :$normalizedReason';
    await sendRaw('RENAME $oldName $newName$suffix');
  }

  Future<void> sendCapLs() async {
    _capNegotiationActive = true;
    _capEnded = false;
    await sendRaw('CAP LS 302');
  }

  Future<void> sendCapList() async {
    await sendRaw('CAP LIST');
  }

  Future<void> sendCapReq(String capabilities) async {
    _capNegotiationActive = true;
    _capEnded = false;
    final capabilityTokens = capabilities
        .split(RegExp(r'\s+'))
        .map((capability) => capability.trim())
        .where((capability) => capability.isNotEmpty)
        .toList(growable: false);
    _capRequested.addAll(_capabilityRequestNames(capabilityTokens));
    await _sendCapReqBatches(capabilityTokens);
  }

  Future<void> sendCapEnd() async {
    await sendRaw('CAP END');
  }

  Future<void> sendAway([String? message]) async {
    final value = (message ?? '').trim();
    if (value.isEmpty) {
      await sendRaw('AWAY');
      return;
    }

    await sendRaw('AWAY :$value');
  }

  Future<void> sendAction({
    required String target,
    required String text,
  }) async {
    await sendCtcpRequest(target: target, command: 'ACTION', args: text);
  }

  Future<void> sendCtcpRequest({
    required String target,
    required String command,
    String? args,
  }) async {
    await sendRaw('PRIVMSG $target :${encodeCtcp(command, args)}');
  }

  Future<void> sendCtcpReply({
    required String target,
    required String command,
    String? args,
  }) async {
    await sendRaw('NOTICE $target :${encodeCtcp(command, args)}');
  }

  Future<bool> sendTyping({
    required String target,
    required String status,
  }) async {
    if (!supportsTyping) {
      return false;
    }

    final tagName = _capEnabled.contains('typing')
        ? '+typing'
        : '+draft/typing';
    await sendRaw('@$tagName=$status TAGMSG $target');
    return true;
  }

  Future<void> sendReaction({
    required String target,
    required String msgid,
    required String emoji,
  }) async {
    await sendRaw('@+draft/react=$msgid\\:$emoji TAGMSG $target');
  }

  void _handleIncomingLine(String line) {
    if (_isDisposed) {
      return;
    }
    _emitRawEvent('<< $line');
    final frame = parseIrcMessage(line);
    _handleLabeledResponse(frame);
    if (!_framesController.isClosed) {
      _framesController.add(frame);
    }

    if (frame.command == 'PING') {
      final payload =
          frame.trailing ?? (frame.params.isNotEmpty ? frame.params.last : '');
      unawaited(sendRaw('PONG :$payload'));
      return;
    }

    if (frame.command == 'CAP') {
      _handleCap(frame);
      return;
    }

    if (frame.command == 'AUTHENTICATE') {
      _handleAuthenticate(frame);
      return;
    }

    if (frame.command == '005') {
      _serverSupport = _serverSupport.mergeFrame(frame);
    }

    if (frame.command == 'ERROR') {
      unawaited(_cleanupTransport());
      _updateState(
        ConnectionSnapshot(
          networkId: _state.networkId,
          phase: ConnectionPhase.error,
          message: frame.trailing ?? frame.raw,
        ),
      );
      return;
    }

    if (frame.command == '903') {
      _saslInProgress = false;
      _saslAuthStatus = SaslAuthStatus.succeeded;
      _activeSaslMechanism = null;
      _scramSession = null;
      _scramAwaitingServerFinal = false;
      _rawEventsController.add('** SASL authentication successful');
      _updateState(
        ConnectionSnapshot(
          networkId: _state.networkId,
          phase: ConnectionPhase.registering,
          message: 'SASL authentication successful.',
        ),
      );
      unawaited(_endCapNegotiation());
      return;
    }

    if (frame.command == '902' ||
        frame.command == '904' ||
        frame.command == '905' ||
        frame.command == '906' ||
        frame.command == '907') {
      _saslInProgress = false;
      _saslAuthStatus = SaslAuthStatus.failed;
      _activeSaslMechanism = null;
      _scramSession = null;
      _scramAwaitingServerFinal = false;
      _rawEventsController.add(_saslFailureMessage(frame));
      _updateState(
        ConnectionSnapshot(
          networkId: _state.networkId,
          phase: ConnectionPhase.registering,
          message: _saslFailureMessage(frame),
        ),
      );
      unawaited(_endCapNegotiation());
      return;
    }

    if (frame.command == '908') {
      final mechanisms = frame.params.length > 1
          ? frame.params[1]
          : frame.trailing;
      if ((mechanisms ?? '').trim().isNotEmpty) {
        _capValues['sasl'] = mechanisms!.trim();
        _rawEventsController.add(
          '** SASL mechanisms available: ${_capValues['sasl']}',
        );
      }
      if (_saslInProgress) {
        _saslInProgress = false;
        _saslAuthStatus = SaslAuthStatus.mechanismUnavailable;
        _activeSaslMechanism = null;
        _scramSession = null;
        _scramAwaitingServerFinal = false;
        unawaited(_endCapNegotiation());
      }
      return;
    }

    if (frame.command == '001') {
      _altNickAttempt = 0;
      _updateState(
        ConnectionSnapshot(
          networkId: _state.networkId,
          phase: ConnectionPhase.connected,
          message: frame.trailing ?? 'Connected.',
        ),
      );
      return;
    }

    if (frame.command == 'NICK') {
      final senderNick = frame.senderNick;
      final nextNick = frame.trailing ?? _firstOrNull(frame.params);
      if (senderNick != null &&
          senderNick == _currentNick &&
          nextNick != null) {
        _currentNick = nextNick;
      }
    }

    if (frame.command == '433' || frame.command == '436') {
      _handleNicknameCollision(frame);
    }
  }

  void _handleCap(IrcMessageFrame frame) {
    final params = frame.params;
    final subcommandIndex = _capSubcommandIndex(params);
    if (subcommandIndex == null) {
      return;
    }

    final subcommand = params[subcommandIndex].toUpperCase();
    final rest = params.skip(subcommandIndex + 1).toList(growable: false);
    final trailing = frame.trailing ?? '';

    switch (subcommand) {
      case 'LS':
        _storeAvailableCapabilityTokens(_capabilitySource(rest, trailing));
        if (_stsUpgradeInProgress) {
          break;
        }
        if (!_capHasMoreLines(rest)) {
          _requestAvailableCapabilities();
        }
        break;
      case 'LIST':
        _storeEnabledCapabilityTokens(
          _capabilitySource(rest, trailing),
          allowDisablePrefix: true,
        );
        break;
      case 'ACK':
        _handleCapAck(_capabilitySource(rest, trailing));
        break;
      case 'NEW':
        _handleCapNew(_capabilitySource(rest, trailing));
        break;
      case 'DEL':
        _handleCapDel(_capabilitySource(rest, trailing));
        break;
      case 'NAK':
        _handleCapNak(_capabilitySource(rest, trailing));
        break;
      default:
        break;
    }
  }

  void _handleStsCapability(String? value) {
    final network = _network;
    if (network == null) {
      return;
    }

    final directive = parseIrcStsDirective(value);
    if (!network.useTls) {
      final port = directive.port;
      if (port == null || _stsUpgradeInProgress) {
        return;
      }

      _stsUpgradeInProgress = true;
      unawaited(
        _restartForStsUpgrade(network.copyWith(useTls: true, port: port)),
      );
      return;
    }

    final durationSeconds = directive.durationSeconds;
    if (durationSeconds == null) {
      return;
    }

    if (durationSeconds == 0) {
      unawaited(_deleteStsPolicy(network.host));
      return;
    }

    unawaited(_saveStsPolicy(network, directive));
  }

  Future<void> _restartForStsUpgrade(NetworkConfig secureNetwork) async {
    _rawEventsController.add(
      '** STS upgrade: reconnecting with TLS on '
      '${secureNetwork.host}:${secureNetwork.port}',
    );
    _updateState(
      ConnectionSnapshot(
        networkId: secureNetwork.id,
        phase: ConnectionPhase.reconnecting,
        message:
            'STS upgrade requested TLS on '
            '${secureNetwork.host}:${secureNetwork.port}.',
      ),
    );
    await _cleanupTransport(rescheduleStsPolicy: false);
    await _connectInternal(secureNetwork);
  }

  Future<void> _saveStsPolicy(
    NetworkConfig network,
    IrcStsDirective directive,
  ) async {
    final durationSeconds = directive.durationSeconds;
    if (durationSeconds == null || durationSeconds <= 0) {
      return;
    }

    await _stsPolicyStore.savePolicy(
      IrcStsPolicy(
        host: network.host,
        port: network.port,
        durationSeconds: durationSeconds,
        expiresAt: _now().toUtc().add(Duration(seconds: durationSeconds)),
        preload: directive.preload,
      ),
    );
    _rawEventsController.add(
      '** STS policy stored for ${network.host} (${durationSeconds}s)',
    );
  }

  Future<void> _deleteStsPolicy(String host) async {
    await _stsPolicyStore.deletePolicy(host);
    _rawEventsController.add('** STS policy cleared for $host');
  }

  int? _capSubcommandIndex(List<String> params) {
    for (var index = 0; index < params.length; index += 1) {
      if (_capSubcommands.contains(params[index].toUpperCase())) {
        return index;
      }
    }
    return null;
  }

  String _capabilitySource(List<String> rest, String trailing) {
    return [
      ...rest.where((item) => item != '*'),
      if (trailing.isNotEmpty) trailing,
    ].join(' ');
  }

  bool _capHasMoreLines(List<String> rest) {
    return rest.contains('*');
  }

  void _storeAvailableCapabilityTokens(String source) {
    for (final token in parseIrcCapabilityTokens(source)) {
      _capAvailable.add(token.name);
      if (token.value != null) {
        _capValues[token.name] = token.value!;
      }
      if (token.name == 'sts') {
        _handleStsCapability(token.value);
      }
    }
  }

  void _storeEnabledCapabilityTokens(
    String source, {
    bool allowDisablePrefix = false,
  }) {
    for (final token in parseIrcCapabilityTokens(
      source,
      allowDisablePrefix: allowDisablePrefix,
    )) {
      if (token.disabled) {
        _capEnabled.remove(token.name);
        continue;
      }
      _capEnabled.add(token.name);
      if (token.value != null) {
        _capValues[token.name] = token.value!;
      }
      if (token.name == 'sts') {
        _handleStsCapability(token.value);
      }
    }
  }

  void _requestAvailableCapabilities() {
    final requested = _selectCapabilitiesToRequest();
    _updateSaslStatusForSelectedCapabilities(requested);
    if (requested.isEmpty) {
      unawaited(_endCapNegotiation());
      return;
    }

    _capRequested.addAll(requested);
    unawaited(_sendCapReqBatches(requested));
  }

  void _updateSaslStatusForSelectedCapabilities(List<String> requested) {
    if (!_shouldUseSasl(_network)) {
      _saslAuthStatus = SaslAuthStatus.notConfigured;
      return;
    }

    if (requested.contains('sasl')) {
      _saslAuthStatus = SaslAuthStatus.requested;
      return;
    }

    if (!_capAvailable.contains('sasl')) {
      _saslAuthStatus = SaslAuthStatus.unavailable;
      _rawEventsController.add(
        '** SASL unavailable: server did not advertise sasl capability',
      );
      return;
    }

    _saslAuthStatus = SaslAuthStatus.mechanismUnavailable;
    final mechanism = _saslMechanismName(
      _network?.saslMechanism ?? SaslMechanism.plain,
    );
    _rawEventsController.add(
      '** SASL unavailable: server does not advertise $mechanism',
    );
  }

  List<String> _selectCapabilitiesToRequest() {
    final requested = <String>{
      if (_shouldRequestSaslCapability(_network)) 'sasl',
      ..._preferredCapabilities.where(
        (capability) =>
            _capAvailable.contains(capability) &&
            !_capEnabled.contains(capability),
      ),
    };
    return requested.toList(growable: false);
  }

  Set<String> _capabilityRequestNames(List<String> capabilities) {
    return capabilities
        .map((capability) {
          final name = capability.split('=').first.trim();
          return name.startsWith('-') ? name.substring(1) : name;
        })
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  Future<void> _sendCapReqBatches(List<String> capabilities) async {
    for (final batch in _splitCapReqBatches(capabilities)) {
      await sendRaw('CAP REQ :${batch.join(' ')}');
    }
  }

  List<List<String>> _splitCapReqBatches(List<String> capabilities) {
    final batches = <List<String>>[];
    var current = <String>[];

    for (final capability in capabilities) {
      final candidate = <String>[...current, capability];
      final candidateLine = 'CAP REQ :${candidate.join(' ')}';
      if (current.isNotEmpty && candidateLine.length > _maxCapReqLineLength) {
        batches.add(current);
        current = <String>[capability];
      } else {
        current = candidate;
      }
    }

    if (current.isNotEmpty) {
      batches.add(current);
    }
    return batches;
  }

  void _handleCapAck(String source) {
    var shouldStartSasl = false;
    SaslMechanism? saslMechanism;
    final ackedNames = <String>{};
    final disabledNames = <String>{};

    for (final token in parseIrcCapabilityTokens(
      source,
      allowDisablePrefix: true,
    )) {
      final wasRequested = _capRequested.remove(token.name);
      if (token.disabled) {
        _capEnabled.remove(token.name);
        disabledNames.add(token.name);
        continue;
      }

      _capEnabled.add(token.name);
      ackedNames.add(token.name);
      if (token.value != null) {
        _capValues[token.name] = token.value!;
      }

      if (token.name == 'sasl' && wasRequested && _shouldUseSasl(_network)) {
        shouldStartSasl = true;
        saslMechanism = _network?.saslMechanism ?? SaslMechanism.plain;
      }
    }

    if (ackedNames.contains('draft/extended-isupport')) {
      unawaited(sendRaw('ISUPPORT'));
    }

    if (disabledNames.isNotEmpty) {
      _rawEventsController.add(
        '** CAP disabled: ${disabledNames.toList(growable: false)..sort()}',
      );
    }

    if (shouldStartSasl && saslMechanism != null) {
      _startSaslAuthentication(saslMechanism);
      return;
    }

    if (_saslInProgress || _capRequested.isNotEmpty) {
      return;
    }

    unawaited(_endCapNegotiation());
  }

  void _handleCapNew(String source) {
    final names = <String>{};
    var saslAdvertised = false;
    for (final token in parseIrcCapabilityTokens(source)) {
      _capAvailable.add(token.name);
      if (token.value != null) {
        _capValues[token.name] = token.value!;
      }
      names.add(token.name);
      if (token.name == 'sasl') {
        saslAdvertised = true;
      }
      if (token.name == 'sts') {
        _handleStsCapability(token.value);
      }
    }

    if (names.isNotEmpty) {
      _rawEventsController.add(
        '** CAP NEW: ${names.toList(growable: false)..sort()}',
      );
    }

    if (_stsUpgradeInProgress) {
      return;
    }

    if (saslAdvertised &&
        !_capEnabled.contains('sasl') &&
        !_capRequested.contains('sasl') &&
        !_saslInProgress &&
        _shouldRequestSaslCapability(_network)) {
      _capNegotiationActive = true;
      _capEnded = false;
      _capRequested.add('sasl');
      unawaited(sendRaw('CAP REQ :sasl'));
    }
  }

  void _handleCapDel(String source) {
    final names = parseIrcCapabilityNames(source);
    final removedNames = <String>{};
    for (final name in names) {
      if (name == 'sts') {
        _rawEventsController.add('** CAP DEL ignored for STS policy');
        continue;
      }
      _capAvailable.remove(name);
      _capEnabled.remove(name);
      _capRequested.remove(name);
      _capValues.remove(name);
      removedNames.add(name);
    }

    if (removedNames.isNotEmpty) {
      _rawEventsController.add(
        '** CAP DEL: ${removedNames.toList(growable: false)..sort()}',
      );
    }
  }

  void _handleCapNak(String source) {
    final names = parseIrcCapabilityNames(source, allowDisablePrefix: true);
    for (final name in names) {
      _capRequested.remove(name);
    }
    if (names.contains('sasl') && _shouldUseSasl(_network)) {
      _saslAuthStatus = SaslAuthStatus.failed;
    }

    if (names.isNotEmpty) {
      _rawEventsController.add(
        '** CAP NAK: server rejected ${names.toList(growable: false)..sort()}',
      );
    } else {
      _rawEventsController.add(
        '** CAP NAK: server rejected capability request',
      );
    }

    if (_saslInProgress || _capRequested.isNotEmpty) {
      return;
    }

    unawaited(_endCapNegotiation());
  }

  void _startSaslAuthentication(SaslMechanism mechanism) {
    _saslInProgress = true;
    _saslAuthStatus = SaslAuthStatus.authenticating;
    _activeSaslMechanism = mechanism;
    _updateState(
      ConnectionSnapshot(
        networkId: _state.networkId,
        phase: ConnectionPhase.authenticating,
        message: 'Authenticating with SASL ${_saslMechanismName(mechanism)}.',
      ),
    );
    switch (mechanism) {
      case SaslMechanism.scramSha256:
        final network = _network;
        if (network != null) {
          _scramSession = ScramSha256Session(
            username: network.saslAccount!,
            password: network.saslPassword!,
            nonceGenerator: _scramNonceGenerator,
          );
        }
        unawaited(sendRaw('AUTHENTICATE SCRAM-SHA-256'));
        break;
      case SaslMechanism.external:
        unawaited(sendRaw('AUTHENTICATE EXTERNAL'));
        break;
      case SaslMechanism.plain:
        unawaited(sendRaw('AUTHENTICATE PLAIN'));
        break;
    }
  }

  bool _shouldRequestSaslCapability(NetworkConfig? network) {
    if (!_capAvailable.contains('sasl') || !_shouldUseSasl(network)) {
      return false;
    }

    final advertisedValue = _capValues['sasl'];
    if (advertisedValue == null) {
      return true;
    }

    final mechanisms = parseIrcCapabilityValueList(advertisedValue);
    if (mechanisms.isEmpty) {
      return false;
    }

    final mechanism = network?.saslMechanism ?? SaslMechanism.plain;
    return mechanisms.contains(_saslMechanismName(mechanism));
  }

  void _handleAuthenticate(IrcMessageFrame frame) {
    if (!_saslInProgress) {
      return;
    }

    final payload = frame.params.isNotEmpty
        ? frame.params.first
        : frame.trailing;
    final network = _network;
    if (network == null) {
      return;
    }

    final mechanism = _activeSaslMechanism ?? network.saslMechanism;
    if (mechanism == SaslMechanism.scramSha256) {
      _handleScramAuthenticate(payload);
      return;
    }

    if (mechanism == SaslMechanism.external) {
      if (payload == '+') {
        unawaited(sendRaw('AUTHENTICATE +'));
      }
      return;
    }

    if (payload != '+') {
      return;
    }

    final account = network.saslAccount;
    final password = network.saslPassword;
    if ((account ?? '').isEmpty || (password ?? '').isEmpty) {
      return;
    }

    final auth = base64.encode(
      utf8.encode('$account\u0000$account\u0000$password'),
    );
    _sendAuthenticateEncoded(auth);
  }

  void _handleScramAuthenticate(String? payload) {
    final session = _scramSession;
    if (session == null || payload == null) {
      return;
    }

    try {
      if (payload == '+') {
        final clientFirst = session.createClientFirstMessage();
        _sendAuthenticatePayload(clientFirst);
        return;
      }

      final decoded = utf8.decode(base64.decode(payload));
      if (!_scramAwaitingServerFinal) {
        final clientFinal = session.createClientFinalMessage(decoded);
        _scramAwaitingServerFinal = true;
        _sendAuthenticatePayload(clientFinal);
        return;
      }

      if (!session.validateServerFinalMessage(decoded)) {
        _rawEventsController.add('** SASL SCRAM verification failed');
        unawaited(_abortSasl());
        return;
      }

      _rawEventsController.add('** SASL SCRAM server signature verified');
    } on FormatException catch (error) {
      _rawEventsController.add('** SASL SCRAM error: ${error.message}');
      unawaited(_abortSasl());
    }
  }

  void _sendAuthenticatePayload(String message) {
    final encoded = base64.encode(utf8.encode(message));
    _sendAuthenticateEncoded(encoded);
  }

  void _sendAuthenticateEncoded(String encoded) {
    if (encoded.isEmpty) {
      unawaited(sendRaw('AUTHENTICATE +'));
      return;
    }

    final chunks = <String>[];
    for (var i = 0; i < encoded.length; i += 400) {
      chunks.add(
        encoded.substring(
          i,
          i + 400 > encoded.length ? encoded.length : i + 400,
        ),
      );
    }

    for (final chunk in chunks) {
      unawaited(sendRaw('AUTHENTICATE $chunk'));
    }
    if (encoded.length % 400 == 0) {
      unawaited(sendRaw('AUTHENTICATE +'));
    }
  }

  Future<void> _abortSasl() async {
    _saslInProgress = false;
    _saslAuthStatus = SaslAuthStatus.aborted;
    _activeSaslMechanism = null;
    _scramSession = null;
    _scramAwaitingServerFinal = false;
    await sendRaw('AUTHENTICATE *');
    await _endCapNegotiation();
  }

  Future<void> _endCapNegotiation() async {
    if (_capEnded || !_capNegotiationActive) {
      return;
    }

    _capEnded = true;
    _activeSaslMechanism = null;
    _scramSession = null;
    _scramAwaitingServerFinal = false;
    await sendRaw('CAP END');
  }

  bool _shouldUseSasl(NetworkConfig? network) {
    if (network == null) {
      return false;
    }

    switch (network.saslMechanism) {
      case SaslMechanism.external:
        return true;
      case SaslMechanism.plain:
      case SaslMechanism.scramSha256:
        return (network.saslAccount ?? '').isNotEmpty &&
            (network.saslPassword ?? '').isNotEmpty;
    }
  }

  void _handleTransportDone() {
    if (_isDisposed) {
      return;
    }
    unawaited(_rescheduleStsPolicyOnDisconnect());
    _transport = null;
    _linesSubscription = null;
    _pendingLabels.clear();
    _updateState(
      ConnectionSnapshot(
        networkId: _state.networkId,
        phase: ConnectionPhase.disconnected,
        message: 'Server closed the connection.',
      ),
    );
  }

  void _handleTransportError(Object error, StackTrace stackTrace) {
    if (_isDisposed) {
      return;
    }
    _pendingLabels.clear();
    unawaited(_cleanupTransport());
    _updateState(
      ConnectionSnapshot(
        networkId: _state.networkId,
        phase: ConnectionPhase.error,
        message: error.toString(),
      ),
    );
  }

  void _updateState(ConnectionSnapshot snapshot) {
    if (_isDisposed || _stateController.isClosed) {
      return;
    }
    _state = snapshot;
    _stateController.add(snapshot);
  }

  bool _isConnectionActive(ConnectionPhase phase) {
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

  bool _isCurrentConnect(int generation, String networkId) {
    return !_isDisposed &&
        generation == _connectGeneration &&
        _state.networkId == networkId &&
        _state.phase != ConnectionPhase.disconnecting &&
        _state.phase != ConnectionPhase.disconnected;
  }

  Future<void> _cleanupTransport({bool rescheduleStsPolicy = true}) async {
    final subscription = _linesSubscription;
    final transport = _transport;
    if (rescheduleStsPolicy) {
      await _rescheduleStsPolicyOnDisconnect();
    }
    _linesSubscription = null;
    _transport = null;
    await subscription?.cancel();
    await transport?.close();
  }

  Future<void> _rescheduleStsPolicyOnDisconnect() async {
    final network = _network;
    if (network == null || !network.useTls) {
      return;
    }

    final policy = await _stsPolicyStore.loadPolicy(network.host);
    if (policy == null) {
      return;
    }

    final now = _now().toUtc();
    if (!policy.isActive(now)) {
      await _stsPolicyStore.deletePolicy(network.host);
      return;
    }

    await _stsPolicyStore.savePolicy(policy.reschedule(now));
  }

  void _emitRawEvent(String event) {
    if (!_isDisposed && !_rawEventsController.isClosed) {
      _rawEventsController.add(event);
    }
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _connectGeneration += 1;
    unawaited(_cleanupTransport());
    _labeledResponsesController.close();
    _rawEventsController.close();
    _framesController.close();
    _stateController.close();
  }

  String? _firstOrNull(List<String> items) {
    if (items.isEmpty) {
      return null;
    }

    return items.first;
  }

  Future<void> _sendNick(String nick) async {
    _currentNick = nick;
    await sendRaw('NICK $nick');
  }

  String _resolveAltNickBase(NetworkConfig network) {
    final explicit = (network.altNickname ?? '').trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }

    final primary = network.nickname.trim();
    return primary.isEmpty ? 'AndroidIRCX_' : '${primary}_';
  }

  void _handleNicknameCollision(IrcMessageFrame frame) {
    final nextNick = _nextNickCandidate();
    if (nextNick == null) {
      return;
    }

    _rawEventsController.add('** Nickname in use, trying $nextNick');
    _updateState(
      ConnectionSnapshot(
        networkId: _state.networkId,
        phase: ConnectionPhase.connecting,
        message: 'Nickname in use, trying $nextNick',
      ),
    );
    unawaited(_sendNick(nextNick));
  }

  String? _nextNickCandidate() {
    final primary = (_primaryNick ?? '').trim();
    final altBase = (_altNickBase ?? '').trim();
    if (primary.isEmpty || altBase.isEmpty) {
      return null;
    }

    if (_currentNick == primary) {
      return altBase;
    }

    if (_currentNick == altBase) {
      _altNickAttempt = 1;
      return '$altBase$_altNickAttempt';
    }

    _altNickAttempt += 1;
    return '$altBase$_altNickAttempt';
  }

  String _saslFailureMessage(IrcMessageFrame frame) {
    final reason = (frame.trailing ?? '').trim();
    final safeReason = reason.isEmpty ? '' : ': $reason';
    return '** SASL authentication failed (${frame.command})$safeReason';
  }

  String _saslMechanismName(SaslMechanism mechanism) {
    return switch (mechanism) {
      SaslMechanism.plain => 'PLAIN',
      SaslMechanism.scramSha256 => 'SCRAM-SHA-256',
      SaslMechanism.external => 'EXTERNAL',
    };
  }

  void _handleLabeledResponse(IrcMessageFrame frame) {
    final label = frame.tags['label'];
    if (label == null || label.isEmpty) {
      return;
    }

    final command = _pendingLabels.remove(label);
    if (command == null) {
      _rawEventsController.add('** Labeled response for unknown label: $label');
      return;
    }

    _rawEventsController.add('** Labeled response matched: $label ($command)');
    _labeledResponsesController.add((
      label: label,
      command: command,
      frame: frame,
    ));
  }
}

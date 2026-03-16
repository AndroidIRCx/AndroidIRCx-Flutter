import 'dart:async';
import 'dart:convert';

import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/parser/irc_message_parser.dart';
import 'package:androidircx/irc/sasl/scram_sha256_session.dart';
import 'package:androidircx/irc/services/irc_transport.dart';

typedef IrcTransportConnector = Future<IrcTransport> Function(NetworkConfig network);

class IrcService {
  IrcService({
    IrcTransportConnector? transportConnector,
    String Function()? scramNonceGenerator,
  })  : _transportConnector = transportConnector ?? defaultIrcTransportConnector,
        _scramNonceGenerator = scramNonceGenerator,
        _state = const ConnectionSnapshot(
          networkId: '',
          phase: ConnectionPhase.idle,
        );

  final IrcTransportConnector _transportConnector;
  final String Function()? _scramNonceGenerator;
  final StreamController<String> _rawEventsController =
      StreamController<String>.broadcast();
  final StreamController<IrcMessageFrame> _framesController =
      StreamController<IrcMessageFrame>.broadcast();
  final StreamController<ConnectionSnapshot> _stateController =
      StreamController<ConnectionSnapshot>.broadcast();

  IrcTransport? _transport;
  StreamSubscription<String>? _linesSubscription;
  ConnectionSnapshot _state;
  String? _currentNick;
  final Set<String> _capAvailable = <String>{};
  final Set<String> _capEnabled = <String>{};
  bool _capNegotiationActive = false;
  bool _capEnded = false;
  bool _saslInProgress = false;
  SaslMechanism? _activeSaslMechanism;
  NetworkConfig? _network;
  String? _primaryNick;
  String? _altNickBase;
  int _altNickAttempt = 0;
  ScramSha256Session? _scramSession;
  bool _scramAwaitingServerFinal = false;

  ConnectionSnapshot get state => _state;
  String? get currentNick => _currentNick;
  Set<String> get enabledCapabilities => Set<String>.unmodifiable(_capEnabled);
  Set<String> get availableCapabilities => Set<String>.unmodifiable(_capAvailable);
  Stream<String> get rawEvents => _rawEventsController.stream;
  Stream<IrcMessageFrame> get frames => _framesController.stream;
  Stream<ConnectionSnapshot> get stateStream => _stateController.stream;

  Future<void> connect(NetworkConfig network) async {
    if (_state.phase == ConnectionPhase.connecting ||
        _state.phase == ConnectionPhase.connected) {
      return;
    }

    _primaryNick = network.nickname.trim();
    _altNickBase = _resolveAltNickBase(network);
    _altNickAttempt = 0;
    _currentNick = _primaryNick;
    _network = network;
    _capAvailable.clear();
    _capEnabled.clear();
    _capNegotiationActive = false;
    _capEnded = false;
    _saslInProgress = false;
    _activeSaslMechanism = null;
    _scramSession = null;
    _scramAwaitingServerFinal = false;
    _updateState(
      ConnectionSnapshot(
        networkId: network.id,
        phase: ConnectionPhase.connecting,
        message: 'Opening socket to ${network.host}:${network.port}',
      ),
    );

    try {
      _transport = await _transportConnector(network);
      _linesSubscription = _transport!.lines.listen(
        _handleIncomingLine,
        onError: _handleTransportError,
        onDone: _handleTransportDone,
      );

      if (_shouldUseSasl(network)) {
        _capNegotiationActive = true;
        await sendRaw('CAP LS 302');
      }
      if ((network.password ?? '').isNotEmpty) {
        await sendRaw('PASS ${network.password}');
      }
      await _sendNick(_primaryNick!);
      await sendRaw('USER ${network.username} 0 * :${network.realName}');
    } catch (error) {
      _updateState(
        ConnectionSnapshot(
          networkId: network.id,
          phase: ConnectionPhase.error,
          message: error.toString(),
        ),
      );
    }
  }

  Future<void> disconnect([String? reason]) async {
    if (_state.networkId.isEmpty) {
      return;
    }

    _updateState(_state.copyWith(phase: ConnectionPhase.disconnecting));
    try {
      if (_transport != null) {
        await sendRaw('QUIT :${reason ?? 'Client disconnected'}');
      }
    } catch (_) {
      // Best effort quit.
    }

    await _linesSubscription?.cancel();
    _linesSubscription = null;
    await _transport?.close();
    _transport = null;

    _updateState(
      const ConnectionSnapshot(
        networkId: '',
        phase: ConnectionPhase.disconnected,
        message: 'Disconnected.',
      ),
    );
  }

  Future<void> sendRaw(String line) async {
    final transport = _transport;
    if (transport == null) {
      return;
    }

    _rawEventsController.add('>> $line');
    await transport.sendLine(line);
  }

  Future<void> joinChannel(String channel) async {
    await sendRaw('JOIN $channel');
  }

  Future<void> sendPrivmsg({
    required String target,
    required String text,
  }) async {
    await sendRaw('PRIVMSG $target :$text');
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

  Future<void> sendTopic({
    required String channel,
    String? topic,
  }) async {
    if ((topic ?? '').trim().isEmpty) {
      await sendRaw('TOPIC $channel');
      return;
    }

    await sendRaw('TOPIC $channel :$topic');
  }

  Future<void> sendMode(String args) async {
    await sendRaw('MODE $args');
  }

  Future<void> sendCapLs() async {
    await sendRaw('CAP LS 302');
  }

  Future<void> sendCapList() async {
    await sendRaw('CAP LIST');
  }

  Future<void> sendCapReq(String capabilities) async {
    await sendRaw('CAP REQ :$capabilities');
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
    await sendRaw('PRIVMSG $target :\u0001ACTION $text\u0001');
  }

  void _handleIncomingLine(String line) {
    _rawEventsController.add('<< $line');
    final frame = parseIrcMessage(line);
    _framesController.add(frame);

    if (frame.command == 'PING') {
      final payload = frame.trailing ?? (frame.params.isNotEmpty ? frame.params.last : '');
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

    if (frame.command == '903') {
      _saslInProgress = false;
      _activeSaslMechanism = null;
      _scramSession = null;
      _scramAwaitingServerFinal = false;
      _rawEventsController.add('** SASL authentication successful');
      unawaited(_endCapNegotiation());
      return;
    }

    if (frame.command == '904' ||
        frame.command == '905' ||
        frame.command == '906' ||
        frame.command == '907') {
      _saslInProgress = false;
      _activeSaslMechanism = null;
      _scramSession = null;
      _scramAwaitingServerFinal = false;
      _rawEventsController.add('** SASL authentication failed');
      unawaited(_endCapNegotiation());
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
      if (senderNick != null && senderNick == _currentNick && nextNick != null) {
        _currentNick = nextNick;
      }
    }

    if (frame.command == '433' || frame.command == '436') {
      _handleNicknameCollision(frame);
    }
  }

  void _handleCap(IrcMessageFrame frame) {
    final params = frame.params;
    if (params.length < 2) {
      return;
    }

    final subcommandIndex = params.first == '*' ? 1 : 0;
    if (subcommandIndex >= params.length) {
      return;
    }

    final subcommand = params[subcommandIndex].toUpperCase();
    final rest = params.skip(subcommandIndex + 1).toList(growable: false);
    final trailing = frame.trailing ?? '';

    switch (subcommand) {
      case 'LS':
        final capabilities = [
          ...rest.where((item) => item != '*'),
          if (trailing.isNotEmpty) trailing,
        ].join(' ');
        _capAvailable.addAll(_parseCapabilityNames(capabilities));
        final isLast = !rest.contains('*');
        if (isLast) {
          if (_capAvailable.contains('sasl') && _shouldUseSasl(_network)) {
            unawaited(sendRaw('CAP REQ :sasl'));
          } else {
            unawaited(_endCapNegotiation());
          }
        }
      case 'ACK':
        final ackSource = [...rest, if (trailing.isNotEmpty) trailing].join(' ');
        _capEnabled.addAll(_parseCapabilityNames(ackSource));
        if (_capEnabled.contains('sasl') && _shouldUseSasl(_network)) {
          _saslInProgress = true;
          final mechanism = _network?.saslMechanism ?? SaslMechanism.plain;
          _activeSaslMechanism = mechanism;
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
        } else {
          unawaited(_endCapNegotiation());
        }
      case 'NEW':
        final newCaps = [...rest, if (trailing.isNotEmpty) trailing].join(' ');
        final names = _parseCapabilityNames(newCaps);
        _capAvailable.addAll(names);
        if (names.isNotEmpty) {
          _rawEventsController.add(
            '** CAP NEW: ${names.toList(growable: false)..sort()}',
          );
        }
      case 'DEL':
        final removedCaps = [...rest, if (trailing.isNotEmpty) trailing].join(' ');
        final names = _parseCapabilityNames(removedCaps);
        for (final name in names) {
          _capAvailable.remove(name);
          _capEnabled.remove(name);
        }
        if (names.isNotEmpty) {
          _rawEventsController.add(
            '** CAP DEL: ${names.toList(growable: false)..sort()}',
          );
        }
      case 'NAK':
        unawaited(_endCapNegotiation());
      default:
        break;
    }
  }

  void _handleAuthenticate(IrcMessageFrame frame) {
    if (!_saslInProgress) {
      return;
    }

    final payload = frame.params.isNotEmpty ? frame.params.first : frame.trailing;
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

    final auth = base64.encode(utf8.encode('$account\u0000$account\u0000$password'));
    final chunks = <String>[];
    for (var i = 0; i < auth.length; i += 400) {
      chunks.add(auth.substring(i, i + 400 > auth.length ? auth.length : i + 400));
    }

    for (final chunk in chunks) {
      unawaited(sendRaw('AUTHENTICATE $chunk'));
    }
    if (auth.length % 400 == 0) {
      unawaited(sendRaw('AUTHENTICATE +'));
    }
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
    final chunks = <String>[];
    for (var i = 0; i < encoded.length; i += 400) {
      chunks.add(
        encoded.substring(i, i + 400 > encoded.length ? encoded.length : i + 400),
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
    _transport = null;
    _updateState(
      ConnectionSnapshot(
        networkId: _state.networkId,
        phase: ConnectionPhase.disconnected,
        message: 'Server closed the connection.',
      ),
    );
  }

  void _handleTransportError(Object error, StackTrace stackTrace) {
    _updateState(
      ConnectionSnapshot(
        networkId: _state.networkId,
        phase: ConnectionPhase.error,
        message: error.toString(),
      ),
    );
  }

  void _updateState(ConnectionSnapshot snapshot) {
    _state = snapshot;
    _stateController.add(snapshot);
  }

  void dispose() {
    _linesSubscription?.cancel();
    _transport?.close();
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

  Set<String> _parseCapabilityNames(String source) {
    final names = <String>{};
    for (final cap in source.split(RegExp(r'\s+'))) {
      final name = cap.split('=').first.trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    return names;
  }
}

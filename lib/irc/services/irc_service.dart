import 'dart:async';

import 'package:androidircx/core/models/connection_state.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/parser/irc_message_parser.dart';
import 'package:androidircx/irc/services/irc_transport.dart';

typedef IrcTransportConnector = Future<IrcTransport> Function(NetworkConfig network);

class IrcService {
  IrcService({
    IrcTransportConnector? transportConnector,
  })  : _transportConnector = transportConnector ?? SocketIrcTransport.connect,
        _state = const ConnectionSnapshot(
          networkId: '',
          phase: ConnectionPhase.idle,
        );

  final IrcTransportConnector _transportConnector;
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

  ConnectionSnapshot get state => _state;
  String? get currentNick => _currentNick;
  Stream<String> get rawEvents => _rawEventsController.stream;
  Stream<IrcMessageFrame> get frames => _framesController.stream;
  Stream<ConnectionSnapshot> get stateStream => _stateController.stream;

  Future<void> connect(NetworkConfig network) async {
    if (_state.phase == ConnectionPhase.connecting ||
        _state.phase == ConnectionPhase.connected) {
      return;
    }

    _currentNick = network.nickname;
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

      if ((network.password ?? '').isNotEmpty) {
        await sendRaw('PASS ${network.password}');
      }
      await sendRaw('NICK ${network.nickname}');
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

    if (frame.command == '001') {
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
}

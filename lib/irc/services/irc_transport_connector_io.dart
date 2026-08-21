import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/security/certificate_store.dart';
import 'package:androidircx/irc/services/irc_transport.dart';

Future<IrcTransport> connectDefaultTransport(
  NetworkConfig network, {
  ClientCertificate? clientCertificate,
}) {
  final context = (clientCertificate != null && network.useTls)
      ? buildClientSecurityContext(clientCertificate)
      : null;
  return SocketIrcTransport.connect(network, securityContext: context);
}

/// Builds a [SecurityContext] presenting [certificate] as the client cert for
/// SASL EXTERNAL / CertFP.
SecurityContext buildClientSecurityContext(ClientCertificate certificate) {
  final context = SecurityContext(withTrustedRoots: true);
  if (certificate.isPkcs12) {
    // Dart's SecurityContext parses PKCS#12 natively for both the certificate
    // chain and the private key, using the import password.
    final bytes = base64.decode(
      certificate.pkcs12Base64!.replaceAll(RegExp(r'\s'), ''),
    );
    context.useCertificateChainBytes(
      bytes,
      password: certificate.privateKeyPassphrase,
    );
    context.usePrivateKeyBytes(
      bytes,
      password: certificate.privateKeyPassphrase,
    );
    return context;
  }
  context.useCertificateChainBytes(utf8.encode(certificate.certificatePem));
  context.usePrivateKeyBytes(
    utf8.encode(certificate.privateKeyPem),
    password: certificate.privateKeyPassphrase,
  );
  return context;
}

class SocketIrcTransport implements IrcTransport {
  SocketIrcTransport._(
    this._socket, {
    StreamSubscription<Uint8List>? subscription,
    List<int> initialData = const <int>[],
  }) {
    _byteController = StreamController<List<int>>();
    lines = _byteController.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.isNotEmpty)
        .asBroadcastStream();

    if (initialData.isNotEmpty) {
      _byteController.add(Uint8List.fromList(initialData));
    }

    _subscription = subscription ?? _socket.listen(null);
    _subscription
      ..onData(_byteController.add)
      ..onError(_byteController.addError)
      ..onDone(() {
        if (!_byteController.isClosed) {
          _byteController.close();
        }
      });
    _subscription.resume();
  }

  final Socket _socket;
  late final StreamController<List<int>> _byteController;
  late final StreamSubscription<Uint8List> _subscription;

  @override
  late final Stream<String> lines;

  static Future<SocketIrcTransport> connect(
    NetworkConfig network, {
    SecurityContext? securityContext,
  }) async {
    if (network.proxyType == IrcProxyType.socks5) {
      return _connectSocks5(network);
    }
    final socket = await _connectDirect(
      network,
      securityContext: securityContext,
    );
    return SocketIrcTransport._(socket);
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    if (!_byteController.isClosed) {
      await _byteController.close();
    }
    _socket.destroy();
  }

  @override
  Future<void> sendLine(String line) async {
    _socket.write('$line\r\n');
    await _socket.flush();
  }

  static Future<Socket> _connectDirect(
    NetworkConfig network, {
    SecurityContext? securityContext,
  }) {
    if (network.useTls) {
      return SecureSocket.connect(
        network.host,
        network.port,
        context: securityContext,
      );
    }
    return Socket.connect(network.host, network.port);
  }

  static Future<SocketIrcTransport> _connectSocks5(
    NetworkConfig network,
  ) async {
    final proxyHost = (network.proxyHost ?? '').trim();
    final proxyPort = network.proxyPort;
    if (proxyHost.isEmpty || proxyPort == null) {
      throw const SocketException(
        'SOCKS5 proxy requires host and port settings.',
      );
    }

    final socket = await Socket.connect(proxyHost, proxyPort);
    final reader = _SocketHandshakeReader(socket);
    try {
      await _negotiateSocks5(network, reader);
      final remainingData = reader.takeBufferedData();
      if (network.useTls) {
        reader.pauseSubscription();
        final secureSocket = await SecureSocket.secure(
          socket,
          host: network.host,
        );
        return SocketIrcTransport._(secureSocket);
      }

      final subscription = reader.takeSubscription();
      return SocketIrcTransport._(
        socket,
        subscription: subscription,
        initialData: remainingData,
      );
    } catch (_) {
      await reader.cancel();
      socket.destroy();
      rethrow;
    }
  }

  static Future<void> _negotiateSocks5(
    NetworkConfig network,
    _SocketHandshakeReader reader,
  ) async {
    final username = (network.proxyUsername ?? '').trim();
    final password = network.proxyPassword ?? '';
    final hasCredentials = username.isNotEmpty || password.isNotEmpty;
    final methods = hasCredentials
        ? const <int>[0x00, 0x02]
        : const <int>[0x00];

    await reader.writeAll(<int>[0x05, methods.length, ...methods]);
    final methodResponse = await reader.readExactly(2);
    if (methodResponse[0] != 0x05) {
      throw const SocketException('Invalid SOCKS5 proxy greeting.');
    }
    if (methodResponse[1] == 0xff) {
      throw const SocketException('SOCKS5 proxy rejected auth methods.');
    }

    if (methodResponse[1] == 0x02) {
      await _authenticateSocks5(username, password, reader);
    }

    final hostBytes = ascii.encode(network.host);
    if (hostBytes.length > 255) {
      throw const SocketException('SOCKS5 host name is too long.');
    }
    await reader.writeAll(<int>[
      0x05,
      0x01,
      0x00,
      0x03,
      hostBytes.length,
      ...hostBytes,
      (network.port >> 8) & 0xff,
      network.port & 0xff,
    ]);

    final responseHeader = await reader.readExactly(4);
    if (responseHeader[0] != 0x05) {
      throw const SocketException('Invalid SOCKS5 connect response.');
    }
    if (responseHeader[1] != 0x00) {
      throw SocketException(
        'SOCKS5 proxy connect failed: ${_socks5ReplyName(responseHeader[1])}.',
      );
    }

    final addressLength = switch (responseHeader[3]) {
      0x01 => 4,
      0x03 => (await reader.readExactly(1)).first,
      0x04 => 16,
      _ => throw const SocketException(
        'SOCKS5 proxy returned an unknown address type.',
      ),
    };
    if (addressLength > 0) {
      await reader.readExactly(addressLength);
    }
    await reader.readExactly(2);
  }

  static Future<void> _authenticateSocks5(
    String username,
    String password,
    _SocketHandshakeReader reader,
  ) async {
    final usernameBytes = utf8.encode(username);
    final passwordBytes = utf8.encode(password);
    if (usernameBytes.length > 255 || passwordBytes.length > 255) {
      throw const SocketException(
        'SOCKS5 username and password must be 255 bytes or shorter.',
      );
    }

    await reader.writeAll(<int>[
      0x01,
      usernameBytes.length,
      ...usernameBytes,
      passwordBytes.length,
      ...passwordBytes,
    ]);
    final response = await reader.readExactly(2);
    if (response[0] != 0x01 || response[1] != 0x00) {
      throw const SocketException('SOCKS5 username/password auth failed.');
    }
  }

  static String _socks5ReplyName(int code) {
    return switch (code) {
      0x01 => 'general failure',
      0x02 => 'connection not allowed',
      0x03 => 'network unreachable',
      0x04 => 'host unreachable',
      0x05 => 'connection refused',
      0x06 => 'TTL expired',
      0x07 => 'command not supported',
      0x08 => 'address type not supported',
      _ => 'error $code',
    };
  }
}

class _SocketHandshakeReader {
  _SocketHandshakeReader(this._socket) {
    _subscription = _socket.listen(
      _handleData,
      onError: (Object error, StackTrace stackTrace) {
        _error = error;
        _completeWaiters();
      },
      onDone: () {
        _isClosed = true;
        _completeWaiters();
      },
    );
  }

  final Socket _socket;
  final List<int> _buffer = <int>[];
  late final StreamSubscription<Uint8List> _subscription;
  Object? _error;
  bool _isClosed = false;
  Completer<void>? _readWaiter;

  Future<List<int>> readExactly(int count) async {
    while (_buffer.length < count) {
      final error = _error;
      if (error != null) {
        throw SocketException('SOCKS5 proxy read failed: $error');
      }
      if (_isClosed) {
        throw const SocketException('SOCKS5 proxy closed the connection.');
      }
      _readWaiter ??= Completer<void>();
      await _readWaiter!.future;
      _readWaiter = null;
    }

    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }

  Future<void> writeAll(List<int> bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  List<int> takeBufferedData() {
    final data = List<int>.unmodifiable(_buffer);
    _buffer.clear();
    return data;
  }

  StreamSubscription<Uint8List> takeSubscription() {
    _subscription.pause();
    return _subscription;
  }

  void pauseSubscription() {
    _subscription.pause();
  }

  Future<void> cancel() => _subscription.cancel();

  void _handleData(Uint8List data) {
    _buffer.addAll(data);
    _completeWaiters();
  }

  void _completeWaiters() {
    final waiter = _readWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }
}

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/security/certificate_store.dart';
import 'package:androidircx/irc/services/irc_transport_connector_stub.dart'
    if (dart.library.io) 'package:androidircx/irc/services/irc_transport_connector_io.dart'
    if (dart.library.js_interop) 'package:androidircx/irc/services/irc_transport_connector_web.dart'
    as transport_connector;

abstract class IrcTransport {
  Stream<String> get lines;
  Future<void> sendLine(String line);
  Future<void> close();
}

Future<IrcTransport> defaultIrcTransportConnector(
  NetworkConfig network, {
  ClientCertificate? clientCertificate,
}) {
  return transport_connector.connectDefaultTransport(
    network,
    clientCertificate: clientCertificate,
  );
}

Uri buildWebSocketUri(NetworkConfig network) {
  final scheme = network.useTls ? 'wss' : 'ws';
  final port = network.webSocketPort ?? network.port;
  final rawPath = (network.webSocketPath ?? '').trim();
  final normalizedPath = rawPath.isEmpty
      ? '/'
      : (rawPath.startsWith('/') ? rawPath : '/$rawPath');
  return Uri.parse('$scheme://${network.host}:$port$normalizedPath');
}

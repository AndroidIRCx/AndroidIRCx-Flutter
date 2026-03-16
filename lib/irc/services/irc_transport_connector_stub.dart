import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/irc/services/irc_transport.dart';

Future<IrcTransport> connectDefaultTransport(NetworkConfig network) {
  throw UnsupportedError(
    'No IRC transport is available for this platform: ${network.host}:${network.port}',
  );
}

import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/features/chat/application/session_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reuses existing session per network id', () {
    final registry = SessionRegistry();
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    final first = registry.obtainSession(network);
    final second = registry.obtainSession(network);

    expect(identical(first, second), isTrue);
    expect(registry.sessions, hasLength(1));

    registry.dispose();
  });

  test('closeSession removes controller from registry', () async {
    final registry = SessionRegistry();
    const network = NetworkConfig(
      id: 'dbase',
      name: 'DBase',
      host: 'irc.dbase.in.rs',
      port: 6697,
      nickname: 'AndroidIRCX',
      altNickname: 'AndroidIRCX_',
    );

    registry.obtainSession(network);
    await registry.closeSession(network.id);

    expect(registry.hasSession(network.id), isFalse);
    expect(registry.sessions, isEmpty);

    registry.dispose();
  });
}

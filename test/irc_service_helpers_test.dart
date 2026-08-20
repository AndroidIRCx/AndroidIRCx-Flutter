import 'package:androidircx/irc/models/irc_message_frame.dart';
import 'package:androidircx/irc/services/irc_service_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IRC service helpers', () {
    test('detects common service nicks and families from prefixes', () {
      const frame = IrcMessageFrame(
        raw: ':NickServ!services@anope.example NOTICE AndroidIRCX :identified',
        prefix: 'NickServ!services@anope.example',
        command: 'NOTICE',
        params: ['AndroidIRCX'],
        trailing: 'identified',
      );

      final detection = detectIrcService(frame);

      expect(detection, isNotNull);
      expect(detection!.kind, IrcServiceKind.nickServ);
      expect(detection.family, IrcServiceFamily.anope);
      expect(detection.isNickService, isTrue);
    });

    test('builds NickServ identify command with redacted logging text', () {
      final command = buildNickServIdentifyCommand(
        account: 'alice',
        password: 'secret-value',
      );

      expect(command.target, 'NickServ');
      expect(command.command, 'IDENTIFY alice secret-value');
      expect(command.redactedCommand, 'IDENTIFY alice [REDACTED]');
    });

    test('detects ZNC and soju compatibility signals from capabilities', () {
      final znc = detectBouncerCompatibility(
        availableCapabilities: {'znc.in/playback', 'batch'},
        enabledCapabilities: const <String>{},
        serverName: 'znc.example.test',
      );
      final soju = detectBouncerCompatibility(
        availableCapabilities: {'soju.im/bouncer-networks', 'chathistory'},
        enabledCapabilities: {'draft/read-marker'},
      );

      expect(znc.family, IrcBouncerFamily.znc);
      expect(znc.supportsPlayback, isTrue);
      expect(soju.family, IrcBouncerFamily.soju);
      expect(soju.supportsNetworkManagement, isTrue);
      expect(soju.supportsReadMarkers, isTrue);
    });
  });
}

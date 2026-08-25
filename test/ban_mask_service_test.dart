import 'package:androidircx/features/chat/application/ban_mask_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = BanMaskService();

  test('generates RN-compatible ban mask types', () {
    final expected = <int, String>{
      0: '*!john@irc.example.com',
      1: '*!*john@irc.example.com',
      2: '*!*@irc.example.com',
      3: '*!*john@*.example.com',
      4: '*!*@*.example.com',
      5: 'John!john@irc.example.com',
      6: 'John!*john@irc.example.com',
      7: 'John!*@irc.example.com',
      8: 'John!*john@*.example.com',
      9: 'John!*@*.example.com',
      10: 'John!*@*',
      11: '*!john@*',
    };

    for (final entry in expected.entries) {
      expect(
        service.generateBanMask(
          nick: 'John',
          ident: '~john',
          host: 'irc.example.com',
          type: entry.key,
        ),
        entry.value,
      );
    }
  });

  test('wildcards IP hosts for domain-style mask types', () {
    expect(
      service.generateBanMask(
        nick: 'John',
        ident: 'john',
        host: '192.168.1.55',
        type: 4,
      ),
      '*!*@192.168.1.*',
    );
  });

  test('falls back to host-only ban for unknown types', () {
    expect(
      service.generateBanMask(
        nick: 'John',
        ident: 'john',
        host: 'host.test',
        type: 99,
      ),
      '*!*@host.test',
    );
  });
}

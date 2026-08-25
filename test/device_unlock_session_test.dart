import 'dart:async';

import 'package:androidircx/core/security/device_unlock_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuses a recent successful unlock', () async {
    var now = DateTime(2026, 8, 24, 15);
    var calls = 0;
    final session = DeviceUnlockSession(
      reuseWindow: const Duration(minutes: 1),
      now: () => now,
      prompt: (_) async {
        calls++;
        return true;
      },
    );

    expect(await session.authenticate(reason: 'Unlock app'), isTrue);
    expect(await session.authenticate(reason: 'Unlock history'), isTrue);
    expect(calls, 1);

    now = now.add(const Duration(minutes: 2));
    expect(await session.authenticate(reason: 'Unlock history'), isTrue);
    expect(calls, 2);
  });

  test('coalesces concurrent unlock requests', () async {
    var calls = 0;
    final prompt = Completer<bool>();
    final session = DeviceUnlockSession(
      prompt: (_) {
        calls++;
        return prompt.future;
      },
    );

    final first = session.authenticate(reason: 'Unlock app');
    final second = session.authenticate(reason: 'Unlock history');
    expect(calls, 1);

    prompt.complete(true);
    expect(await first, isTrue);
    expect(await second, isTrue);
  });

  test('invalidate clears the cached unlock', () async {
    var calls = 0;
    final session = DeviceUnlockSession(
      prompt: (_) async {
        calls++;
        return true;
      },
    );

    expect(await session.authenticate(reason: 'Unlock app'), isTrue);
    session.invalidate();
    expect(await session.authenticate(reason: 'Unlock app'), isTrue);
    expect(calls, 2);
  });
}

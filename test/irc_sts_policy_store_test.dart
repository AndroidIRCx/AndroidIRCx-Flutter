import 'package:androidircx/irc/services/irc_sts_policy_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IrcStsPolicy', () {
    test('toJson/fromJson round-trips all fields', () {
      final policy = IrcStsPolicy(
        host: 'irc.example.com',
        port: 6697,
        durationSeconds: 3600,
        expiresAt: DateTime.utc(2030, 1, 1, 12),
        preload: true,
      );

      final restored = IrcStsPolicy.fromJson(policy.toJson());

      expect(restored.host, 'irc.example.com');
      expect(restored.port, 6697);
      expect(restored.durationSeconds, 3600);
      expect(restored.preload, isTrue);
      expect(restored.expiresAt.isAtSameMomentAs(policy.expiresAt), isTrue);
    });

    test('fromJson normalizes the host (trim + lowercase)', () {
      final restored = IrcStsPolicy.fromJson(<String, Object?>{
        'host': '  IRC.Example.COM  ',
        'port': 6697,
        'durationSeconds': 60,
        'expiresAt': DateTime.utc(2030).toIso8601String(),
      });

      expect(restored.host, 'irc.example.com');
      expect(restored.preload, isFalse); // defaults when absent
    });

    test('isActive reflects the expiry boundary', () {
      final now = DateTime.utc(2030, 6, 1, 12);
      final active = IrcStsPolicy(
        host: 'h',
        port: 6697,
        durationSeconds: 60,
        expiresAt: now.add(const Duration(seconds: 1)),
      );
      final expired = IrcStsPolicy(
        host: 'h',
        port: 6697,
        durationSeconds: 60,
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );

      expect(active.isActive(now), isTrue);
      expect(expired.isActive(now), isFalse);
    });

    test('reschedule sets expiresAt to now + durationSeconds', () {
      final now = DateTime.utc(2030, 6, 1, 12);
      final policy = IrcStsPolicy(
        host: 'h',
        port: 6697,
        durationSeconds: 120,
        expiresAt: now,
      );

      final rescheduled = policy.reschedule(now);

      expect(
        rescheduled.expiresAt.isAtSameMomentAs(
          now.add(const Duration(seconds: 120)),
        ),
        isTrue,
      );
    });
  });

  group('SharedPrefsIrcStsPolicyStore', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('save then load returns an equivalent policy, host-normalized', () async {
      final store = SharedPrefsIrcStsPolicyStore();
      final policy = IrcStsPolicy(
        host: 'IRC.Example.COM ',
        port: 6697,
        durationSeconds: 3600,
        expiresAt: DateTime.utc(2030, 1, 1),
        preload: true,
      );

      await store.savePolicy(policy);
      final loaded = await store.loadPolicy('irc.example.com');

      expect(loaded, isNotNull);
      expect(loaded!.host, 'irc.example.com');
      expect(loaded.port, 6697);
      expect(loaded.durationSeconds, 3600);
      expect(loaded.preload, isTrue);
      expect(loaded.expiresAt.isAtSameMomentAs(policy.expiresAt), isTrue);
    });

    test('corrupt stored JSON returns null and removes the key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'androidircx.irc.sts.bad.host': 'not-json{',
      });
      final store = SharedPrefsIrcStsPolicyStore();

      expect(await store.loadPolicy('bad.host'), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('androidircx.irc.sts.bad.host'), isNull);
    });

    test('deletePolicy removes a stored policy', () async {
      final store = SharedPrefsIrcStsPolicyStore();
      await store.savePolicy(
        IrcStsPolicy(
          host: 'irc.example.com',
          port: 6697,
          durationSeconds: 60,
          expiresAt: DateTime.utc(2030),
        ),
      );

      await store.deletePolicy('irc.example.com');

      expect(await store.loadPolicy('irc.example.com'), isNull);
    });

    test('missing policy loads as null', () async {
      final store = SharedPrefsIrcStsPolicyStore();
      expect(await store.loadPolicy('never.saved'), isNull);
    });
  });

  group('InMemoryIrcStsPolicyStore', () {
    test('saves, loads (host-normalized) and deletes', () async {
      final store = InMemoryIrcStsPolicyStore();
      await store.savePolicy(
        IrcStsPolicy(
          host: 'Irc.Example.Com',
          port: 6697,
          durationSeconds: 60,
          expiresAt: DateTime.utc(2030),
        ),
      );

      expect(await store.loadPolicy('irc.example.com'), isNotNull);

      await store.deletePolicy('IRC.EXAMPLE.COM');
      expect(await store.loadPolicy('irc.example.com'), isNull);
    });
  });
}

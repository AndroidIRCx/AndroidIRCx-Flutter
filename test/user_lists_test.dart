import 'package:androidircx/features/chat/data/user_list_entry.dart';
import 'package:androidircx/features/chat/data/user_lists_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('maskMatches', () {
    test('bare nick matches any user@host via normalizedMask', () {
      const entry = UserListEntry(type: UserListType.autoVoice, mask: 'alice');
      expect(entry.normalizedMask, 'alice!*@*');
      expect(
        entry.matches(nick: 'alice', ident: 'x', host: 'y', channel: '#a'),
        isTrue,
      );
      expect(
        entry.matches(nick: 'bob', ident: 'x', host: 'y', channel: '#a'),
        isFalse,
      );
    });

    test('wildcard host mask', () {
      expect(
        maskMatches('*!*@*.example.net', 'bob!id@host.example.net'),
        isTrue,
      );
      expect(
        maskMatches('*!*@*.example.net', 'bob!id@host.other.org'),
        isFalse,
      );
    });

    test('is case-insensitive', () {
      expect(maskMatches('Alice!*@*', 'alice!id@host'), isTrue);
    });

    test('? matches exactly one char', () {
      expect(maskMatches('ali?e!*@*', 'alice!x@y'), isTrue);
      expect(maskMatches('ali?e!*@*', 'aliiice!x@y'), isFalse);
    });
  });

  group('UserListEntry channel/network scoping', () {
    test('empty channels applies to all channels', () {
      const e = UserListEntry(type: UserListType.autoOp, mask: 'a');
      expect(e.appliesToChannel('#anything'), isTrue);
    });

    test('channel filter is case-insensitive and specific', () {
      const e = UserListEntry(
        type: UserListType.autoOp,
        mask: 'a',
        channels: ['#Flutter'],
      );
      expect(e.appliesToChannel('#flutter'), isTrue);
      expect(e.appliesToChannel('#dart'), isFalse);
    });

    test('network filter', () {
      const e = UserListEntry(
        type: UserListType.autoVoice,
        mask: 'a',
        network: 'dbase',
      );
      expect(e.appliesToNetwork('dbase'), isTrue);
      expect(e.appliesToNetwork('other'), isFalse);
      const global = UserListEntry(type: UserListType.autoVoice, mask: 'a');
      expect(global.appliesToNetwork('anything'), isTrue);
    });
  });

  group('UserListsRepository', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    UserListsRepository repo() =>
        UserListsRepository(prefsLoader: SharedPreferences.getInstance);

    test('add, persist, reload', () async {
      final r = repo();
      await r.add(
        const UserListEntry(type: UserListType.autoVoice, mask: 'alice'),
      );
      final loaded = await r.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.type, UserListType.autoVoice);
      expect(loaded.first.mask, 'alice');
    });

    test('add de-duplicates by identity', () async {
      final r = repo();
      await r.add(
        const UserListEntry(type: UserListType.autoVoice, mask: 'alice'),
      );
      await r.add(
        const UserListEntry(type: UserListType.autoVoice, mask: 'alice'),
      );
      expect(await r.loadAll(), hasLength(1));
    });

    test('remove by identity', () async {
      final r = repo();
      await r.add(const UserListEntry(type: UserListType.autoOp, mask: 'a'));
      await r.add(const UserListEntry(type: UserListType.autoVoice, mask: 'b'));
      await r.remove(const UserListEntry(type: UserListType.autoOp, mask: 'a'));
      final loaded = await r.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.first.mask, 'b');
    });

    test('json round-trip preserves channels and network', () {
      const e = UserListEntry(
        type: UserListType.autoHalfOp,
        mask: 'nick!*@*',
        channels: ['#a', '#b'],
        network: 'dbase',
      );
      final decoded = UserListEntry.fromJson(e.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.type, UserListType.autoHalfOp);
      expect(decoded.channels, ['#a', '#b']);
      expect(decoded.network, 'dbase');
    });

    test('json round-trip preserves blacklist action metadata', () {
      const e = UserListEntry(
        type: UserListType.blacklist,
        mask: 'bad!*@evil',
        network: 'dbase',
        blacklistAction: BlacklistAction.custom,
        reason: 'spam',
        duration: Duration(minutes: 30),
        customRaw: 'GLINE {hostmask} {duration} :{reason}',
      );
      final decoded = UserListEntry.fromJson(e.toJson());
      expect(decoded, isNotNull);
      expect(decoded!.type, UserListType.blacklist);
      expect(decoded.effectiveBlacklistAction, BlacklistAction.custom);
      expect(decoded.reason, 'spam');
      expect(decoded.duration, const Duration(minutes: 30));
      expect(decoded.customRaw, 'GLINE {hostmask} {duration} :{reason}');
    });
  });
}

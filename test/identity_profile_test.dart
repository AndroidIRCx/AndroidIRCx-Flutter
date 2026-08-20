import 'package:androidircx/core/models/identity_profile.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/identity_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _network = NetworkConfig(
  id: 'net',
  name: 'Net',
  host: 'irc.example.test',
  port: 6697,
  nickname: 'orig',
  altNickname: 'orig_',
  username: 'origident',
  realName: 'Original',
);

void main() {
  group('IdentityProfile model', () {
    test('round-trips through JSON', () {
      const profile = IdentityProfile(
        id: 'p1',
        name: 'Work',
        nick: 'alice',
        altNick: 'alice_',
        realName: 'Alice R',
        ident: 'aliceid',
        saslAccount: 'aliceacct',
        saslMechanism: SaslMechanism.scramSha256,
        onConnectCommands: ['/join #work'],
      );
      final restored = IdentityProfile.fromJson(profile.toJson());
      expect(restored.id, 'p1');
      expect(restored.nick, 'alice');
      expect(restored.altNick, 'alice_');
      expect(restored.saslMechanism, SaslMechanism.scramSha256);
      expect(restored.onConnectCommands, ['/join #work']);
    });

    test('exposes the built-in default identity', () {
      expect(IdentityProfile.defaultProfile.nick, 'AndroidIRCX');
      expect(IdentityProfile.defaultProfile.id, IdentityProfile.defaultProfileId);
    });
  });

  group('applyIdentityProfile', () {
    test('overrides identity fields and records the profile id', () {
      const profile = IdentityProfile(
        id: 'p1',
        name: 'Work',
        nick: 'alice',
        altNick: 'alice_',
        realName: 'Alice R',
        ident: 'aliceid',
        saslAccount: 'aliceacct',
        saslMechanism: SaslMechanism.external,
      );
      final result = applyIdentityProfile(_network, profile);
      expect(result.identityProfileId, 'p1');
      expect(result.nickname, 'alice');
      expect(result.altNickname, 'alice_');
      expect(result.realName, 'Alice R');
      expect(result.username, 'aliceid');
      expect(result.saslAccount, 'aliceacct');
      expect(result.saslMechanism, SaslMechanism.external);
    });

    test('keeps network values for fields the profile leaves empty', () {
      const profile = IdentityProfile(id: 'p2', name: 'Nick only', nick: 'bob');
      final result = applyIdentityProfile(_network, profile);
      expect(result.nickname, 'bob');
      expect(result.altNickname, 'orig_');
      expect(result.realName, 'Original');
      expect(result.username, 'origident');
      expect(result.identityProfileId, 'p2');
    });
  });

  group('IdentityProfileRepository', () {
    test('normalizeProfiles puts the default first without duplicating', () {
      const custom = IdentityProfile(id: 'p1', name: 'A', nick: 'a');
      final normalized = normalizeProfiles(const [custom]);
      expect(normalized.first.id, IdentityProfile.defaultProfileId);
      expect(
        normalized.where((p) => p.id == IdentityProfile.defaultProfileId),
        hasLength(1),
      );
      expect(normalized.map((p) => p.id), contains('p1'));
    });

    test('in-memory repo saves, replaces, and deletes custom profiles', () async {
      final repo = InMemoryIdentityProfileRepository();
      const profile = IdentityProfile(id: 'p1', name: 'Work', nick: 'alice');
      await repo.saveProfile(profile);
      expect((await repo.loadProfiles()).any((p) => p.id == 'p1'), isTrue);

      await repo.saveProfile(profile.copyWith(nick: 'alice2'));
      final loaded = await repo.loadProfiles();
      expect(loaded.firstWhere((p) => p.id == 'p1').nick, 'alice2');
      expect(loaded.where((p) => p.id == 'p1'), hasLength(1));

      await repo.deleteProfile('p1');
      expect((await repo.loadProfiles()).any((p) => p.id == 'p1'), isFalse);
    });

    test('the default profile cannot be deleted', () async {
      final repo = InMemoryIdentityProfileRepository();
      await repo.deleteProfile(IdentityProfile.defaultProfileId);
      expect(
        (await repo.loadProfiles())
            .any((p) => p.id == IdentityProfile.defaultProfileId),
        isTrue,
      );
    });
  });

  test('NetworkConfig round-trips identityProfileId', () {
    final config = _network.copyWith(identityProfileId: 'p9');
    final restored = NetworkConfig.fromJson(config.toJson());
    expect(restored.identityProfileId, 'p9');
  });
}

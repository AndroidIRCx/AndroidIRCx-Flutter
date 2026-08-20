import 'package:androidircx/core/backup/backup_service.dart';
import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/models/identity_profile.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/identity_profile_repository.dart';
import 'package:androidircx/core/storage/in_memory_network_repository.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSettings implements SettingsRepository {
  _FakeSettings(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }
}

void main() {
  test('exports and re-imports config without secret values', () async {
    final networks = InMemoryNetworkRepository(const [
      NetworkConfig(
        id: 'n',
        name: 'N',
        host: 'irc.example.test',
        port: 6697,
        nickname: 'nick',
        password: 'topsecret',
        saslPassword: 'saslsecret',
      ),
    ]);
    final settings = _FakeSettings(
      const AppSettings(monospaceMessages: true),
    );
    final profiles = InMemoryIdentityProfileRepository([
      const IdentityProfile(id: 'p', name: 'Work', nick: 'w'),
    ]);
    final service = BackupService(
      networkRepository: networks,
      settingsRepository: settings,
      profileRepository: profiles,
    );

    final json = await service.export();
    expect(json.contains('topsecret'), isFalse);
    expect(json.contains('saslsecret'), isFalse);
    expect(json.contains('"N"'), isTrue);

    final networks2 = InMemoryNetworkRepository(const []);
    final settings2 = _FakeSettings(const AppSettings());
    final profiles2 = InMemoryIdentityProfileRepository();
    final service2 = BackupService(
      networkRepository: networks2,
      settingsRepository: settings2,
      profileRepository: profiles2,
    );

    final result = await service2.import(json);
    expect(result.networks, 1);
    expect(result.profiles, 1);
    expect(result.settingsRestored, isTrue);

    final restored = await networks2.loadNetworks();
    expect(restored.single.name, 'N');
    expect(restored.single.password, isNull);
    expect((await settings2.loadSettings()).monospaceMessages, isTrue);
    expect(
      (await profiles2.loadProfiles()).any((p) => p.id == 'p'),
      isTrue,
    );
  });

  test('rejects a non-object backup', () async {
    final service = BackupService(
      networkRepository: InMemoryNetworkRepository(const []),
      settingsRepository: _FakeSettings(const AppSettings()),
      profileRepository: InMemoryIdentityProfileRepository(),
    );
    await expectLater(service.import('[]'), throwsA(isA<FormatException>()));
  });
}

import 'dart:convert';

import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/models/identity_profile.dart';
import 'package:androidircx/core/models/network_config.dart';
import 'package:androidircx/core/storage/identity_profile_repository.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:androidircx/core/storage/network_secret_keys.dart';
import 'package:androidircx/core/storage/settings_repository.dart';

class BackupImportResult {
  const BackupImportResult({
    required this.networks,
    required this.profiles,
    required this.settingsRestored,
  });

  final int networks;
  final int profiles;
  final bool settingsRestored;
}

/// Exports/imports networks, settings, and identity profiles as JSON.
///
/// Secret values (passwords, channel keys, certificates) are never included —
/// they stay in secure storage. Restoring re-creates the non-secret config; the
/// user re-enters passwords afterward.
class BackupService {
  BackupService({
    required NetworkRepository networkRepository,
    required SettingsRepository settingsRepository,
    required IdentityProfileRepository profileRepository,
  }) : _networks = networkRepository,
       _settings = settingsRepository,
       _profiles = profileRepository;

  static const int backupVersion = 1;

  final NetworkRepository _networks;
  final SettingsRepository _settings;
  final IdentityProfileRepository _profiles;

  Future<String> export() async {
    final networks = await _networks.loadNetworks();
    final settings = await _settings.loadSettings();
    final profiles = await _profiles.loadProfiles();
    return const JsonEncoder.withIndent('  ').convert({
      'version': backupVersion,
      'networks': networks.map(_publicNetworkJson).toList(),
      'settings': settings.toJson(),
      'profiles': profiles
          .where((p) => p.id != IdentityProfile.defaultProfileId)
          .map((p) => p.toJson())
          .toList(),
    });
  }

  Future<BackupImportResult> import(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Backup is not a JSON object.');
    }

    var networkCount = 0;
    final rawNetworks = decoded['networks'];
    if (rawNetworks is List) {
      for (final raw in rawNetworks) {
        if (raw is Map) {
          await _networks.saveNetwork(
            NetworkConfig.fromJson(Map<String, Object?>.from(raw)),
          );
          networkCount++;
        }
      }
    }

    var profileCount = 0;
    final rawProfiles = decoded['profiles'];
    if (rawProfiles is List) {
      for (final raw in rawProfiles) {
        if (raw is Map) {
          await _profiles.saveProfile(
            IdentityProfile.fromJson(Map<String, Object?>.from(raw)),
          );
          profileCount++;
        }
      }
    }

    var settingsRestored = false;
    final rawSettings = decoded['settings'];
    if (rawSettings is Map) {
      await _settings.saveSettings(
        AppSettings.fromJson(Map<String, Object?>.from(rawSettings)),
      );
      settingsRestored = true;
    }

    return BackupImportResult(
      networks: networkCount,
      profiles: profileCount,
      settingsRestored: settingsRestored,
    );
  }

  static Map<String, Object?> _publicNetworkJson(NetworkConfig network) {
    final json = network.toJson();
    for (final field in NetworkSecretField.values) {
      json.remove(field.jsonKey);
    }
    return json;
  }
}

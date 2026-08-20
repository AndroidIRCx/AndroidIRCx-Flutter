import 'dart:convert';

import 'package:androidircx/core/models/identity_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence for reusable identity profiles.
abstract class IdentityProfileRepository {
  Future<List<IdentityProfile>> loadProfiles();
  Future<void> saveProfile(IdentityProfile profile);
  Future<void> deleteProfile(String id);
}

/// Ensures [IdentityProfile.defaultProfile] is always present and first, without
/// duplicating it, so callers always have at least one usable identity.
List<IdentityProfile> normalizeProfiles(List<IdentityProfile> profiles) {
  final others = profiles.where(
    (profile) => profile.id != IdentityProfile.defaultProfileId,
  );
  return List<IdentityProfile>.unmodifiable(
    [IdentityProfile.defaultProfile, ...others],
  );
}

class SharedPrefsIdentityProfileRepository implements IdentityProfileRepository {
  static const _storageKey = 'androidircx.identityProfiles';

  @override
  Future<List<IdentityProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return normalizeProfiles(const <IdentityProfile>[]);
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return normalizeProfiles(const <IdentityProfile>[]);
    }
    final profiles = decoded
        .whereType<Map<String, Object?>>()
        .map(IdentityProfile.fromJson)
        .toList(growable: false);
    return normalizeProfiles(profiles);
  }

  @override
  Future<void> saveProfile(IdentityProfile profile) async {
    final current = await loadProfiles();
    final next = <IdentityProfile>[];
    var replaced = false;
    for (final existing in current) {
      if (existing.id == profile.id) {
        next.add(profile);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) {
      next.add(profile);
    }
    await _persist(next);
  }

  @override
  Future<void> deleteProfile(String id) async {
    if (id == IdentityProfile.defaultProfileId) {
      return; // the built-in default cannot be removed
    }
    final current = await loadProfiles();
    await _persist(
      current.where((profile) => profile.id != id).toList(growable: false),
    );
  }

  Future<void> _persist(List<IdentityProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    // The default profile is implicit; do not persist it.
    final persistable = profiles
        .where((profile) => profile.id != IdentityProfile.defaultProfileId)
        .map((profile) => profile.toJson())
        .toList(growable: false);
    await prefs.setString(_storageKey, jsonEncode(persistable));
  }
}

class InMemoryIdentityProfileRepository implements IdentityProfileRepository {
  InMemoryIdentityProfileRepository([List<IdentityProfile> initial = const []])
      : _profiles = [
          for (final profile in initial)
            if (profile.id != IdentityProfile.defaultProfileId) profile,
        ];

  final List<IdentityProfile> _profiles;

  @override
  Future<List<IdentityProfile>> loadProfiles() async {
    return normalizeProfiles(_profiles);
  }

  @override
  Future<void> saveProfile(IdentityProfile profile) async {
    if (profile.id == IdentityProfile.defaultProfileId) {
      return;
    }
    _profiles
      ..removeWhere((existing) => existing.id == profile.id)
      ..add(profile);
  }

  @override
  Future<void> deleteProfile(String id) async {
    _profiles.removeWhere((profile) => profile.id == id);
  }
}

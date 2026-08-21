import 'dart:convert';

import 'package:androidircx/features/chat/data/user_list_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists automatic-mode user-list rules (auto-op / auto-halfop / auto-voice)
/// as a single JSON array in shared preferences. De-duplicates by rule identity.
class UserListsRepository {
  UserListsRepository({Future<SharedPreferences> Function()? prefsLoader})
    : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String storageKey = 'userLists';

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<List<UserListEntry>> loadAll() async {
    final prefs = await _prefsLoader();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return <UserListEntry>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => UserListEntry.fromJson(Map<String, dynamic>.from(e)))
            .whereType<UserListEntry>()
            .toList();
      }
    } catch (_) {
      // Corrupt blob: start fresh.
    }
    return <UserListEntry>[];
  }

  Future<void> _saveAll(List<UserListEntry> entries) async {
    final prefs = await _prefsLoader();
    await prefs.setString(
      storageKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// Adds [entry], replacing any existing rule with the same identity. Returns
  /// the updated full list.
  Future<List<UserListEntry>> add(UserListEntry entry) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.key == entry.key);
    entries.add(entry);
    await _saveAll(entries);
    return entries;
  }

  /// Removes any rule whose identity matches [entry]. Returns the updated list.
  Future<List<UserListEntry>> remove(UserListEntry entry) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.key == entry.key);
    await _saveAll(entries);
    return entries;
  }

  Future<List<UserListEntry>> replaceAll(List<UserListEntry> entries) async {
    await _saveAll(entries);
    return entries;
  }
}

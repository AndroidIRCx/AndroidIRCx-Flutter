import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local, per-user free-text notes keyed by `network::nick`. Stored as a single
/// JSON object in shared preferences (mirrors the RN user-notes store). Purely
/// on-device; no IRC protocol involvement. Nick lookups are case-insensitive.
class UserNotesRepository {
  UserNotesRepository({Future<SharedPreferences> Function()? prefsLoader})
    : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String storageKey = 'userNotes';

  final Future<SharedPreferences> Function() _prefsLoader;

  String _compositeKey(String network, String nick) =>
      '$network::${nick.toLowerCase()}';

  Future<Map<String, String>> _readAll(SharedPreferences prefs) async {
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', '${value ?? ''}'));
      }
    } catch (_) {
      // Corrupt blob: start fresh rather than throw.
    }
    return <String, String>{};
  }

  /// Returns the note for [nick] on [network], or an empty string.
  Future<String> getNote(String network, String nick) async {
    final prefs = await _prefsLoader();
    final all = await _readAll(prefs);
    return all[_compositeKey(network, nick)] ?? '';
  }

  /// Saves [note] for [nick] on [network]. An empty/whitespace note removes the
  /// entry.
  Future<void> setNote(String network, String nick, String note) async {
    final prefs = await _prefsLoader();
    final all = await _readAll(prefs);
    final key = _compositeKey(network, nick);
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      all.remove(key);
    } else {
      all[key] = trimmed;
    }
    await prefs.setString(storageKey, jsonEncode(all));
  }

  /// All notes, keyed by `network::nick`.
  Future<Map<String, String>> allNotes() async {
    final prefs = await _prefsLoader();
    return _readAll(prefs);
  }
}

import 'dart:convert';

import 'package:androidircx/core/models/app_settings.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _storageKey = 'androidircx.settings';

  @override
  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return const AppSettings();
    }

    return AppSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(settings.toJson()));
  }
}

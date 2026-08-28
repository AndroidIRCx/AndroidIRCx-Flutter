import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Preset kick/ban reasons offered in the moderation dialog; user-editable
/// in Settings → Channels.
class KickBanReasonsRepository {
  static const _key = 'androidircx.kickBanReasons';

  static const List<String> defaultReasons = <String>[
    'Spam',
    'Flooding',
    'Abuse',
    'Off-topic',
    'Policy violation',
  ];

  Future<List<String>> loadReasons() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return defaultReasons;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return defaultReasons;
      }
      final reasons = decoded
          .whereType<String>()
          .map((reason) => reason.trim())
          .where((reason) => reason.isNotEmpty)
          .toList(growable: false);
      return reasons.isEmpty ? defaultReasons : reasons;
    } catch (_) {
      return defaultReasons;
    }
  }

  Future<void> saveReasons(List<String> reasons) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = reasons
        .map((reason) => reason.trim())
        .where((reason) => reason.isNotEmpty)
        .toList(growable: false);
    await prefs.setString(_key, jsonEncode(cleaned));
  }
}

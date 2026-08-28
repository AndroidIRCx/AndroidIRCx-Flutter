import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-channel/query notification override.
enum ChannelNotificationRule {
  /// Follow the global notification settings (highlights, PMs, ...).
  defaults,

  /// Notify for every message in this tab, not just highlights.
  all,

  /// Only notify when the message is a highlight/mention.
  mentionsOnly,

  /// Never notify (and never play a sound) for this tab.
  mute,
}

String channelNotificationRuleLabel(ChannelNotificationRule rule) {
  return switch (rule) {
    ChannelNotificationRule.defaults => 'Default',
    ChannelNotificationRule.all => 'All messages',
    ChannelNotificationRule.mentionsOnly => 'Mentions only',
    ChannelNotificationRule.mute => 'Muted',
  };
}

/// Persists per-channel notification rules keyed by network + target name.
class ChannelNotificationRulesRepository {
  static const _key = 'androidircx.channelNotificationRules';

  static String _entryKey(String networkId, String target) =>
      '$networkId|${target.toLowerCase()}';

  Future<Map<String, ChannelNotificationRule>> loadRules(
    String networkId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const <String, ChannelNotificationRule>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const <String, ChannelNotificationRule>{};
      }
      final prefix = '$networkId|';
      final rules = <String, ChannelNotificationRule>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! String || !key.startsWith(prefix)) {
          return;
        }
        for (final rule in ChannelNotificationRule.values) {
          if (rule.name == value) {
            rules[key.substring(prefix.length)] = rule;
          }
        }
      });
      return rules;
    } catch (_) {
      return const <String, ChannelNotificationRule>{};
    }
  }

  Future<void> setRule(
    String networkId,
    String target,
    ChannelNotificationRule rule,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    Map<String, Object?> stored = <String, Object?>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          stored = Map<String, Object?>.from(decoded);
        }
      } catch (_) {
        // Corrupt storage: start over.
      }
    }
    final entryKey = _entryKey(networkId, target);
    if (rule == ChannelNotificationRule.defaults) {
      stored.remove(entryKey);
    } else {
      stored[entryKey] = rule.name;
    }
    await prefs.setString(_key, jsonEncode(stored));
  }
}

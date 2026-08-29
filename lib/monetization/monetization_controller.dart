import 'dart:async';
import 'dart:convert';

import 'package:androidircx/monetization/monetization_config.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PremiumTier { free, removeAds, proUnlimited, supporterPro }

class MonetizationController extends ChangeNotifier {
  static const _purchasesKey = 'androidircx.monetization.purchases';
  static const _purchaseTokensKey = 'androidircx.monetization.purchaseTokens';
  static const _adFreeTimeKey = 'androidircx.monetization.adFreeTime';

  bool _initialized = false;
  bool _removeAds = false;
  bool _proUnlimited = false;
  bool _supporterPro = false;
  int _adFreeMs = 0;
  int _lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
  int _ticksSinceSave = 0;
  Timer? _adFreeTimer;

  bool get initialized => _initialized;
  bool get hasRemoveAds => _removeAds;
  bool get hasProUnlimited => _proUnlimited;
  bool get isSupporter => _supporterPro;

  bool get hasNoAds => _removeAds || _proUnlimited || _supporterPro;
  bool get hasUnlimitedScripting => _proUnlimited || _supporterPro;
  bool get hasTemporaryAdFreeTime => _adFreeMs > 0;
  int get adFreeTimeMs => _adFreeMs;

  PremiumTier get highestTier {
    if (_supporterPro) {
      return PremiumTier.supporterPro;
    }
    if (_proUnlimited) {
      return PremiumTier.proUnlimited;
    }
    if (_removeAds) {
      return PremiumTier.removeAds;
    }
    return PremiumTier.free;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _loadPurchases();
    await _loadAdFreeTime();
    _initialized = true;
    if (_adFreeMs > 0) {
      _startAdFreeTimer();
    }
    notifyListeners();
  }

  bool shouldShowBanner({
    required bool onboardingCompleted,
    bool? mobileAdsRuntimeSupported,
  }) {
    final adsSupported =
        mobileAdsRuntimeSupported ??
        MonetizationConfig.mobileAdsRuntimeSupported;
    return _initialized &&
        onboardingCompleted &&
        adsSupported &&
        !hasNoAds &&
        !hasTemporaryAdFreeTime;
  }

  Future<bool> processPurchase(String productId, String purchaseToken) async {
    if (!MonetizationConfig.productIds.contains(productId)) {
      return false;
    }
    if (productId == MonetizationConfig.productRemoveAds) {
      _removeAds = true;
    } else if (productId == MonetizationConfig.productProUnlimited) {
      _proUnlimited = true;
    } else if (productId == MonetizationConfig.productSupporterPro) {
      _supporterPro = true;
    }

    await _savePurchases();
    if (purchaseToken.trim().isNotEmpty) {
      await _storePurchaseToken(productId, purchaseToken.trim());
    }
    notifyListeners();
    return true;
  }

  bool hasPurchased(String productId) {
    return switch (productId) {
      MonetizationConfig.productRemoveAds => _removeAds,
      MonetizationConfig.productProUnlimited => _proUnlimited,
      MonetizationConfig.productSupporterPro => _supporterPro,
      _ => false,
    };
  }

  Future<String?> getPurchaseToken(String productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_purchaseTokensKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      return decoded[productId] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> grantTemporaryAdFreeTime(Duration duration) async {
    if (duration <= Duration.zero) {
      return;
    }
    _adFreeMs += duration.inMilliseconds;
    _lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
    _ticksSinceSave = 0;
    await _saveAdFreeTime();
    _startAdFreeTimer();
    notifyListeners();
  }

  Future<void> resetTemporaryAdFreeTime() async {
    _adFreeMs = 0;
    _lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
    _ticksSinceSave = 0;
    _adFreeTimer?.cancel();
    _adFreeTimer = null;
    await _saveAdFreeTime();
    notifyListeners();
  }

  String get adFreeTimeFormatted => formatDurationMs(_adFreeMs);

  static String formatDurationMs(int ms) {
    final safeMs = ms < 0 ? 0 : ms;
    final hours = safeMs ~/ Duration.millisecondsPerHour;
    final minutes =
        (safeMs % Duration.millisecondsPerHour) ~/
        Duration.millisecondsPerMinute;
    final seconds =
        (safeMs % Duration.millisecondsPerMinute) ~/
        Duration.millisecondsPerSecond;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  Future<void> _loadPurchases() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_purchasesKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      _removeAds =
          decoded[MonetizationConfig.productRemoveAds] as bool? ?? false;
      _proUnlimited =
          decoded[MonetizationConfig.productProUnlimited] as bool? ?? false;
      _supporterPro =
          decoded[MonetizationConfig.productSupporterPro] as bool? ?? false;
    } catch (_) {
      _removeAds = false;
      _proUnlimited = false;
      _supporterPro = false;
    }
  }

  Future<void> _savePurchases() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _purchasesKey,
      jsonEncode(<String, bool>{
        MonetizationConfig.productRemoveAds: _removeAds,
        MonetizationConfig.productProUnlimited: _proUnlimited,
        MonetizationConfig.productSupporterPro: _supporterPro,
      }),
    );
  }

  Future<void> _storePurchaseToken(String productId, String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_purchaseTokensKey);
      final tokens = raw == null || raw.isEmpty
          ? <String, Object?>{}
          : jsonDecode(raw) as Map<String, Object?>;
      tokens[productId] = token;
      await prefs.setString(_purchaseTokensKey, jsonEncode(tokens));
    } catch (_) {
      // The entitlement is already granted locally. Token storage is best effort
      // until backend verification is introduced.
    }
  }

  Future<void> _loadAdFreeTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_adFreeTimeKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      _adFreeMs = (decoded['remainingMs'] as num?)?.toInt() ?? 0;
      _lastUpdatedMs =
          (decoded['lastUpdated'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      _adFreeMs = _adFreeMs < 0 ? 0 : _adFreeMs;
      final elapsed = DateTime.now().millisecondsSinceEpoch - _lastUpdatedMs;
      if (elapsed > 0) {
        _adFreeMs = (_adFreeMs - elapsed).clamp(0, _adFreeMs).toInt();
        _lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
        await prefs.setString(
          _adFreeTimeKey,
          jsonEncode(<String, int>{
            'remainingMs': _adFreeMs,
            'lastUpdated': _lastUpdatedMs,
          }),
        );
      }
    } catch (_) {
      _adFreeMs = 0;
      _lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<void> _saveAdFreeTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _adFreeTimeKey,
      jsonEncode(<String, int>{
        'remainingMs': _adFreeMs,
        'lastUpdated': _lastUpdatedMs,
      }),
    );
  }

  void _startAdFreeTimer() {
    if (_adFreeTimer != null || _adFreeMs <= 0) {
      return;
    }
    _lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
    _adFreeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = now - _lastUpdatedMs;
      _lastUpdatedMs = now;
      _adFreeMs = (_adFreeMs - elapsed).clamp(0, _adFreeMs).toInt();
      _ticksSinceSave += 1;

      if (_adFreeMs <= 0) {
        _adFreeTimer?.cancel();
        _adFreeTimer = null;
        unawaited(_saveAdFreeTime());
      } else if (_ticksSinceSave >= 10) {
        _ticksSinceSave = 0;
        unawaited(_saveAdFreeTime());
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _adFreeTimer?.cancel();
    super.dispose();
  }
}

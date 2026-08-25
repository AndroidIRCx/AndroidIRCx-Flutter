import 'dart:async';

import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class RewardedAdResult {
  const RewardedAdResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class RewardedAdService extends ChangeNotifier {
  RewardedAdService({required MonetizationController monetizationController})
    : _monetizationController = monetizationController;

  final MonetizationController _monetizationController;
  RewardedAd? _rewardedAd;
  bool _loading = false;
  bool _showing = false;
  int _retryCount = 0;
  DateTime? _cooldownUntil;
  Timer? _cooldownTimer;
  String? _lastError;

  bool get isReady => _rewardedAd != null;
  bool get isLoading => _loading;
  bool get isShowing => _showing;
  bool get isInCooldown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);
  int get cooldownSeconds {
    final until = _cooldownUntil;
    if (until == null) {
      return 0;
    }
    final remaining = until.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  String? get lastError => _lastError;

  Future<RewardedAdResult> manualLoadAd() async {
    if (!MonetizationConfig.mobileAdsRuntimeSupported) {
      return const RewardedAdResult(
        success: false,
        message: 'Rewarded ads are available only in Android/iOS builds.',
      );
    }
    if (isInCooldown) {
      return RewardedAdResult(
        success: false,
        message: 'Please wait ${cooldownSeconds}s before trying again.',
      );
    }
    if (isReady) {
      return const RewardedAdResult(
        success: true,
        message: 'Ad is ready. Tap again to watch.',
      );
    }
    if (_loading) {
      return const RewardedAdResult(
        success: false,
        message: 'Ad is loading, please wait.',
      );
    }
    await loadAd();
    return const RewardedAdResult(
      success: true,
      message: 'Requesting rewarded ad from Google.',
    );
  }

  Future<void> loadAd() async {
    if (!MonetizationConfig.mobileAdsRuntimeSupported ||
        _loading ||
        isReady ||
        isInCooldown) {
      return;
    }
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      await RewardedAd.load(
        adUnitId: MonetizationConfig.rewardedAdUnitId,
        request: const AdRequest(nonPersonalizedAds: true),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedAd = ad;
            _loading = false;
            _retryCount = 0;
            _lastError = null;
            _configureFullScreenCallbacks(ad);
            notifyListeners();
          },
          onAdFailedToLoad: (error) {
            _rewardedAd = null;
            _loading = false;
            _handleLoadFailure(error.message);
          },
        ),
      );
    } catch (error) {
      _loading = false;
      _handleLoadFailure(error.toString());
    }
  }

  Future<RewardedAdResult> showRewardedAd() async {
    final ad = _rewardedAd;
    if (ad == null) {
      return const RewardedAdResult(
        success: false,
        message: 'Rewarded ad is not ready yet.',
      );
    }
    _rewardedAd = null;
    _showing = true;
    notifyListeners();
    try {
      await ad.show(
        onUserEarnedReward: (_, reward) {
          final minutes = reward.amount.toInt() > 0
              ? reward.amount.toInt()
              : MonetizationConfig.rewardAdFreeMinutes;
          unawaited(
            _monetizationController.grantTemporaryAdFreeTime(
              Duration(minutes: minutes),
            ),
          );
        },
      );
      return const RewardedAdResult(
        success: true,
        message: 'Ad opened. Reward applies after completion.',
      );
    } catch (error) {
      _showing = false;
      _lastError = error.toString();
      notifyListeners();
      return RewardedAdResult(
        success: false,
        message: 'Could not show rewarded ad: $error',
      );
    }
  }

  void _configureFullScreenCallbacks(RewardedAd ad) {
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showing = false;
        notifyListeners();
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!_showing && !isReady) {
            unawaited(loadAd());
          }
        });
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _showing = false;
        _handleLoadFailure(error.message);
      },
    );
  }

  void _handleLoadFailure(String message) {
    _retryCount += 1;
    _lastError = message;
    if (_retryCount >= 3) {
      _cooldownUntil = DateTime.now().add(const Duration(seconds: 60));
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(const Duration(seconds: 60), () {
        _cooldownUntil = null;
        notifyListeners();
      });
      _retryCount = 0;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _rewardedAd?.dispose();
    super.dispose();
  }
}

import 'dart:async';

import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class MonetizationBanner extends StatefulWidget {
  const MonetizationBanner({
    super.key,
    required this.controller,
    required this.onboardingCompleted,
    required this.child,
  });

  final MonetizationController controller;
  final bool onboardingCompleted;
  final Widget child;

  @override
  State<MonetizationBanner> createState() => _MonetizationBannerState();
}

class _MonetizationBannerState extends State<MonetizationBanner> {
  static const _retryDelay = Duration(seconds: 30);

  BannerAd? _bannerAd;
  bool _loaded = false;
  bool _loading = false;
  String? _lastFailure;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncBannerState);
    _syncBannerState();
  }

  @override
  void didUpdateWidget(covariant MonetizationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncBannerState);
      widget.controller.addListener(_syncBannerState);
    }
    _syncBannerState();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncBannerState);
    _retryTimer?.cancel();
    _disposeBanner();
    super.dispose();
  }

  void _syncBannerState() {
    final shouldShow = widget.controller.shouldShowBanner(
      onboardingCompleted: widget.onboardingCompleted,
    );
    if (!shouldShow) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _loading = false;
      _lastFailure = null;
      _disposeBanner();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (_bannerAd == null && !_loading) {
      _loadBanner();
    }
  }

  void _loadBanner() {
    if (!MonetizationConfig.mobileAdsRuntimeSupported) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    _loading = true;
    _loaded = false;
    _lastFailure = null;
    if (mounted) {
      setState(() {});
    }
    final ad = BannerAd(
      adUnitId: MonetizationConfig.bannerAdUnitId,
      request: const AdRequest(nonPersonalizedAds: true),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || !identical(_bannerAd, ad)) {
            ad.dispose();
            return;
          }
          setState(() {
            _loaded = true;
            _loading = false;
            _lastFailure = null;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (!mounted) {
            return;
          }
          setState(() {
            if (identical(_bannerAd, ad)) {
              _bannerAd = null;
              _loaded = false;
              _loading = false;
              _lastFailure = '${error.code}: ${error.message}';
            }
          });
          _scheduleRetry();
        },
      ),
    );
    _bannerAd = ad;
    try {
      ad.load();
    } catch (error) {
      ad.dispose();
      _bannerAd = null;
      _loaded = false;
      _loading = false;
      _lastFailure = error.toString();
      if (mounted) {
        setState(() {});
        _scheduleRetry();
      }
    }
  }

  void _disposeBanner() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _loaded = false;
  }

  void _scheduleRetry() {
    if (_retryTimer != null) {
      return;
    }
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      if (!mounted) {
        return;
      }
      if (widget.controller.shouldShowBanner(
        onboardingCompleted: widget.onboardingCompleted,
      )) {
        _loadBanner();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shouldShow = widget.controller.shouldShowBanner(
      onboardingCompleted: widget.onboardingCompleted,
    );
    final banner = _loaded && _bannerAd != null
        ? SafeArea(
            bottom: false,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 1,
              child: SizedBox(
                width: double.infinity,
                height: AdSize.banner.height.toDouble(),
                child: Center(
                  child: SizedBox(
                    width: AdSize.banner.width.toDouble(),
                    height: AdSize.banner.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ),
              ),
            ),
          )
        : shouldShow && !kReleaseMode
        ? _BannerLoadStatus(loading: _loading, failure: _lastFailure)
        : const SizedBox.shrink();

    return Column(
      children: [
        banner,
        Expanded(child: widget.child),
      ],
    );
  }
}

class _BannerLoadStatus extends StatelessWidget {
  const _BannerLoadStatus({required this.loading, required this.failure});

  final bool loading;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = failure == null
        ? loading
              ? 'Banner ad loading'
              : 'Banner ad pending'
        : 'Banner ad failed: $failure';
    return SafeArea(
      bottom: false,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        elevation: 1,
        child: SizedBox(
          height: AdSize.banner.height.toDouble(),
          width: double.infinity,
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

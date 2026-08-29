import 'dart:async';

import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:androidircx/monetization/mobile_ads_bootstrap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

typedef BannerAdLoader = Future<void> Function(BannerAd ad);
typedef MobileAdsInitializer = Future<void> Function();

class MonetizationBanner extends StatefulWidget {
  const MonetizationBanner({
    super.key,
    required this.controller,
    required this.onboardingCompleted,
    required this.child,
    this.mobileAdsRuntimeSupported,
    this.initializeMobileAds,
    this.loadBannerAd,
  });

  final MonetizationController controller;
  final bool onboardingCompleted;
  final Widget child;
  @visibleForTesting
  final bool? mobileAdsRuntimeSupported;
  @visibleForTesting
  final MobileAdsInitializer? initializeMobileAds;
  @visibleForTesting
  final BannerAdLoader? loadBannerAd;

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

  bool get _mobileAdsRuntimeSupported =>
      widget.mobileAdsRuntimeSupported ??
      MonetizationConfig.mobileAdsRuntimeSupported;

  bool get _shouldShowBanner => widget.controller.shouldShowBanner(
    onboardingCompleted: widget.onboardingCompleted,
    mobileAdsRuntimeSupported: _mobileAdsRuntimeSupported,
  );

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
    final shouldShow = _shouldShowBanner;
    if (!shouldShow) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _lastFailure = null;
      _disposeBanner();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (_bannerAd == null && !_loading) {
      unawaited(_loadBanner());
    }
  }

  Future<void> _loadBanner() async {
    if (!_mobileAdsRuntimeSupported || _bannerAd != null || _loading) {
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
          if (!mounted || !identical(_bannerAd, ad) || !_shouldShowBanner) {
            _disposeAd(ad);
            return;
          }
          setState(() {
            _loaded = true;
            _loading = false;
            _lastFailure = null;
          });
        },
        onAdFailedToLoad: (ad, error) {
          _disposeAd(ad);
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
      await (widget.initializeMobileAds ?? MobileAdsBootstrap.ensureInitialized)
          .call();
      if (!mounted || !identical(_bannerAd, ad) || !_shouldShowBanner) {
        if (identical(_bannerAd, ad)) {
          _bannerAd = null;
          _loaded = false;
          _loading = false;
        }
        _disposeAd(ad);
        return;
      }
      await (widget.loadBannerAd ?? (ad) => ad.load()).call(ad);
    } catch (error) {
      _disposeAd(ad);
      if (!mounted) {
        return;
      }
      setState(() {
        if (identical(_bannerAd, ad)) {
          _bannerAd = null;
          _loaded = false;
          _loading = false;
          _lastFailure = error.toString();
        }
      });
      _scheduleRetry();
    }
  }

  void _disposeBanner() {
    final ad = _bannerAd;
    _bannerAd = null;
    _loaded = false;
    _loading = false;
    if (ad != null) {
      _disposeAd(ad);
    }
  }

  void _disposeAd(Ad ad) {
    unawaited(ad.dispose().catchError((_) {}));
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
      if (_shouldShowBanner) {
        unawaited(_loadBanner());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final banner = _shouldShowBanner
        ? _BannerSlot(
            child: _loaded && _bannerAd != null
                ? Center(
                    child: SizedBox(
                      width: AdSize.banner.width.toDouble(),
                      height: AdSize.banner.height.toDouble(),
                      child: AdWidget(ad: _bannerAd!),
                    ),
                  )
                : !kReleaseMode
                ? _BannerLoadStatus(loading: _loading, failure: _lastFailure)
                : const SizedBox.shrink(),
          )
        : const SizedBox.shrink();

    return Column(
      children: [
        banner,
        Expanded(child: widget.child),
      ],
    );
  }
}

class _BannerSlot extends StatelessWidget {
  const _BannerSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 1,
        child: SizedBox(
          key: const Key('monetization-banner-slot'),
          height: AdSize.banner.height.toDouble(),
          width: double.infinity,
          child: child,
        ),
      ),
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
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
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
    );
  }
}

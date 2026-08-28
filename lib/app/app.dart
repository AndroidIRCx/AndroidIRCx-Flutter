import 'dart:async';

import 'package:androidircx/app/theme/app_theme.dart';
import 'package:androidircx/core/firebase/firebase_service.dart';
import 'package:androidircx/core/platform/foreground_connection_service.dart';
import 'package:androidircx/core/platform/screen_security.dart';
import 'package:androidircx/core/security/secret_storage.dart';
import 'package:androidircx/core/settings/app_settings_controller.dart';
import 'package:androidircx/core/sound/audioplayers_sound_player.dart';
import 'package:androidircx/core/sound/sound_service.dart';
import 'package:androidircx/core/storage/network_repository.dart';
import 'package:androidircx/core/storage/settings_repository.dart';
import 'package:androidircx/core/storage/shared_prefs_network_repository.dart';
import 'package:androidircx/features/bootstrap/presentation/bootstrap_screen.dart';
import 'package:androidircx/features/monetization/presentation/monetization_banner.dart';
import 'package:androidircx/features/onboarding/presentation/onboarding_screen.dart';
import 'package:androidircx/features/security/presentation/app_lock_gate.dart';
import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:androidircx/monetization/monetization_scope.dart';
import 'package:androidircx/monetization/rewarded_ad_service.dart';
import 'package:androidircx/monetization/store_purchase_service.dart';
import 'package:flutter/material.dart';

class AndroidIrcxApp extends StatefulWidget {
  const AndroidIrcxApp({
    super.key,
    this.networkRepository,
    this.settingsRepository,
    this.foregroundConnectionService =
        const MethodChannelForegroundConnectionService(),
    this.historyRepositoryLoader,
    this.monetizationController,
    this.rewardedAdService,
    this.purchaseService,
    this.soundService,
  });

  final NetworkRepository? networkRepository;
  final SettingsRepository? settingsRepository;
  final ForegroundConnectionService foregroundConnectionService;
  final HistoryRepositoryLoader? historyRepositoryLoader;
  final MonetizationController? monetizationController;
  final RewardedAdService? rewardedAdService;
  final StorePurchaseService? purchaseService;

  /// Overridable for tests; defaults to the audioplayers-backed service.
  final SoundService? soundService;

  @override
  State<AndroidIrcxApp> createState() => _AndroidIrcxAppState();
}

class _AndroidIrcxAppState extends State<AndroidIrcxApp> {
  late final AppSettingsController _settingsController;
  late final MonetizationController _monetizationController;
  late final RewardedAdService _rewardedAdService;
  late final StorePurchaseService _purchaseService;
  late final SoundService _soundService;
  late final bool _ownsMonetizationController;
  late final bool _ownsRewardedAdService;
  late final bool _ownsPurchaseService;
  bool? _appliedScreenSecure;
  bool? _appliedAnalyticsConsent;

  @override
  void initState() {
    super.initState();
    _settingsController = AppSettingsController(
      repository: widget.settingsRepository,
    );
    _ownsMonetizationController = widget.monetizationController == null;
    _monetizationController =
        widget.monetizationController ?? MonetizationController();
    _ownsRewardedAdService = widget.rewardedAdService == null;
    _rewardedAdService =
        widget.rewardedAdService ??
        RewardedAdService(monetizationController: _monetizationController);
    _ownsPurchaseService = widget.purchaseService == null;
    _purchaseService =
        widget.purchaseService ??
        StorePurchaseService(monetizationController: _monetizationController);
    _soundService =
        widget.soundService ?? SoundService(player: AudioplayersSoundPlayer());
    unawaited(_soundService.load());
    _settingsController.addListener(_applySettingsSideEffects);
    _settingsController.load();
    unawaited(_monetizationController.initialize());
    if (MonetizationConfig.storeRuntimeSupported) {
      unawaited(_purchaseService.initialize());
    }
    if (MonetizationConfig.mobileAdsRuntimeSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rewardedAdService.loadAd();
      });
    }
  }

  void _applySettingsSideEffects() {
    final settings = _settingsController.settings;
    if (settings.screenshotProtection != _appliedScreenSecure) {
      _appliedScreenSecure = settings.screenshotProtection;
      unawaited(
        const ScreenSecurity().setSecure(settings.screenshotProtection),
      );
    }
    if (settings.analyticsConsent != _appliedAnalyticsConsent) {
      _appliedAnalyticsConsent = settings.analyticsConsent;
      unawaited(FirebaseService.instance.setConsent(settings.analyticsConsent));
    }
  }

  @override
  void dispose() {
    _settingsController.removeListener(_applySettingsSideEffects);
    _settingsController.dispose();
    if (_ownsPurchaseService) {
      _purchaseService.dispose();
    }
    if (_ownsRewardedAdService) {
      _rewardedAdService.dispose();
    }
    if (_ownsMonetizationController) {
      _monetizationController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MonetizationScope(
      controller: _monetizationController,
      rewardedAdService: _rewardedAdService,
      purchaseService: _purchaseService,
      child: SoundScope(
        service: _soundService,
        child: AppSettingsScope(
          controller: _settingsController,
          child: AnimatedBuilder(
            animation: _settingsController,
            builder: (context, _) {
              return MaterialApp(
                title: 'AndroidIRCx Flutter',
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(_settingsController.settings),
                builder: (context, child) => AppLockGate(
                  enabled:
                      !_settingsController.isLoading &&
                      _settingsController.settings.appLockEnabled,
                  child: MonetizationBanner(
                    controller: _monetizationController,
                    onboardingCompleted:
                        _settingsController.settings.onboardingCompleted,
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
                home: _buildHome(),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHome() {
    if (_settingsController.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_settingsController.settings.onboardingCompleted) {
      final repository =
          widget.networkRepository ??
          SharedPrefsNetworkRepository(
            secretStorage: FlutterSecureSecretStorage(),
          );
      return OnboardingScreen(
        networkRepository: repository,
        onCompleted: () => _settingsController.save(
          _settingsController.settings.copyWith(onboardingCompleted: true),
        ),
      );
    }
    return BootstrapScreen(
      networkRepository: widget.networkRepository,
      foregroundConnectionService: widget.foregroundConnectionService,
      historyRepositoryLoader: widget.historyRepositoryLoader,
      soundService: _soundService,
    );
  }
}

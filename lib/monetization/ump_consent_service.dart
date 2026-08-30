import 'dart:async';

import 'package:androidircx/monetization/mobile_ads_bootstrap.dart';
import 'package:androidircx/monetization/monetization_config.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Gathers ad consent through Google's UMP SDK (the AdMob "Privacy &
/// messaging" GDPR message) and only then initializes the Mobile Ads SDK.
///
/// Outside regions where consent is required (e.g. non-EEA), the SDK reports
/// NOT_REQUIRED and ads initialize immediately. Inside the EEA/UK the consent
/// form is shown once and the user's choice drives personalized vs
/// non-personalized serving automatically — ad requests no longer need a
/// manual `nonPersonalizedAds` flag.
class UmpConsentService {
  UmpConsentService({
    ConsentGatherer? gatherer,
    bool? runtimeSupported,
    Future<void> Function()? initializeAds,
  }) : _gatherer = gatherer ?? const _UmpConsentGatherer(),
       _runtimeSupported = runtimeSupported,
       _initializeAds = initializeAds ?? MobileAdsBootstrap.ensureInitialized;

  final ConsentGatherer _gatherer;
  final bool? _runtimeSupported;
  final Future<void> Function() _initializeAds;
  bool _gathering = false;

  bool get _supported =>
      _runtimeSupported ?? MonetizationConfig.mobileAdsRuntimeSupported;

  /// Requests a consent-info update, shows the consent form when required,
  /// and initializes the ads SDK once ad requests are allowed. Safe to call
  /// repeatedly; failures leave the previous consent state in effect and the
  /// ads SDK still initializes when a prior session's consent allows it.
  Future<void> gatherConsentAndInitAds() async {
    if (!_supported || _gathering) {
      return;
    }
    _gathering = true;
    try {
      await _gatherer.requestConsentInfoUpdate();
      await _gatherer.showConsentFormIfRequired();
    } catch (_) {
      // Network/form failures must never block the app; fall through to the
      // canRequestAds check, which reflects any previously stored consent.
    } finally {
      _gathering = false;
    }
    try {
      if (await _gatherer.canRequestAds()) {
        await _initializeAds();
      }
    } catch (_) {
      // Ads init failures are non-fatal; banner/rewarded retry lazily.
    }
  }

  /// Whether the region requires a "privacy options" entry point (EEA/UK
  /// users can revisit their consent choice from Settings).
  Future<bool> isPrivacyOptionsRequired() {
    if (!_supported) {
      return Future<bool>.value(false);
    }
    return _gatherer.isPrivacyOptionsRequired().catchError((_) => false);
  }

  /// Shows the UMP privacy-options form (Settings entry point).
  Future<void> showPrivacyOptionsForm() {
    if (!_supported) {
      return Future<void>.value();
    }
    return _gatherer.showPrivacyOptionsForm().catchError((_) {});
  }
}

/// Thin seam over the UMP plugin calls so tests can fake them.
abstract class ConsentGatherer {
  Future<void> requestConsentInfoUpdate();
  Future<void> showConsentFormIfRequired();
  Future<bool> canRequestAds();
  Future<bool> isPrivacyOptionsRequired();
  Future<void> showPrivacyOptionsForm();
}

class _UmpConsentGatherer implements ConsentGatherer {
  const _UmpConsentGatherer();

  @override
  Future<void> requestConsentInfoUpdate() {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => completer.complete(),
      (FormError error) => completer.completeError(
        StateError('Consent info update failed: ${error.message}'),
      ),
    );
    return completer.future;
  }

  @override
  Future<void> showConsentFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
      if (error != null) {
        completer.completeError(
          StateError('Consent form failed: ${error.message}'),
        );
        return;
      }
      completer.complete();
    });
    return completer.future;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> isPrivacyOptionsRequired() async {
    final status = await ConsentInformation.instance
        .getPrivacyOptionsRequirementStatus();
    return status == PrivacyOptionsRequirementStatus.required;
  }

  @override
  Future<void> showPrivacyOptionsForm() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (error != null) {
        completer.completeError(
          StateError('Privacy options form failed: ${error.message}'),
        );
        return;
      }
      completer.complete();
    });
    return completer.future;
  }
}

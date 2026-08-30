import 'package:androidircx/monetization/ump_consent_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGatherer implements ConsentGatherer {
  _FakeGatherer({
    this.canRequest = true,
    this.privacyOptionsRequired = false,
    this.updateThrows = false,
  });

  bool canRequest;
  bool privacyOptionsRequired;
  bool updateThrows;
  bool formThrows = false;
  int updates = 0;
  int formsShown = 0;
  int privacyFormsShown = 0;

  @override
  Future<void> requestConsentInfoUpdate() async {
    updates++;
    if (updateThrows) {
      throw StateError('offline');
    }
  }

  @override
  Future<void> showConsentFormIfRequired() async {
    formsShown++;
    if (formThrows) {
      throw StateError('form failed');
    }
  }

  @override
  Future<bool> canRequestAds() async => canRequest;

  @override
  Future<bool> isPrivacyOptionsRequired() async => privacyOptionsRequired;

  @override
  Future<void> showPrivacyOptionsForm() async {
    privacyFormsShown++;
  }
}

void main() {
  test('initializes ads after consent allows requests', () async {
    final gatherer = _FakeGatherer(canRequest: true);
    var adsInitialized = 0;
    final service = UmpConsentService(
      gatherer: gatherer,
      runtimeSupported: true,
      initializeAds: () async => adsInitialized++,
    );

    await service.gatherConsentAndInitAds();

    expect(gatherer.updates, 1);
    expect(gatherer.formsShown, 1);
    expect(adsInitialized, 1);
  });

  test('skips ads init when consent forbids requests', () async {
    final gatherer = _FakeGatherer(canRequest: false);
    var adsInitialized = 0;
    final service = UmpConsentService(
      gatherer: gatherer,
      runtimeSupported: true,
      initializeAds: () async => adsInitialized++,
    );

    await service.gatherConsentAndInitAds();

    expect(adsInitialized, 0);
  });

  test('update/form failures fall through to stored consent', () async {
    final gatherer = _FakeGatherer(canRequest: true, updateThrows: true);
    var adsInitialized = 0;
    final service = UmpConsentService(
      gatherer: gatherer,
      runtimeSupported: true,
      initializeAds: () async => adsInitialized++,
    );

    await service.gatherConsentAndInitAds();
    // Consent update failed (e.g. offline) but a previous session already
    // allowed ads, so the SDK still initializes.
    expect(adsInitialized, 1);

    gatherer.updateThrows = false;
    gatherer.formThrows = true;
    await service.gatherConsentAndInitAds();
    expect(adsInitialized, 2);
  });

  test('does nothing on unsupported runtimes', () async {
    final gatherer = _FakeGatherer();
    var adsInitialized = 0;
    final service = UmpConsentService(
      gatherer: gatherer,
      runtimeSupported: false,
      initializeAds: () async => adsInitialized++,
    );

    await service.gatherConsentAndInitAds();
    expect(gatherer.updates, 0);
    expect(adsInitialized, 0);
    expect(await service.isPrivacyOptionsRequired(), isFalse);
    await service.showPrivacyOptionsForm();
    expect(gatherer.privacyFormsShown, 0);
  });

  test('privacy options surface only when the region requires them', () async {
    final gatherer = _FakeGatherer(privacyOptionsRequired: true);
    final service = UmpConsentService(
      gatherer: gatherer,
      runtimeSupported: true,
      initializeAds: () async {},
    );

    expect(await service.isPrivacyOptionsRequired(), isTrue);
    await service.showPrivacyOptionsForm();
    expect(gatherer.privacyFormsShown, 1);
  });
}

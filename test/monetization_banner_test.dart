import 'package:androidircx/features/monetization/presentation/monetization_banner.dart';
import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _slotKey = Key('monetization-banner-slot');
const _bodyKey = Key('app-body');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<MonetizationController> initializedController() async {
    final controller = MonetizationController();
    await controller.initialize();
    return controller;
  }

  Future<void> pumpBanner(
    WidgetTester tester,
    MonetizationController controller, {
    required bool onboardingCompleted,
    BannerAdLoader? loadBannerAd,
    CanRequestAdsCheck? canRequestAds,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MonetizationBanner(
          controller: controller,
          onboardingCompleted: onboardingCompleted,
          mobileAdsRuntimeSupported: true,
          initializeMobileAds: () async {},
          loadBannerAd: loadBannerAd ?? (_) async {},
          canRequestAds: canRequestAds ?? () async => true,
          child: const SizedBox.expand(key: _bodyKey),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('reserves top banner slot for free users while ad loads', (
    tester,
  ) async {
    final controller = await initializedController();

    await pumpBanner(tester, controller, onboardingCompleted: true);

    expect(find.byKey(_slotKey), findsOneWidget);
    expect(find.text('Banner ad loading'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(_bodyKey)).dy,
      tester.getBottomLeft(find.byKey(_slotKey)).dy,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('does not reserve banner slot after permanent no-ads purchase', (
    tester,
  ) async {
    final controller = await initializedController();
    await controller.processPurchase(
      MonetizationConfig.productRemoveAds,
      'token-1',
    );

    await pumpBanner(tester, controller, onboardingCompleted: true);

    expect(find.byKey(_slotKey), findsNothing);
    expect(tester.getTopLeft(find.byKey(_bodyKey)).dy, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('does not reserve banner slot during rewarded ad-free time', (
    tester,
  ) async {
    final controller = await initializedController();
    await controller.grantTemporaryAdFreeTime(const Duration(minutes: 1));

    await pumpBanner(tester, controller, onboardingCompleted: true);

    expect(find.byKey(_slotKey), findsNothing);
    expect(tester.getTopLeft(find.byKey(_bodyKey)).dy, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('does not request an ad until UMP consent allows it', (
    tester,
  ) async {
    final controller = await initializedController();
    var loadCalls = 0;

    await pumpBanner(
      tester,
      controller,
      onboardingCompleted: true,
      loadBannerAd: (_) async => loadCalls++,
      canRequestAds: () async => false,
    );
    await tester.pump();

    // The slot is still reserved for a free user, but no ad request is fired
    // while consent disallows it.
    expect(loadCalls, 0);
    expect(find.byKey(_slotKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('reports async banner load failures instead of staying loading', (
    tester,
  ) async {
    final controller = await initializedController();
    var loadCalls = 0;

    await pumpBanner(
      tester,
      controller,
      onboardingCompleted: true,
      loadBannerAd: (_) {
        loadCalls += 1;
        return Future<void>.error(StateError('load failed'));
      },
    );
    await tester.pump();

    expect(loadCalls, 1);
    expect(find.byKey(_slotKey), findsOneWidget);
    expect(
      find.text('Banner ad failed: Bad state: load failed'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

import 'package:androidircx/features/settings/presentation/settings_screen.dart';
import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:androidircx/monetization/monetization_scope.dart';
import 'package:androidircx/monetization/rewarded_ad_service.dart';
import 'package:androidircx/monetization/store_purchase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  void useTallSettingsViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> pumpSettingsWithMonetization(
    WidgetTester tester,
    MonetizationController controller,
    RewardedAdService rewardedAdService,
    StorePurchaseService purchaseService,
  ) async {
    await tester.pumpWidget(
      MonetizationScope(
        controller: controller,
        rewardedAdService: rewardedAdService,
        purchaseService: purchaseService,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  double textTop(WidgetTester tester, String text) {
    return tester.getTopLeft(find.text(text).first).dy;
  }

  testWidgets('settings shows premium ads near top before purchase', (
    tester,
  ) async {
    useTallSettingsViewport(tester);
    final controller = MonetizationController();
    final rewardedAdService = RewardedAdService(
      monetizationController: controller,
    );
    final purchaseService = StorePurchaseService(
      monetizationController: controller,
    );

    await controller.initialize();
    await pumpSettingsWithMonetization(
      tester,
      controller,
      rewardedAdService,
      purchaseService,
    );

    expect(find.text('Premium & ads'), findsOneWidget);
    expect(find.text('Free plan'), findsOneWidget);
    expect(find.text('Rewarded ads unavailable here'), findsOneWidget);
    expect(find.text('Remove ads permanently'), findsOneWidget);
    expect(
      textTop(tester, 'Premium & ads'),
      greaterThan(textTop(tester, 'Connections')),
    );
    expect(
      textTop(tester, 'Premium & ads'),
      lessThan(textTop(tester, 'Appearance')),
    );

    purchaseService.dispose();
    rewardedAdService.dispose();
    controller.dispose();
  });

  testWidgets('settings moves premium ads near help after purchase', (
    tester,
  ) async {
    useTallSettingsViewport(tester);
    final controller = MonetizationController();
    final rewardedAdService = RewardedAdService(
      monetizationController: controller,
    );
    final purchaseService = StorePurchaseService(
      monetizationController: controller,
    );

    await controller.initialize();
    await controller.processPurchase(
      MonetizationConfig.productRemoveAds,
      'token-1',
    );
    await pumpSettingsWithMonetization(
      tester,
      controller,
      rewardedAdService,
      purchaseService,
    );

    expect(find.text('Premium & ads'), findsOneWidget);
    expect(find.text('Remove Ads active'), findsOneWidget);
    expect(
      textTop(tester, 'Premium & ads'),
      greaterThan(textTop(tester, 'Channels')),
    );
    expect(textTop(tester, 'Premium & ads'), lessThan(textTop(tester, 'Help')));

    purchaseService.dispose();
    rewardedAdService.dispose();
    controller.dispose();
  });
}

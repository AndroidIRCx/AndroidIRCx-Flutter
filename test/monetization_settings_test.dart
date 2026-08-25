import 'package:androidircx/features/settings/presentation/settings_screen.dart';
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

  testWidgets('settings exposes rewarded ads and no-ads purchase entry', (
    tester,
  ) async {
    final controller = MonetizationController();
    final rewardedAdService = RewardedAdService(
      monetizationController: controller,
    );
    final purchaseService = StorePurchaseService(
      monetizationController: controller,
    );

    await controller.initialize();
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
    await tester.scrollUntilVisible(
      find.text('Premium & ads'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Premium & ads'), findsOneWidget);
    expect(find.text('Free plan'), findsOneWidget);
    expect(find.text('Rewarded ads unavailable here'), findsOneWidget);
    expect(find.text('Remove ads permanently'), findsOneWidget);

    purchaseService.dispose();
    rewardedAdService.dispose();
    controller.dispose();
  });
}

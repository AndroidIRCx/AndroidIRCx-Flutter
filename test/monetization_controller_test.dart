import 'dart:convert';

import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists permanent no-ads purchases and verification tokens', () async {
    final controller = MonetizationController();
    await controller.initialize();

    expect(controller.hasNoAds, isFalse);

    final processed = await controller.processPurchase(
      MonetizationConfig.productRemoveAds,
      'token-1',
    );

    expect(processed, isTrue);
    expect(controller.hasNoAds, isTrue);
    expect(
      controller.hasPurchased(MonetizationConfig.productRemoveAds),
      isTrue,
    );
    expect(
      await controller.getPurchaseToken(MonetizationConfig.productRemoveAds),
      'token-1',
    );

    controller.dispose();

    final restored = MonetizationController();
    await restored.initialize();

    expect(restored.hasNoAds, isTrue);
    expect(restored.hasPurchased(MonetizationConfig.productRemoveAds), isTrue);

    restored.dispose();
  });

  test('expires rewarded ad-free time across restarts', () async {
    SharedPreferences.setMockInitialValues({
      'androidircx.monetization.adFreeTime': jsonEncode(<String, int>{
        'remainingMs': const Duration(minutes: 1).inMilliseconds,
        'lastUpdated': DateTime.now()
            .subtract(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
      }),
    });

    final controller = MonetizationController();
    await controller.initialize();

    expect(controller.hasTemporaryAdFreeTime, isFalse);

    controller.dispose();
  });

  test('grants and resets temporary ad-free time', () async {
    final controller = MonetizationController();
    await controller.initialize();

    await controller.grantTemporaryAdFreeTime(const Duration(minutes: 1));

    expect(controller.hasTemporaryAdFreeTime, isTrue);
    expect(controller.adFreeTimeFormatted, isNot('0s'));

    await controller.resetTemporaryAdFreeTime();

    expect(controller.hasTemporaryAdFreeTime, isFalse);
    expect(controller.adFreeTimeFormatted, '0s');

    controller.dispose();
  });
}

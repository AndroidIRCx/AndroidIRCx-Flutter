import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:androidircx/monetization/rewarded_ad_service.dart';
import 'package:androidircx/monetization/store_purchase_service.dart';
import 'package:flutter/widgets.dart';

class MonetizationScope extends InheritedWidget {
  const MonetizationScope({
    super.key,
    required this.controller,
    required this.rewardedAdService,
    required this.purchaseService,
    required super.child,
  });

  final MonetizationController controller;
  final RewardedAdService rewardedAdService;
  final StorePurchaseService purchaseService;

  static MonetizationScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MonetizationScope>();
    assert(scope != null, 'No MonetizationScope found in context.');
    return scope!;
  }

  static MonetizationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MonetizationScope>();
  }

  @override
  bool updateShouldNotify(MonetizationScope oldWidget) {
    return controller != oldWidget.controller ||
        rewardedAdService != oldWidget.rewardedAdService ||
        purchaseService != oldWidget.purchaseService;
  }
}

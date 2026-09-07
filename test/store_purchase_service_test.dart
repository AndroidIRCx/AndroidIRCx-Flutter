import 'dart:async';

import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:androidircx/monetization/store_purchase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeInAppPurchase implements InAppPurchase {
  final StreamController<List<PurchaseDetails>> controller =
      StreamController<List<PurchaseDetails>>.broadcast();
  bool available = true;
  List<ProductDetails> productList = const <ProductDetails>[];
  Set<String> notFound = const <String>{};
  final List<PurchaseDetails> completed = <PurchaseDetails>[];
  int restoreCalls = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async => ProductDetailsResponse(
    productDetails: productList,
    notFoundIDs: notFound.toList(),
  );

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreCalls++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

PurchaseDetails _purchase(
  String productId,
  PurchaseStatus status, {
  bool pendingComplete = false,
  String server = 'server-token',
  IAPError? error,
}) {
  final details = PurchaseDetails(
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: server,
      source: 'google_play',
    ),
    transactionDate: null,
    status: status,
  );
  details.pendingCompletePurchase = pendingComplete;
  details.error = error;
  return details;
}

Future<StorePurchaseService> _initedService(
  _FakeInAppPurchase store, {
  MonetizationController? controller,
}) async {
  final service = StorePurchaseService(
    monetizationController: controller ?? MonetizationController(),
    store: store,
    storeRuntimeSupported: true,
  );
  await service.initialize();
  return service;
}

Future<void> _emit(
  _FakeInAppPurchase store,
  List<PurchaseDetails> purchases,
) async {
  store.controller.add(purchases);
  // Let the async stream handler (and its awaited persistence) settle.
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('initialize on an unsupported platform reports a mobile-only message',
      () async {
    final service = StorePurchaseService(
      monetizationController: MonetizationController(),
      store: _FakeInAppPurchase(),
      storeRuntimeSupported: false,
    );

    await service.initialize();

    expect(service.storeAvailable, isFalse);
    expect(
      service.statusMessage,
      'Purchases are available only in mobile store builds.',
    );
  });

  test('initialize loads products and records not-found ids when available',
      () async {
    final store = _FakeInAppPurchase()..notFound = {'pro_unlimited'};
    final service = await _initedService(store);

    expect(service.storeAvailable, isTrue);
    expect(service.notFoundProductIds, contains('pro_unlimited'));
  });

  test('initialize surfaces a message when billing is unavailable', () async {
    final store = _FakeInAppPurchase()..available = false;
    final service = await _initedService(store);

    expect(service.storeAvailable, isFalse);
    expect(
      service.statusMessage,
      'Google Play Billing is not available on this device.',
    );
  });

  test('purchased event grants the entitlement and completes the purchase',
      () async {
    final controller = MonetizationController();
    final store = _FakeInAppPurchase();
    final service = await _initedService(store, controller: controller);

    await _emit(store, [
      _purchase(
        MonetizationConfig.productRemoveAds,
        PurchaseStatus.purchased,
        pendingComplete: true,
      ),
    ]);

    expect(controller.hasRemoveAds, isTrue);
    expect(service.statusMessage, 'Purchase complete.');
    expect(service.pendingProductId, isNull);
    expect(store.completed, hasLength(1));
  });

  test('restored event grants the entitlement with a restore message',
      () async {
    final controller = MonetizationController();
    final store = _FakeInAppPurchase();
    final service = await _initedService(store, controller: controller);

    await _emit(store, [
      _purchase(
        MonetizationConfig.productProUnlimited,
        PurchaseStatus.restored,
      ),
    ]);

    expect(controller.hasProUnlimited, isTrue);
    expect(service.statusMessage, 'Purchase restored.');
  });

  test('unknown product id grants nothing', () async {
    final controller = MonetizationController();
    final store = _FakeInAppPurchase();
    final service = await _initedService(store, controller: controller);

    await _emit(store, [
      _purchase('mystery_sku', PurchaseStatus.purchased),
    ]);

    expect(controller.hasNoAds, isFalse);
    expect(service.pendingProductId, isNull);
  });

  test('pending event exposes the pending product id', () async {
    final store = _FakeInAppPurchase();
    final service = await _initedService(store);

    await _emit(store, [
      _purchase(MonetizationConfig.productRemoveAds, PurchaseStatus.pending),
    ]);

    expect(service.pendingProductId, MonetizationConfig.productRemoveAds);
  });

  test('error event clears pending and surfaces the error message', () async {
    final store = _FakeInAppPurchase();
    final service = await _initedService(store);

    await _emit(store, [
      _purchase(
        MonetizationConfig.productRemoveAds,
        PurchaseStatus.error,
        pendingComplete: true,
        error: IAPError(
          source: 'google_play',
          code: 'boom',
          message: 'Card declined',
        ),
      ),
    ]);

    expect(service.pendingProductId, isNull);
    expect(service.statusMessage, 'Card declined');
    expect(store.completed, hasLength(1));
  });

  test('canceled event reports a cancellation', () async {
    final store = _FakeInAppPurchase();
    final service = await _initedService(store);

    await _emit(store, [
      _purchase(MonetizationConfig.productRemoveAds, PurchaseStatus.canceled),
    ]);

    expect(service.statusMessage, 'Purchase canceled.');
    expect(service.pendingProductId, isNull);
  });

  test('buyProduct without a matching product asks to activate it in Play',
      () async {
    final store = _FakeInAppPurchase();
    final service = await _initedService(store);

    await service.buyProduct(MonetizationConfig.productRemoveAds);

    expect(
      service.statusMessage,
      'Create and activate ${MonetizationConfig.productRemoveAds} '
      'in Play Console first.',
    );
  });

  test('restorePurchases forwards to the store when available', () async {
    final store = _FakeInAppPurchase();
    final service = await _initedService(store);

    await service.restorePurchases();

    expect(store.restoreCalls, 1);
    expect(
      service.statusMessage,
      'Restore requested. Google Play will return purchases.',
    );
  });
}

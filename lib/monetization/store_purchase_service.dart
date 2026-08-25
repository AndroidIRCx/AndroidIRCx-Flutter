import 'dart:async';

import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class StorePurchaseService extends ChangeNotifier {
  StorePurchaseService({
    required MonetizationController monetizationController,
    InAppPurchase? store,
  }) : _monetizationController = monetizationController,
       _store = store;

  final MonetizationController _monetizationController;
  final InAppPurchase? _store;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  bool _initialized = false;
  bool _storeAvailable = false;
  bool _loadingProducts = false;
  bool _restoring = false;
  String? _pendingProductId;
  String? _statusMessage;
  List<ProductDetails> _products = const <ProductDetails>[];
  Set<String> _notFoundProductIds = const <String>{};

  bool get initialized => _initialized;
  bool get storeAvailable => _storeAvailable;
  bool get loadingProducts => _loadingProducts;
  bool get restoring => _restoring;
  String? get pendingProductId => _pendingProductId;
  String? get statusMessage => _statusMessage;
  List<ProductDetails> get products => _products;
  Set<String> get notFoundProductIds => _notFoundProductIds;
  InAppPurchase get _effectiveStore => _store ?? InAppPurchase.instance;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _monetizationController.initialize();
    _initialized = true;

    if (!MonetizationConfig.storeRuntimeSupported) {
      _storeAvailable = false;
      _statusMessage = 'Purchases are available only in mobile store builds.';
      notifyListeners();
      return;
    }

    final store = _effectiveStore;
    _purchaseSubscription = store.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        _pendingProductId = null;
        _statusMessage = 'Purchase update failed: $error';
        notifyListeners();
      },
    );

    try {
      _storeAvailable = await store.isAvailable();
      if (_storeAvailable) {
        await loadProducts();
      } else {
        _statusMessage = 'Google Play Billing is not available on this device.';
      }
    } catch (error) {
      _storeAvailable = false;
      _statusMessage = 'Could not initialize purchases: $error';
    }
    notifyListeners();
  }

  Future<void> loadProducts() async {
    if (!_storeAvailable || _loadingProducts) {
      return;
    }
    _loadingProducts = true;
    _statusMessage = null;
    notifyListeners();
    try {
      final response = await _effectiveStore.queryProductDetails(
        MonetizationConfig.productIds,
      );
      _products = response.productDetails;
      _notFoundProductIds = response.notFoundIDs.toSet();
      _statusMessage = response.error?.message;
    } catch (error) {
      _statusMessage = 'Could not load Play products: $error';
    } finally {
      _loadingProducts = false;
      notifyListeners();
    }
  }

  ProductDetails? productDetailsFor(String productId) {
    for (final product in _products) {
      if (product.id == productId) {
        return product;
      }
    }
    return null;
  }

  Future<void> buyProduct(String productId) async {
    await initialize();
    if (!_storeAvailable) {
      _statusMessage = 'Google Play Billing is not available.';
      notifyListeners();
      return;
    }
    final product = productDetailsFor(productId);
    if (product == null) {
      _statusMessage = 'Create and activate $productId in Play Console first.';
      notifyListeners();
      return;
    }

    _pendingProductId = productId;
    _statusMessage = null;
    notifyListeners();
    try {
      final started = await _effectiveStore.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        _pendingProductId = null;
        _statusMessage = 'Purchase flow did not start.';
        notifyListeners();
      }
    } catch (error) {
      _pendingProductId = null;
      _statusMessage = 'Purchase failed: $error';
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    await initialize();
    if (!_storeAvailable) {
      _statusMessage = 'Google Play Billing is not available.';
      notifyListeners();
      return;
    }
    _restoring = true;
    _statusMessage = null;
    notifyListeners();
    try {
      await _effectiveStore.restorePurchases();
      _statusMessage = 'Restore requested. Google Play will return purchases.';
    } catch (error) {
      _statusMessage = 'Restore failed: $error';
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        _pendingProductId = purchase.productID;
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        if (MonetizationConfig.productIds.contains(purchase.productID)) {
          await _monetizationController.processPurchase(
            purchase.productID,
            purchase.verificationData.serverVerificationData,
          );
          _statusMessage = purchase.status == PurchaseStatus.restored
              ? 'Purchase restored.'
              : 'Purchase complete.';
        }
        if (purchase.pendingCompletePurchase) {
          await _effectiveStore.completePurchase(purchase);
        }
        _pendingProductId = null;
      } else if (purchase.status == PurchaseStatus.error) {
        _pendingProductId = null;
        _statusMessage =
            purchase.error?.message ?? 'Purchase failed. Please try again.';
        if (purchase.pendingCompletePurchase) {
          await _effectiveStore.completePurchase(purchase);
        }
      } else if (purchase.status == PurchaseStatus.canceled) {
        _pendingProductId = null;
        _statusMessage = 'Purchase canceled.';
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_purchaseSubscription?.cancel());
    super.dispose();
  }
}

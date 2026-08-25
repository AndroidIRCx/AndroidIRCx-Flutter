import 'dart:async';

import 'package:androidircx/monetization/monetization_config.dart';
import 'package:androidircx/monetization/monetization_controller.dart';
import 'package:androidircx/monetization/store_purchase_service.dart';
import 'package:flutter/material.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({
    super.key,
    required this.monetizationController,
    required this.purchaseService,
  });

  final MonetizationController monetizationController;
  final StorePurchaseService purchaseService;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.purchaseService.initialize());
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.monetizationController,
        widget.purchaseService,
      ]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('AndroidIRCX Premium')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  _tierText(widget.monetizationController.highestTier),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final product in MonetizationConfig.products) ...[
                  _ProductCard(
                    product: product,
                    monetizationController: widget.monetizationController,
                    purchaseService: widget.purchaseService,
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  onPressed:
                      widget.purchaseService.storeAvailable &&
                          !widget.purchaseService.restoring
                      ? widget.purchaseService.restorePurchases
                      : null,
                  icon: widget.purchaseService.restoring
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore),
                  label: const Text('Restore purchases'),
                ),
                if ((widget.purchaseService.statusMessage ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(widget.purchaseService.statusMessage!),
                  ),
                if (widget.purchaseService.notFoundProductIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Missing Play products: '
                      '${widget.purchaseService.notFoundProductIds.join(', ')}',
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Purchases are processed by Google Play. Product IDs must be '
                  'created as one-time in-app products in Play Console before '
                  'prices appear here.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _tierText(PremiumTier tier) {
    return switch (tier) {
      PremiumTier.free => 'Current plan: Free',
      PremiumTier.removeAds => 'Current plan: Remove Ads',
      PremiumTier.proUnlimited => 'Current plan: Pro Unlimited',
      PremiumTier.supporterPro => 'Current plan: Supporter Pro',
    };
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.monetizationController,
    required this.purchaseService,
  });

  final MonetizationProduct product;
  final MonetizationController monetizationController;
  final StorePurchaseService purchaseService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = purchaseService.productDetailsFor(product.id);
    final purchased = monetizationController.hasPurchased(product.id);
    final pending = purchaseService.pendingProductId == product.id;
    final available = purchaseService.storeAvailable && details != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    product.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (product.recommended)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      'Recommended',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(product.description),
            const SizedBox(height: 10),
            for (final feature in product.features)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(feature)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    details?.price ??
                        (MonetizationConfig.storeRuntimeSupported
                            ? 'Create in Play Console'
                            : 'Mobile store only'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                FilledButton(
                  onPressed: purchased || pending || !available
                      ? null
                      : () => purchaseService.buyProduct(product.id),
                  child: pending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(purchased ? 'Purchased' : 'Purchase'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

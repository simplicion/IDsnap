import 'dart:async';

import 'package:engine_billing/src/billing_store.dart';
import 'package:engine_billing/src/model.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:url_launcher/url_launcher.dart';

/// [BillingStore] on the official `in_app_purchase` plugin: Google Play
/// Billing on Android (talks to the Play Store app over IPC; the app itself
/// has no INTERNET permission) and StoreKit 2 on iOS.
class InAppPurchaseStore implements BillingStore {
  InAppPurchaseStore({required this.androidPackageName, InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;

  /// Used for the Play subscription-management deep link.
  final String androidPackageName;
  final InAppPurchase _iap;
  final _details = <String, ProductDetails>{};

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Stream<List<StorePurchase>> get purchaseUpdates =>
      _iap.purchaseStream.map((list) => list.map(_map).toList());

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async {
    final response = await _iap.queryProductDetails(ids);
    final result = <StoreProduct>[];
    for (final id in ids) {
      final candidates = response.productDetails.where((d) => d.id == id);
      if (candidates.isEmpty) continue;
      // Play lists a subscription once per base plan and per offer; use the
      // base plan (no offer), i.e. the plain monthly price.
      final chosen = candidates.firstWhere(
        (d) =>
            d is! GooglePlayProductDetails ||
            d.subscriptionIndex == null ||
            d
                    .productDetails
                    .subscriptionOfferDetails![d.subscriptionIndex!]
                    .offerId ==
                null,
        orElse: () => candidates.first,
      );
      _details[id] = chosen;
      result.add(StoreProduct(id: id, price: chosen.price));
    }
    return result;
  }

  @override
  Future<bool> buy(String productId) async {
    final details = _details[productId];
    if (details == null) return false;
    // Subscriptions and one-time unlocks are both "non-consumable" here.
    return await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  @override
  Future<List<StorePurchase>?> queryOwned() async {
    if (_android) {
      final addition = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      if (response.error != null) return null;
      return response.pastPurchases.map(_map).toList();
    }
    // StoreKit 2: "restore" lists Transaction.currentEntitlements (active
    // subscriptions and owned one-time products) without a sign-in prompt.
    // The batch arrives on the purchase stream.
    final batch = _iap.purchaseStream.first.timeout(
      const Duration(seconds: 10),
    );
    try {
      await _iap.restorePurchases();
      final purchases = await batch;
      return purchases
          .where((p) => p.status == PurchaseStatus.restored)
          .map(_map)
          .toList();
    } on Object {
      unawaited(batch.then((_) {}, onError: (Object _) {}));
      return null;
    }
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    final raw = purchase.raw;
    if (raw is PurchaseDetails && raw.pendingCompletePurchase) {
      await _iap.completePurchase(raw);
    }
  }

  @override
  Future<bool> openManageSubscriptions(String productId) {
    // Both links are handled by the store app itself (Play Store / App
    // Store), which does the networking; IDSnap never connects.
    final uri = _android
        ? Uri.https('play.google.com', '/store/account/subscriptions', {
            'sku': productId,
            'package': androidPackageName,
          })
        : Uri.https('apps.apple.com', '/account/subscriptions');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  StorePurchase _map(PurchaseDetails p) {
    final android = p is GooglePlayPurchaseDetails
        ? p.billingClientPurchase
        : null;
    final millis = int.tryParse(p.transactionDate ?? '');
    return StorePurchase(
      productId: p.productID,
      status: switch (p.status) {
        PurchaseStatus.pending => StorePurchaseStatus.pending,
        PurchaseStatus.purchased => StorePurchaseStatus.purchased,
        PurchaseStatus.restored => StorePurchaseStatus.restored,
        PurchaseStatus.error => StorePurchaseStatus.error,
        PurchaseStatus.canceled => StorePurchaseStatus.canceled,
      },
      purchaseId: p.purchaseID,
      transactionDate: millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      pendingCompletePurchase: p.pendingCompletePurchase,
      errorMessage: p.error?.message,
      signedData: android?.originalJson,
      signature: android?.signature,
      autoRenewing: android?.isAutoRenewing,
      raw: p,
    );
  }
}

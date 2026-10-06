import 'dart:async';

import 'package:engine_billing/engine_billing.dart';

/// Scriptable [BillingStore]: tests push purchase updates and inspect what
/// the engine completed (acknowledged).
class FakeBillingStore implements BillingStore {
  FakeBillingStore({
    this.available = true,
    this.products = const {
      BillingProducts.monthly: r'$1.99',
      BillingProducts.lifetime: r'$49.99',
    },
  });

  bool available;
  Map<String, String> products;

  /// What [queryOwned] returns; null = the store couldn't answer.
  List<StorePurchase>? owned = const [];

  /// Called by [buy]; return false to simulate a flow that couldn't start.
  bool Function(String productId) onBuy = (_) => true;

  final bought = <String>[];
  final completed = <StorePurchase>[];
  final _updates = StreamController<List<StorePurchase>>.broadcast();
  int manageOpened = 0;

  void emit(List<StorePurchase> purchases) => _updates.add(purchases);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<List<StorePurchase>> get purchaseUpdates => _updates.stream;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async => [
    for (final id in ids)
      if (products[id] != null) StoreProduct(id: id, price: products[id]!),
  ];

  @override
  Future<bool> buy(String productId) async {
    bought.add(productId);
    return onBuy(productId);
  }

  @override
  Future<List<StorePurchase>?> queryOwned() async => owned;

  @override
  Future<void> complete(StorePurchase purchase) async =>
      completed.add(purchase);

  @override
  Future<bool> openManageSubscriptions(String productId) async {
    manageOpened++;
    return true;
  }

  Future<void> close() => _updates.close();
}

StorePurchase purchase(
  String productId, {
  StorePurchaseStatus status = StorePurchaseStatus.purchased,
  bool needsAck = true,
  DateTime? at,
  String? signedData,
  String? signature,
  bool? autoRenewing,
}) => StorePurchase(
  productId: productId,
  status: status,
  pendingCompletePurchase: needsAck,
  transactionDate: at,
  signedData: signedData,
  signature: signature,
  autoRenewing: autoRenewing,
);

/// Mutable clock for tests.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

import 'package:engine_billing/src/model.dart';

/// The platform store (Google Play Billing, StoreKit) behind a small
/// interface, so the engine is tested with a fake store and never needs
/// the plugin in unit tests.
abstract interface class BillingStore {
  /// False on devices without a store (sideloaded builds, emulators without
  /// Play, tests).
  Future<bool> isAvailable();

  /// Every purchase update: new purchases, pending payments, errors,
  /// cancellations and restored purchases.
  Stream<List<StorePurchase>> get purchaseUpdates;

  /// Localized product details. Missing IDs are simply absent.
  Future<List<StoreProduct>> queryProducts(Set<String> ids);

  /// Starts the store's purchase sheet. Returns false if it couldn't start.
  /// The outcome arrives on [purchaseUpdates].
  Future<bool> buy(String productId);

  /// What the store says this account owns right now: active subscriptions
  /// and owned one-time products (Android: queryPurchasesAsync, answered
  /// by the Play Store app's cache; iOS: StoreKit 2 current entitlements).
  /// `null` when the store couldn't answer.
  Future<List<StorePurchase>?> queryOwned();

  /// Acknowledges (Android) / finishes (iOS) a purchase.
  Future<void> complete(StorePurchase purchase);

  /// Opens the store's own subscription management page (hands off to the
  /// Play Store / App Store app). Returns false if nothing could open it.
  Future<bool> openManageSubscriptions(String productId);
}

/// A store that is never available. Used when billing is not supported on
/// the platform (desktop, web) and as a safe default.
class UnavailableBillingStore implements BillingStore {
  const UnavailableBillingStore();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Stream<List<StorePurchase>> get purchaseUpdates => const Stream.empty();

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async => const [];

  @override
  Future<bool> buy(String productId) async => false;

  @override
  Future<List<StorePurchase>?> queryOwned() async => null;

  @override
  Future<void> complete(StorePurchase purchase) async {}

  @override
  Future<bool> openManageSubscriptions(String productId) async => false;
}

import 'package:flutter/foundation.dart';

/// Store product IDs. They must match Play Console and App Store Connect
/// exactly (see docs/adr/0009-offline-billing-entitlements.md).
abstract final class BillingProducts {
  /// Auto-renewing monthly subscription (Play: subscription with one
  /// monthly base plan; App Store: auto-renewable subscription).
  static const monthly = 'idsnap_pro_monthly';

  /// One-time, non-consumable "lifetime" unlock.
  static const lifetime = 'idsnap_pro_lifetime';

  static const all = {monthly, lifetime};

  /// Shown only when the store can't be reached (tests, sideloaded builds,
  /// no Play Store), and labelled as such. Real prices always come from the
  /// store, localized. The UI adds "/month" and "once".
  static const fallbackMonthlyPrice = r'$2';
  static const fallbackLifetimePrice = r'$50';
}

enum BillingPlan {
  monthly(BillingProducts.monthly),
  lifetime(BillingProducts.lifetime);

  const BillingPlan(this.productId);
  final String productId;

  static BillingPlan? fromProductId(String id) => switch (id) {
    BillingProducts.monthly => monthly,
    BillingProducts.lifetime => lifetime,
    _ => null,
  };
}

/// What the user is entitled to right now.
enum EntitlementKind { trial, monthly, lifetime, expired }

/// Why Pro is not active.
enum LapseReason { trialEnded, subscriptionEnded, clockTampered }

/// Resolved entitlement, recomputed from the trial record, the cached
/// verified purchase and the current time.
@immutable
class BillingStatus {
  const BillingStatus({
    required this.kind,
    this.trialEndsAt,
    this.trialDaysLeft = 0,
    this.expiresAt,
    this.willRenew = false,
    this.inGracePeriod = false,
    this.lapseReason,
    this.purchasePending = false,
  });

  final EntitlementKind kind;

  /// End of the 30-day trial (null when the trial record is unknown).
  final DateTime? trialEndsAt;

  /// Whole days of trial left, rounded up (30 on the first day, 1 on the
  /// last). 0 once the trial is over.
  final int trialDaysLeft;

  /// Monthly plan: end of the current (estimated) billing period.
  final DateTime? expiresAt;

  /// Monthly plan: the store reported auto-renew as on.
  final bool willRenew;

  /// Monthly plan honoured past its expiry because the store couldn't be
  /// reached to confirm a renewal.
  final bool inGracePeriod;

  /// Set when [kind] is [EntitlementKind.expired].
  final LapseReason? lapseReason;

  /// A purchase is waiting for payment (e.g. cash at a shop). Pro unlocks
  /// when the store confirms it.
  final bool purchasePending;

  bool get isEntitled => kind != EntitlementKind.expired;

  BillingStatus withPending({required bool pending}) => BillingStatus(
    kind: kind,
    trialEndsAt: trialEndsAt,
    trialDaysLeft: trialDaysLeft,
    expiresAt: expiresAt,
    willRenew: willRenew,
    inGracePeriod: inGracePeriod,
    lapseReason: lapseReason,
    purchasePending: pending,
  );

  @override
  bool operator ==(Object other) =>
      other is BillingStatus &&
      other.kind == kind &&
      other.trialEndsAt == trialEndsAt &&
      other.trialDaysLeft == trialDaysLeft &&
      other.expiresAt == expiresAt &&
      other.willRenew == willRenew &&
      other.inGracePeriod == inGracePeriod &&
      other.lapseReason == lapseReason &&
      other.purchasePending == purchasePending;

  @override
  int get hashCode => Object.hash(
    kind,
    trialEndsAt,
    trialDaysLeft,
    expiresAt,
    willRenew,
    inGracePeriod,
    lapseReason,
    purchasePending,
  );

  @override
  String toString() =>
      'BillingStatus($kind, trialDaysLeft: $trialDaysLeft, '
      'expiresAt: $expiresAt, grace: $inGracePeriod, reason: $lapseReason, '
      'pending: $purchasePending)';
}

/// A plan's display price.
@immutable
class PlanPrice {
  const PlanPrice({
    required this.plan,
    required this.price,
    required this.fromStore,
  });

  final BillingPlan plan;

  /// Localized store price ("₹169.00", "$1.99"), or the labelled fallback.
  final String price;

  /// False when [price] is the fallback because the store is unavailable.
  final bool fromStore;
}

enum PurchaseResultKind {
  /// Verified and unlocked.
  purchased,

  /// Waiting for payment; unlocks later.
  pending,

  /// The user closed the store sheet.
  cancelled,

  /// Store error, verification failure or the flow couldn't start.
  failed,

  /// No store on this device (sideloaded build, no Play Store, tests).
  storeUnavailable,
}

@immutable
class PurchaseResult {
  const PurchaseResult(this.kind, {this.message});

  final PurchaseResultKind kind;

  /// Short, user-presentable explanation for failures.
  final String? message;

  @override
  String toString() => 'PurchaseResult($kind, $message)';
}

@immutable
class RestoreResult {
  const RestoreResult({required this.restored, this.message});

  /// A monthly plan or lifetime purchase is now active.
  final bool restored;
  final String? message;
}

// ── Store-facing value types (platform neutral; see BillingStore) ──────────

enum StorePurchaseStatus { pending, purchased, restored, error, canceled }

@immutable
class StoreProduct {
  const StoreProduct({required this.id, required this.price});

  final String id;

  /// Localized, formatted price from the store.
  final String price;
}

/// One purchase update from the store, normalised across platforms.
class StorePurchase {
  StorePurchase({
    required this.productId,
    required this.status,
    this.purchaseId,
    this.transactionDate,
    this.pendingCompletePurchase = false,
    this.errorMessage,
    this.signedData,
    this.signature,
    this.autoRenewing,
    this.raw,
  });

  final String productId;
  final StorePurchaseStatus status;
  final String? purchaseId;

  /// Purchase time (Android: original purchase time of the subscription;
  /// iOS: this transaction, so a renewal moves it forward).
  final DateTime? transactionDate;

  /// True until the purchase is acknowledged / finished. On Android an
  /// unacknowledged purchase is refunded after 3 days.
  final bool pendingCompletePurchase;
  final String? errorMessage;

  /// Android only: the purchase's original JSON and its RSA-SHA1 signature,
  /// for local verification against the Play license key.
  final String? signedData;
  final String? signature;

  /// Android subscriptions: auto-renew on.
  final bool? autoRenewing;

  /// The platform object, needed to complete the purchase.
  final Object? raw;

  @override
  String toString() => 'StorePurchase($productId, $status)';
}

// IDSnap Pro entitlements: what is free, what needs Pro after the free
// day, and the port the app wires to the licence engine.
// See docs/adr/0012-180pay-licence-server.md (supersedes ADR-0009).
//
// SWITCHED OFF BY DEFAULT (docs/adr/0013-free-with-ads.md): the default
// build is free with ads (`IDSNAP_MONETIZATION=ads`), where the state is
// always [FreeEntitlement] and nothing below is ever locked. All of this
// stays in place for the `licence` and `store` modes.

/// Every capability the paywall policy knows about. Gate a new feature by
/// adding it here AND to [featurePolicy], then call `ensurePro(context,
/// ref, ProFeature.x)` at its entry point (see pro_gate.dart).
enum ProFeature {
  // ── Free forever (the user's own data is never held hostage) ──────────────
  viewDocuments('Open and view documents'),
  shareExport('Share and export documents'),
  browseFolders('Browse folders'),
  authenticator('Authenticator codes'),
  appLockUnlock('App Lock and folder unlock'),
  readSecureNotes('Read secure notes'),
  exportAllData('Export all data'),
  importFiles('Add files to the vault'),

  // ── Pro after the trial: creating or processing documents ─────────────────
  scan('Scan documents'),
  idCard('ID card copies'),
  passportPhoto('Passport-size photos'),
  kits('Application kits'),
  ocr('Extract text (OCR)'),
  pdfTools('PDF tools'),
  imageTools('Image tools'),
  convert('Convert files'),
  signature('Signatures'),
  protectFile('Protect files with a password'),
  qrTools('QR code generator'),
  secureNotes('New secure notes'),
  batch('Batch processing');

  const ProFeature(this.label);

  /// Short user-facing name ("Application kits").
  final String label;
}

enum FeatureAccess {
  /// Always available, also after the free day.
  free,

  /// Available during the free day and with a paid plan.
  pro,
}

/// THE policy: the single place that decides free vs Pro. Change a line
/// here to move a feature; nothing else needs editing. Rule of thumb from
/// the product owner: opening, viewing, sharing and exporting what the
/// user already has is free forever (and the authenticator's login codes
/// are never paywalled); creating or processing documents is Pro.
const Map<ProFeature, FeatureAccess> featurePolicy = {
  ProFeature.viewDocuments: FeatureAccess.free,
  ProFeature.shareExport: FeatureAccess.free,
  ProFeature.browseFolders: FeatureAccess.free,
  ProFeature.authenticator: FeatureAccess.free,
  ProFeature.appLockUnlock: FeatureAccess.free,
  ProFeature.readSecureNotes: FeatureAccess.free,
  ProFeature.exportAllData: FeatureAccess.free,
  ProFeature.importFiles: FeatureAccess.free,
  ProFeature.scan: FeatureAccess.pro,
  ProFeature.idCard: FeatureAccess.pro,
  ProFeature.passportPhoto: FeatureAccess.pro,
  ProFeature.kits: FeatureAccess.pro,
  ProFeature.ocr: FeatureAccess.pro,
  ProFeature.pdfTools: FeatureAccess.pro,
  ProFeature.imageTools: FeatureAccess.pro,
  ProFeature.convert: FeatureAccess.pro,
  ProFeature.signature: FeatureAccess.pro,
  ProFeature.protectFile: FeatureAccess.pro,
  ProFeature.qrTools: FeatureAccess.pro,
  ProFeature.secureNotes: FeatureAccess.pro,
  ProFeature.batch: FeatureAccess.pro,
};

/// True if [feature] needs Pro once the free day is over. A feature missing
/// from [featurePolicy] counts as Pro (a test keeps the map complete).
bool requiresPro(ProFeature feature) =>
    (featurePolicy[feature] ?? FeatureAccess.pro) == FeatureAccess.pro;

/// Whether [feature] can be used in [state].
bool canUse(ProFeature feature, EntitlementState state) =>
    !requiresPro(feature) || state.isEntitled;

/// Paid plans. There is no lifetime plan (ADR-0012).
enum ProPlan {
  /// Auto-renewing monthly subscription.
  monthly,

  /// Prepaid N × 24 h; ends by itself.
  dayPass,
}

/// Why Pro isn't active.
enum LapseReason {
  /// The free day ended.
  trialEnded,

  /// The paid days ran out.
  dayPassEnded,

  /// The monthly plan ended (cancelled or not renewed).
  subscriptionEnded,

  /// The phone's clock was set back past a time the app already saw.
  clockTampered,

  /// No licence yet and no internet: the device has never registered, so
  /// the free day hasn't started. Connecting once starts it.
  notActivated,
}

/// The user's entitlement right now.
sealed class EntitlementState {
  const EntitlementState({this.purchasePending = false});

  /// A payment was started and the app is waiting for the server to
  /// confirm it.
  final bool purchasePending;

  bool get isEntitled;

  /// When access ends, if it ends (null when unknown).
  DateTime? get accessEndsAt;
}

/// The free, ad-supported app (`IDSNAP_MONETIZATION=ads`): every feature
/// is unlocked for everyone, for good. There is no trial, no plan and
/// nothing to buy.
final class FreeEntitlement extends EntitlementState {
  const FreeEntitlement();

  @override
  DateTime? get accessEndsAt => null;

  @override
  bool get isEntitled => true;
}

/// Free day with every feature, from the device's first registration.
final class TrialEntitlement extends EntitlementState {
  const TrialEntitlement({required this.endsAt, super.purchasePending});

  final DateTime endsAt;

  @override
  DateTime get accessEndsAt => endsAt;

  @override
  bool get isEntitled => true;
}

/// Prepaid day pass.
final class DayPassEntitlement extends EntitlementState {
  const DayPassEntitlement({required this.expiresAt, super.purchasePending});

  final DateTime expiresAt;

  @override
  DateTime get accessEndsAt => expiresAt;

  @override
  bool get isEntitled => true;
}

/// Monthly subscription.
final class MonthlyEntitlement extends EntitlementState {
  const MonthlyEntitlement({
    this.renewsAt,
    this.expiresAt,
    this.willRenew = true,
    this.inGracePeriod = false,
    super.purchasePending,
  });

  /// End of the paid period (the renewal date when [willRenew]).
  final DateTime? renewsAt;

  /// When access ends if no renewal is confirmed: [renewsAt] plus a few
  /// days of grace for a renewing plan, [renewsAt] for a cancelled one.
  final DateTime? expiresAt;
  final bool willRenew;

  /// Past [renewsAt], still unlocked while the renewal is confirmed.
  final bool inGracePeriod;

  @override
  DateTime? get accessEndsAt => expiresAt;

  @override
  bool get isEntitled => true;
}

/// Free day over (or plan ended, or never activated): free features only.
final class ExpiredEntitlement extends EntitlementState {
  const ExpiredEntitlement({
    required this.reason,
    this.endedAt,
    super.purchasePending,
  });

  final LapseReason reason;
  final DateTime? endedAt;

  @override
  DateTime? get accessEndsAt => endedAt;

  @override
  bool get isEntitled => false;
}

/// "5 h", "1 day 3 h", "45 min": how long until [end], rounded up.
/// "0 min" once passed.
String formatTimeLeft(DateTime end, DateTime now) {
  final left = end.difference(now);
  if (left <= Duration.zero) return '0 min';
  final minutes = (left.inSeconds / 60).ceil();
  if (minutes < 60) return '$minutes min';
  final hours = (minutes / 60).ceil();
  if (hours < 48) return '$hours h';
  final days = hours ~/ 24;
  final rest = hours % 24;
  return rest == 0 ? '$days days' : '$days days $rest h';
}

/// Prices and limits for the paywall. They come from the licence server;
/// the fallback is shown only when it can't be reached, labelled
/// approximate.
class ProPricing {
  const ProPricing({
    required this.dayPriceCents,
    required this.monthPriceCents,
    required this.currency,
    required this.minDays,
    required this.maxDays,
    required this.fromServer,
  });

  final int dayPriceCents;
  final int monthPriceCents;
  final String currency;
  final int minDays;
  final int maxDays;

  /// False for [fallbackPricing]; the UI must say the prices are
  /// approximate.
  final bool fromServer;

  int dayPassCents(int days) => days * dayPriceCents;

  /// True when [days] of day passes cost as much as a month, or more.
  bool monthlyIsCheaper(int days) => dayPassCents(days) >= monthPriceCents;

  /// "$2.50", "$0.10", "€3.00"; "2.50 CHF" for other currencies.
  String format(int cents) {
    final amount = (cents / 100).toStringAsFixed(2);
    final symbol = switch (currency) {
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      'INR' => '₹',
      _ => null,
    };
    return symbol == null ? '$amount $currency' : '$symbol$amount';
  }
}

/// Used until the server has been reached. Matches the server defaults
/// (ADR-0012) but is labelled approximate in the UI.
const fallbackPricing = ProPricing(
  dayPriceCents: 10,
  monthPriceCents: 250,
  currency: 'USD',
  minDays: 1,
  maxDays: 24,
  fromServer: false,
);

/// What the user asked to buy.
class ProPurchase {
  const ProPurchase.monthly() : plan = ProPlan.monthly, days = 0;
  const ProPurchase.dayPass(this.days) : plan = ProPlan.dayPass;

  final ProPlan plan;

  /// Day pass only.
  final int days;
}

enum PurchaseOutcomeKind {
  /// Paid and unlocked.
  purchased,

  /// Checkout opened but the payment isn't confirmed yet. Unlocks by
  /// itself when it is (the app checks again on resume).
  pending,
  cancelled,
  failed,

  /// No internet, or no payment service in this build.
  unavailable,
}

class PurchaseOutcome {
  const PurchaseOutcome(this.kind, {this.message});

  final PurchaseOutcomeKind kind;
  final String? message;
}

class LicenceRefreshOutcome {
  const LicenceRefreshOutcome({required this.ok, this.message});

  /// The server answered and the licence on this phone is up to date.
  final bool ok;
  final String? message;
}

/// Port for licensing (wired in the app bootstrap to engine_billing).
/// Works offline: [current] comes from the signed licence stored on the
/// phone, checked on every read.
abstract interface class EntitlementService {
  /// Recomputed on every read (a licence ending mid-session lapses on time).
  EntitlementState get current;

  /// Emits when purchases or refreshes change the state.
  Stream<EntitlementState> get changes;

  /// Prices from the server, or [fallbackPricing].
  Future<ProPricing> pricing();

  /// Opens checkout in the browser and waits (about two minutes) for the
  /// server to confirm the payment.
  Future<PurchaseOutcome> purchase(ProPurchase request);

  /// "Refresh licence": asks the server for the current licence now.
  Future<LicenceRefreshOutcome> refreshLicence();

  /// Background refresh (app start and resume). Never throws.
  Future<void> refresh();

  /// Opens the payment provider's page to manage or cancel the monthly
  /// plan. False if it couldn't be opened.
  Future<bool> openManageSubscription();
}

/// An [EntitlementService] with a fixed state and no server. The default
/// when licensing isn't wired (tests, the docs and lab apps): everything is
/// unlocked, so existing tests and tools behave as before.
class StaticEntitlementService implements EntitlementService {
  const StaticEntitlementService([this.state = const MonthlyEntitlement()]);

  final EntitlementState state;

  @override
  EntitlementState get current => state;

  @override
  Stream<EntitlementState> get changes => const Stream.empty();

  @override
  Future<ProPricing> pricing() async => fallbackPricing;

  @override
  Future<PurchaseOutcome> purchase(ProPurchase request) async =>
      const PurchaseOutcome(PurchaseOutcomeKind.unavailable);

  @override
  Future<LicenceRefreshOutcome> refreshLicence() async =>
      const LicenceRefreshOutcome(
        ok: false,
        message: "Licensing isn't available in this build.",
      );

  @override
  Future<void> refresh() async {}

  @override
  Future<bool> openManageSubscription() async => false;
}

/// The [EntitlementService] of the free, ad-supported app: everything is
/// unlocked, permanently. No licence, no server, no network.
class FreeEntitlementService implements EntitlementService {
  const FreeEntitlementService();

  @override
  EntitlementState get current => const FreeEntitlement();

  @override
  Stream<EntitlementState> get changes => const Stream.empty();

  @override
  Future<ProPricing> pricing() async => fallbackPricing;

  @override
  Future<PurchaseOutcome> purchase(ProPurchase request) async =>
      const PurchaseOutcome(
        PurchaseOutcomeKind.unavailable,
        message: 'IDSnap is free. There is nothing to buy.',
      );

  @override
  Future<LicenceRefreshOutcome> refreshLicence() async =>
      const LicenceRefreshOutcome(ok: true);

  @override
  Future<void> refresh() async {}

  @override
  Future<bool> openManageSubscription() async => false;
}

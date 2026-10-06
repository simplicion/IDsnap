import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How this build earns money. ONE build-time switch:
/// `--dart-define=IDSNAP_MONETIZATION=ads|licence|store` (default `ads`).
/// See docs/adr/0013-free-with-ads.md.
enum MonetizationMode {
  /// Free: every feature unlocked for everyone, no trial, no paywall, no
  /// licence server. Revenue comes from ads on a few screens.
  ads,

  /// IDSnap Pro through the licence server and 180 Pay (ADR-0012).
  /// No ads.
  licence,

  /// IDSnap Pro through Google Play Billing / StoreKit (ADR-0009).
  /// No ads.
  store;

  /// The mode named by [value], or null when it isn't one.
  static MonetizationMode? parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'ads' => ads,
        'licence' || 'license' => licence,
        'store' => store,
        _ => null,
      };

  /// Billing is switched off: nothing is sold and nothing is locked.
  bool get isFree => this == ads;

  /// Ads may be shown (only where the placement policy allows them).
  bool get showsAds => this == ads;
}

/// The raw build setting.
const monetizationDefine = String.fromEnvironment(
  'IDSNAP_MONETIZATION',
  defaultValue: 'ads',
);

/// A monetization setting that must not ship.
class MonetizationConfigError extends Error {
  MonetizationConfigError(this.message);

  final String message;

  @override
  String toString() => 'MonetizationConfigError: $message';
}

/// The mode of this build. Throws [MonetizationConfigError] for an
/// unknown value, so a typo can never silently pick a business model.
MonetizationMode resolveMonetizationMode([String value = monetizationDefine]) =>
    MonetizationMode.parse(value) ??
    (throw MonetizationConfigError(
      'IDSNAP_MONETIZATION must be ads, licence or store (got "$value").',
    ));

/// The mode every screen reads. Tests of the paid modes override it:
/// `monetizationModeProvider.overrideWithValue(MonetizationMode.licence)`.
final monetizationModeProvider = Provider<MonetizationMode>(
  (ref) => resolveMonetizationMode(),
);

// ── The privacy statement (use these words everywhere) ─────────────────────

/// Free build with ads (ADR-0013, amending ADR-0008).
const adsPrivacyLine =
    'Your documents, IDs and codes never leave this phone. IDSnap is free '
    'and shows ads on a few screens; the ads are provided by Google, which '
    "may use your device's advertising ID.";

/// Paid builds (ADR-0012): no ads; the internet is used for licensing.
const paidPrivacyLine =
    'Your documents never leave this phone. IDSnap connects to the internet '
    'only to check your licence and for payments.';

/// The one-sentence privacy statement for [mode].
String privacyLineFor(MonetizationMode mode) =>
    mode.showsAds ? adsPrivacyLine : paidPrivacyLine;

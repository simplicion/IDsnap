import 'package:docscan_contracts/src/ad_placement.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the consent platform knows about this user's ad choices.
enum AdConsentStatus {
  /// Not asked yet (or the consent service couldn't be reached).
  unknown,

  /// No consent needed where this user is.
  notRequired,

  /// The user answered the consent form.
  obtained,

  /// Consent is needed and hasn't been given: no ads are requested.
  required,
}

/// Colours for a native ad, taken from the app theme so the ad matches
/// the design system (the card around it keeps it distinct from content).
@immutable
class AdNativeStyle {
  const AdNativeStyle({
    required this.background,
    required this.primaryText,
    required this.secondaryText,
    required this.buttonBackground,
    required this.buttonText,
  });

  final Color background;
  final Color primaryText;
  final Color secondaryText;
  final Color buttonBackground;
  final Color buttonText;

  @override
  bool operator ==(Object other) =>
      other is AdNativeStyle &&
      other.background == background &&
      other.primaryText == primaryText &&
      other.secondaryText == secondaryText &&
      other.buttonBackground == buttonBackground &&
      other.buttonText == buttonText;

  @override
  int get hashCode => Object.hash(
    background,
    primaryText,
    secondaryText,
    buttonBackground,
    buttonText,
  );
}

/// A native ad that is already loaded. Show [view] once, then [dispose].
abstract interface class AdNativeHandle {
  /// The ad itself (headline, "Ad" badge, AdChoices, button), sized by
  /// its [AdNativeSize].
  Widget get view;

  void dispose();
}

/// Port for advertising (ADR-0013). Wired in the app bootstrap to
/// engine_ads; everywhere else it is [NoopAdsService], so no widget test
/// needs the ads plugin.
///
/// Features never call this directly: they use `AdBannerSlot`,
/// `AdNativeSlot` and `maybeShowResultInterstitial` (ad_widgets.dart),
/// which apply the placement policy (ad_placement.dart) first.
///
/// Notifies its listeners when [canShowAds], [consentStatus] or
/// [privacyOptionsRequired] change. No method throws, and none makes the
/// user wait for an ad.
abstract interface class AdsService implements Listenable {
  /// Consent first: asks the consent platform, shows its form if one is
  /// required, and starts the ads SDK only when ads may be requested.
  /// Idempotent. Called by the first ad slot that becomes visible, so it
  /// never runs before the vault has opened or over a locked app.
  Future<void> initialize();

  /// Consent is resolved and the SDK is running.
  bool get canShowAds;

  AdConsentStatus get consentStatus;

  /// Settings must offer "Ad privacy choices" (see [openPrivacyOptions]).
  bool get privacyOptionsRequired;

  /// Height of the anchored banner for [width] logical pixels, or null
  /// when no banner should be shown now (not ready, last load failed).
  Future<double?> resolveBannerHeight(int width);

  /// Builds the banner for a slot that reserved [resolveBannerHeight].
  /// The widget loads its ad, stays empty if that fails, and disposes its
  /// platform view with itself.
  Widget buildBanner({required int width});

  /// A native ad that is ALREADY loaded for [size] and [style], or null.
  /// Never waits: when none is ready the caller shows nothing. Either way
  /// the next ones are preloaded in the background for later screens.
  AdNativeHandle? takeNative(AdNativeSize size, AdNativeStyle style);

  /// Preloads one interstitial in the background.
  Future<void> loadInterstitial();

  /// Shows the preloaded interstitial if the frequency cap allows one
  /// now. False (at once) when it doesn't or when none is loaded.
  Future<bool> maybeShowInterstitial();

  /// Reopens the consent platform's privacy options form.
  Future<void> openPrivacyOptions();
}

/// No ads: paid builds, tests, desktop, and
/// `--dart-define=IDSNAP_ADS_DISABLED=true`.
class NoopAdsService implements AdsService {
  const NoopAdsService();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  Future<void> initialize() async {}

  @override
  bool get canShowAds => false;

  @override
  AdConsentStatus get consentStatus => AdConsentStatus.unknown;

  @override
  bool get privacyOptionsRequired => false;

  @override
  Future<double?> resolveBannerHeight(int width) async => null;

  @override
  Widget buildBanner({required int width}) => const SizedBox.shrink();

  @override
  AdNativeHandle? takeNative(AdNativeSize size, AdNativeStyle style) => null;

  @override
  Future<void> loadInterstitial() async {}

  @override
  Future<bool> maybeShowInterstitial() async => false;

  @override
  Future<void> openPrivacyOptions() async {}
}

/// Overridden in apps/scanner/lib/bootstrap.dart (ads mode, on a phone).
final adsServiceProvider = Provider<AdsService>(
  (ref) => const NoopAdsService(),
);

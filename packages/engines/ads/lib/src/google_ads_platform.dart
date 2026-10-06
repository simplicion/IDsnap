import 'dart:async';

import 'package:engine_ads/src/ads_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// [AdsPlatform] on the official `google_mobile_ads` plugin: AdMob for the
/// ads, the User Messaging Platform (UMP) for consent.
///
/// Choices made here (ADR-0013):
/// - The advertising ID on iOS (IDFA) is never requested, so there is no
///   App Tracking Transparency prompt.
/// - IDSnap is not directed at children: no child or teen treatment is
///   declared, and consent requests say the user is not under the age of
///   consent.
/// - Banners are anchored adaptive banners; interstitials are plain
///   full-screen ads; native ads use Google's native templates, which
///   draw the "Ad" badge and the AdChoices icon themselves. No app-open
///   or rewarded formats.
class GoogleAdsPlatform implements AdsPlatform {
  GoogleAdsPlatform();

  /// Native side: `MainActivity.kt` / `AppDelegate.swift`. Reads the IAB
  /// TCF values that UMP stores in the app's default preferences.
  static const consentChannelName = 'idsnap/ad_consent';
  static const _consentChannel = MethodChannel(consentChannelName);

  @override
  Future<bool> requestConsentInfoUpdate() {
    final done = Completer<bool>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(tagForUnderAgeOfConsent: false),
        () => done.isCompleted ? null : done.complete(true),
        (_) => done.isCompleted ? null : done.complete(false),
      );
    } on Object {
      return Future.value(false);
    }
    // Offline phones must not wait on the consent server.
    return done.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
  }

  @override
  Future<void> showConsentFormIfRequired() async {
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
    } on Object {
      // canRequestAds() decides what happens next.
    }
  }

  @override
  Future<PlatformConsentStatus> consentStatus() async {
    try {
      return switch (await ConsentInformation.instance.getConsentStatus()) {
        ConsentStatus.notRequired => PlatformConsentStatus.notRequired,
        ConsentStatus.obtained => PlatformConsentStatus.obtained,
        ConsentStatus.required => PlatformConsentStatus.required,
        ConsentStatus.unknown => PlatformConsentStatus.unknown,
      };
    } on Object {
      return PlatformConsentStatus.unknown;
    }
  }

  @override
  Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptionsForm() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((_) {});
    } on Object {
      // The form did not open; nothing changed.
    }
  }

  /// Personalised ads need the user's consent to TCF purposes 1 (store
  /// and access information on the device), 3 and 4 (personalised ads
  /// profile and selection) wherever the GDPR applies. Where it does not
  /// apply, the SDK itself honours regional opt-outs (US states).
  /// Anything unreadable counts as "not allowed".
  @override
  Future<bool> personalizedAdsAllowed() async {
    try {
      final tcf = await _consentChannel.invokeMapMethod<String, Object?>('tcf');
      return personalizedAllowedByTcf(
        gdprApplies: (tcf?['gdprApplies'] as num?)?.toInt(),
        purposeConsents: tcf?['purposeConsents'] as String?,
      );
    } on Object {
      return false;
    }
  }

  /// [gdprApplies]: `IABTCF_gdprApplies` (1, 0 or null when unset);
  /// [purposeConsents]: `IABTCF_PurposeConsents`, one '0'/'1' per purpose.
  @visibleForTesting
  static bool personalizedAllowedByTcf({
    required int? gdprApplies,
    required String? purposeConsents,
  }) {
    if (gdprApplies != 1) return true;
    final p = purposeConsents ?? '';
    bool has(int purpose) => p.length >= purpose && p[purpose - 1] == '1';
    return has(1) && has(3) && has(4);
  }

  @override
  Future<void> initializeSdk({required List<String> testDeviceIds}) async {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        // Not a children's app: no child or teen treatment is claimed.
        ageRestrictedTreatment: AgeRestrictedTreatment.unspecified,
        testDeviceIds: testDeviceIds,
      ),
    );
    await MobileAds.instance.initialize();
  }

  @override
  Future<double?> bannerHeight(int width) async {
    try {
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      return size?.height.toDouble();
    } on Object {
      return null;
    }
  }

  @override
  Widget banner({
    required String unitId,
    required int width,
    required bool nonPersonalized,
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) => _GoogleBanner(
    key: ValueKey('$unitId/$width/$nonPersonalized'),
    unitId: unitId,
    width: width,
    nonPersonalized: nonPersonalized,
    onLoaded: onLoaded,
    onFailed: onFailed,
  );

  @override
  Future<PlatformInterstitial?> loadInterstitial({
    required String unitId,
    required bool nonPersonalized,
  }) {
    final done = Completer<PlatformInterstitial?>();
    try {
      unawaited(
        InterstitialAd.load(
          adUnitId: unitId,
          request: _request(nonPersonalized: nonPersonalized),
          adLoadCallback: InterstitialAdLoadCallback(
            onAdLoaded: (ad) => done.isCompleted
                ? unawaited(ad.dispose())
                : done.complete(_GoogleInterstitial(ad)),
            onAdFailedToLoad: (_) =>
                done.isCompleted ? null : done.complete(null),
          ),
        ).catchError((Object _) {
          if (!done.isCompleted) done.complete(null);
        }),
      );
    } on Object {
      return Future.value();
    }
    return done.future;
  }

  @override
  Future<PlatformNative?> loadNative({
    required String unitId,
    required NativeLayout layout,
    required NativeColors colors,
    required bool nonPersonalized,
  }) {
    final done = Completer<PlatformNative?>();
    try {
      final ad = NativeAd(
        adUnitId: unitId,
        request: _request(nonPersonalized: nonPersonalized),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: switch (layout) {
            NativeLayout.small => TemplateType.small,
            NativeLayout.medium => TemplateType.medium,
          },
          mainBackgroundColor: colors.background,
          cornerRadius: 12,
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: colors.primaryText,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: colors.secondaryText,
          ),
          tertiaryTextStyle: NativeTemplateTextStyle(
            textColor: colors.secondaryText,
          ),
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: colors.buttonText,
            backgroundColor: colors.buttonBackground,
          ),
        ),
        listener: NativeAdListener(
          onAdLoaded: (ad) => done.isCompleted
              ? unawaited(ad.dispose())
              : done.complete(_GoogleNative(ad as NativeAd)),
          onAdFailedToLoad: (ad, _) {
            unawaited(ad.dispose());
            if (!done.isCompleted) done.complete(null);
          },
        ),
      );
      unawaited(
        ad.load().catchError((Object _) {
          if (!done.isCompleted) done.complete(null);
        }),
      );
    } on Object {
      return Future.value();
    }
    return done.future;
  }
}

class _GoogleNative implements PlatformNative {
  _GoogleNative(this._ad);

  final NativeAd _ad;
  bool _disposed = false;

  @override
  Widget get view => AdWidget(ad: _ad);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_ad.dispose().catchError((Object _) {}));
  }
}

AdRequest _request({required bool nonPersonalized}) =>
    AdRequest(nonPersonalizedAds: nonPersonalized ? true : null);

class _GoogleInterstitial implements PlatformInterstitial {
  _GoogleInterstitial(this._ad);

  final InterstitialAd _ad;
  bool _disposed = false;

  @override
  Future<bool> show() async {
    final closed = Completer<bool>();
    void finish(bool shown) {
      if (!closed.isCompleted) closed.complete(shown);
    }

    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(true),
      onAdFailedToShowFullScreenContent: (_, _) => finish(false),
    );
    try {
      await _ad.show();
    } on Object {
      finish(false);
    }
    return await closed.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_ad.dispose().catchError((Object _) {}));
  }
}

/// Owns one [BannerAd]: loads it once, shows it when loaded, and frees the
/// native view when the widget leaves the tree.
class _GoogleBanner extends StatefulWidget {
  const _GoogleBanner({
    required this.unitId,
    required this.width,
    required this.nonPersonalized,
    required this.onLoaded,
    required this.onFailed,
    super.key,
  });

  final String unitId;
  final int width;
  final bool nonPersonalized;
  final VoidCallback onLoaded;
  final VoidCallback onFailed;

  @override
  State<_GoogleBanner> createState() => _GoogleBannerState();
}

class _GoogleBannerState extends State<_GoogleBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
        widget.width,
      );
      if (!mounted) return;
      if (size == null) {
        widget.onFailed();
        return;
      }
      final ad = BannerAd(
        size: size,
        adUnitId: widget.unitId,
        request: _request(nonPersonalized: widget.nonPersonalized),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (!mounted) return;
            setState(() => _loaded = true);
            widget.onLoaded();
          },
          onAdFailedToLoad: (ad, _) {
            unawaited(ad.dispose());
            if (identical(_ad, ad)) _ad = null;
            if (mounted) widget.onFailed();
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } on Object {
      if (mounted) widget.onFailed();
    }
  }

  @override
  void dispose() {
    final ad = _ad;
    _ad = null;
    if (ad != null) unawaited(ad.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}

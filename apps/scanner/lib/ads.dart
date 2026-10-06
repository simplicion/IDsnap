import 'dart:io';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:engine_ads/engine_ads.dart' as ads;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The committed AdMob IDs, also read by android/app/build.gradle.kts.
const admobIdsAsset = 'assets/config/admob.json';

/// What the build earns money with, checked.
class MonetizationSetup {
  const MonetizationSetup(this.mode, this.adsConfig);

  final MonetizationMode mode;

  /// The AdMob IDs to use, or null when this build shows no ads (a paid
  /// mode, the kill switch, desktop, or iOS before its IDs exist).
  final ads.AdsConfig? adsConfig;
}

/// Checks the build's monetization settings before anything else starts
/// (ADR-0013). Reads build constants and one bundled file; runs no ad code.
///
/// Throws [MonetizationConfigError] for an unknown IDSNAP_MONETIZATION
/// and [ads.AdsConfigError] when a release build that shows ads has
/// missing, malformed or Google-sample AdMob IDs.
Future<MonetizationSetup> checkMonetizationConfig({
  String mode = monetizationDefine,
  bool release = kReleaseMode,
  bool adsDisabled = ads.adsDisabledDefine,
  TargetPlatform? platform,
  Future<String> Function()? loadIds,
  ads.AdUnitIds? overrides,
  String testDevices = ads.admobTestDevicesDefine,
}) async {
  final resolved = resolveMonetizationMode(mode);
  final target = _adsTarget(platform ?? defaultTargetPlatform);
  if (!resolved.showsAds || adsDisabled || target == null) {
    return MonetizationSetup(resolved, null);
  }
  final text = await (loadIds ?? _loadIdsAsset)();
  return MonetizationSetup(
    resolved,
    ads.resolveAdsConfig(
      release: release,
      target: target,
      file: ads.AdmobIdsFile.parse(text),
      overrides: overrides,
      testDevices: testDevices,
    ),
  );
}

Future<String> _loadIdsAsset() => rootBundle.loadString(admobIdsAsset);

ads.AdsTarget? _adsTarget(TargetPlatform platform) {
  if (kIsWeb) return null;
  return switch (platform) {
    TargetPlatform.android => ads.AdsTarget.android,
    TargetPlatform.iOS => ads.AdsTarget.ios,
    _ => null,
  };
}

/// Builds the [AdsService] for [setup]. No ad code runs here: the service
/// starts (consent first) when the first ad slot becomes visible.
///
/// [NoopAdsService] — no SDK, no requests — when the build shows no ads.
/// Every number comes from the placement policy in docscan_contracts.
AdsService createAdsService({
  required MonetizationSetup setup,
  required String supportDirectory,
  ads.AdsPlatform Function()? sdk,
  DateTime Function()? now,
}) {
  final config = setup.adsConfig;
  if (!setup.mode.showsAds || config == null) return const NoopAdsService();
  return EngineAdsService(
    ads.AdsEngine(
      platform: (sdk ?? ads.GoogleAdsPlatform.new)(),
      config: config,
      now: now,
      bannerRetryAfter: AdPlacementPolicy.bannerRetryAfter,
      nativeMaxAge: AdPlacementPolicy.nativeMaxAge,
      cap: ads.InterstitialFrequencyCap(
        now: now,
        policy: const ads.InterstitialCapPolicy(
          minGap: AdPlacementPolicy.interstitialMinGap,
          maxPerDay: AdPlacementPolicy.interstitialMaxPerDay,
          warmUp: AdPlacementPolicy.interstitialSessionWarmUp,
          freeTasks: AdPlacementPolicy.interstitialFreeTasks,
        ),
        // Counters only (finished jobs, ads shown today): not vault data.
        storage: ads.FileAdsStorage(File('$supportDirectory/ads/state.json')),
      ),
    ),
  );
}

/// Adapts the ads engine to the [AdsService] port in contracts.
class EngineAdsService implements AdsService {
  EngineAdsService(this.engine);

  final ads.AdsEngine engine;

  @override
  void addListener(VoidCallback listener) => engine.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => engine.removeListener(listener);

  @override
  Future<void> initialize() => engine.initialize();

  @override
  bool get canShowAds => engine.ready;

  @override
  AdConsentStatus get consentStatus => switch (engine.consentStatus) {
    ads.PlatformConsentStatus.unknown => AdConsentStatus.unknown,
    ads.PlatformConsentStatus.notRequired => AdConsentStatus.notRequired,
    ads.PlatformConsentStatus.obtained => AdConsentStatus.obtained,
    ads.PlatformConsentStatus.required => AdConsentStatus.required,
  };

  @override
  bool get privacyOptionsRequired => engine.privacyOptionsRequired;

  @override
  Future<double?> resolveBannerHeight(int width) =>
      engine.resolveBannerHeight(width);

  @override
  Widget buildBanner({required int width}) => engine.buildBanner(width: width);

  @override
  AdNativeHandle? takeNative(AdNativeSize size, AdNativeStyle style) {
    final ad = engine.takeNative(
      switch (size) {
        AdNativeSize.small => ads.NativeLayout.small,
        AdNativeSize.medium => ads.NativeLayout.medium,
      },
      ads.NativeColors(
        background: style.background,
        primaryText: style.primaryText,
        secondaryText: style.secondaryText,
        buttonBackground: style.buttonBackground,
        buttonText: style.buttonText,
      ),
    );
    return ad == null ? null : _NativeHandle(ad);
  }

  @override
  Future<void> loadInterstitial() => engine.loadInterstitial();

  @override
  Future<bool> maybeShowInterstitial() => engine.maybeShowInterstitial();

  @override
  Future<void> openPrivacyOptions() => engine.openPrivacyOptions();
}

class _NativeHandle implements AdNativeHandle {
  _NativeHandle(this._ad);

  final ads.PlatformNative _ad;

  @override
  Widget get view => _ad.view;

  @override
  void dispose() => _ad.dispose();
}

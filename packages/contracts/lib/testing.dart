/// Test doubles for the ports in docscan_contracts. Import from tests only.
library;

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:flutter/widgets.dart';

/// An [AdsService] for widget tests: no plugin, no network. Shows plain
/// boxes where ads would be and counts every call, so tests can assert
/// both "an ad appears here" and "no ad code ran there".
class FakeAdsService extends ChangeNotifier implements AdsService {
  FakeAdsService({
    this.ready = true,
    this.bannerHeight = 60,
    this.nativeLoaded = true,
    this.interstitialLoaded = true,
    this.optionsRequired = false,
  });

  /// On the box standing in for a banner ad.
  static const bannerKey = Key('fake.ad.banner');

  /// On the box standing in for a native ad.
  static const nativeKey = Key('fake.ad.native');

  /// Consent resolved and SDK running.
  bool ready;

  /// Null = no banner available (offline, no fill).
  double? bannerHeight;

  /// Whether a native ad is already loaded when a slot asks.
  bool nativeLoaded;
  bool interstitialLoaded;
  bool optionsRequired;

  int initializeCalls = 0;
  int bannersBuilt = 0;
  int nativesTaken = 0;
  int nativesDisposed = 0;
  int nativeRequests = 0;
  int interstitialRequests = 0;
  int interstitialsShown = 0;
  int privacyOptionsOpened = 0;
  final nativeSizes = <AdNativeSize>[];

  /// Every ad that was put on screen or asked for.
  int get adActivity => bannersBuilt + nativeRequests + interstitialRequests;

  /// Ads become available (consent resolved); slots are told.
  void becomeReady() {
    ready = true;
    notifyListeners();
  }

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  bool get canShowAds => ready;

  @override
  AdConsentStatus get consentStatus =>
      ready ? AdConsentStatus.notRequired : AdConsentStatus.unknown;

  @override
  bool get privacyOptionsRequired => optionsRequired;

  @override
  Future<double?> resolveBannerHeight(int width) async =>
      ready ? bannerHeight : null;

  @override
  Widget buildBanner({required int width}) {
    bannersBuilt++;
    return const SizedBox.expand(key: bannerKey);
  }

  @override
  AdNativeHandle? takeNative(AdNativeSize size, AdNativeStyle style) {
    nativeRequests++;
    if (!ready || !nativeLoaded) return null;
    nativesTaken++;
    nativeSizes.add(size);
    return _FakeNative(this);
  }

  @override
  Future<void> loadInterstitial() async {}

  @override
  Future<bool> maybeShowInterstitial() async {
    interstitialRequests++;
    if (!ready || !interstitialLoaded) return false;
    interstitialsShown++;
    return true;
  }

  @override
  Future<void> openPrivacyOptions() async => privacyOptionsOpened++;
}

class _FakeNative implements AdNativeHandle {
  _FakeNative(this._service);

  final FakeAdsService _service;

  @override
  Widget get view => const SizedBox.expand(key: FakeAdsService.nativeKey);

  @override
  void dispose() => _service.nativesDisposed++;
}

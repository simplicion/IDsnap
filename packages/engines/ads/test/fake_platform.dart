import 'package:engine_ads/engine_ads.dart';
import 'package:flutter/widgets.dart';

/// Records every call so tests can assert the order: consent first, then
/// the SDK, then ad requests.
class FakeAdsPlatform implements AdsPlatform {
  final log = <String>[];

  bool consentServerReachable = true;
  bool formRequired = false;

  /// What the user picks when the form is shown.
  bool userConsents = true;
  bool personalizedAllowed = true;
  bool privacyOptions = false;
  PlatformConsentStatus status = PlatformConsentStatus.notRequired;
  bool _canRequest = true;

  bool interstitialAvailable = true;
  bool nativeAvailable = true;
  bool interstitialShows = true;
  double? bannerHeightValue = 60;
  int interstitialsShown = 0;
  final nativesDisposed = <NativeLayout>[];
  final requests = <({String kind, String unitId, bool nonPersonalized})>[];

  /// A user in a consent region who has not answered yet.
  void requireConsent() {
    formRequired = true;
    status = PlatformConsentStatus.required;
    _canRequest = false;
    privacyOptions = true;
  }

  @override
  Future<bool> requestConsentInfoUpdate() async {
    log.add('consentUpdate');
    return consentServerReachable;
  }

  @override
  Future<void> showConsentFormIfRequired() async {
    if (!formRequired || !consentServerReachable) return;
    log.add('consentForm');
    formRequired = false;
    status = PlatformConsentStatus.obtained;
    // UMP allows requests once the form was answered, either way.
    _canRequest = true;
    personalizedAllowed = userConsents;
  }

  @override
  Future<PlatformConsentStatus> consentStatus() async => status;

  @override
  Future<bool> canRequestAds() async => _canRequest;

  @override
  Future<bool> privacyOptionsRequired() async => privacyOptions;

  @override
  Future<void> showPrivacyOptionsForm() async {
    log.add('privacyOptions');
    personalizedAllowed = userConsents;
  }

  @override
  Future<bool> personalizedAdsAllowed() async => personalizedAllowed;

  @override
  Future<void> initializeSdk({required List<String> testDeviceIds}) async {
    log.add('sdkInit');
  }

  @override
  Future<double?> bannerHeight(int width) async {
    log.add('bannerHeight');
    return bannerHeightValue;
  }

  @override
  Widget banner({
    required String unitId,
    required int width,
    required bool nonPersonalized,
    required VoidCallback onLoaded,
    required VoidCallback onFailed,
  }) {
    log.add('banner');
    requests.add((
      kind: 'banner',
      unitId: unitId,
      nonPersonalized: nonPersonalized,
    ));
    lastBannerFailed = onFailed;
    return const SizedBox(key: Key('fake-banner'));
  }

  VoidCallback? lastBannerFailed;

  @override
  Future<PlatformInterstitial?> loadInterstitial({
    required String unitId,
    required bool nonPersonalized,
  }) async {
    log.add('loadInterstitial');
    requests.add((
      kind: 'interstitial',
      unitId: unitId,
      nonPersonalized: nonPersonalized,
    ));
    return interstitialAvailable ? _FakeInterstitial(this) : null;
  }

  @override
  Future<PlatformNative?> loadNative({
    required String unitId,
    required NativeLayout layout,
    required NativeColors colors,
    required bool nonPersonalized,
  }) async {
    log.add('loadNative:${layout.name}');
    requests.add((
      kind: 'native',
      unitId: unitId,
      nonPersonalized: nonPersonalized,
    ));
    return nativeAvailable ? _FakeNative(this, layout) : null;
  }
}

class _FakeInterstitial implements PlatformInterstitial {
  _FakeInterstitial(this._platform);

  final FakeAdsPlatform _platform;

  @override
  Future<bool> show() async {
    if (!_platform.interstitialShows) return false;
    _platform.log.add('showInterstitial');
    _platform.interstitialsShown++;
    return true;
  }

  @override
  void dispose() {}
}

class _FakeNative implements PlatformNative {
  _FakeNative(this._platform, this.layout);

  final FakeAdsPlatform _platform;
  final NativeLayout layout;

  @override
  Widget get view => const SizedBox(key: Key('fake-native'));

  @override
  void dispose() => _platform.nativesDisposed.add(layout);
}

/// A clock tests move by hand.
class FakeClock {
  FakeClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// The owner's caps (kept equal to AdPlacementPolicy by a test in
/// apps/scanner).
const testCapPolicy = InterstitialCapPolicy(
  minGap: Duration(minutes: 3),
  maxPerDay: 6,
  warmUp: Duration(seconds: 60),
  freeTasks: 1,
);

const testConfig = AdsConfig(ids: GoogleTestAdIds.android, usesTestIds: true);

const testColors = NativeColors(
  background: Color(0xFFEEEEEE),
  primaryText: Color(0xFF000000),
  secondaryText: Color(0xFF444444),
  buttonBackground: Color(0xFF0000FF),
  buttonText: Color(0xFFFFFFFF),
);

AdsEngine buildEngine(
  FakeAdsPlatform platform,
  FakeClock clock, {
  AdsStorage? storage,
}) => AdsEngine(
  platform: platform,
  config: testConfig,
  now: clock.call,
  bannerRetryAfter: const Duration(minutes: 5),
  nativeMaxAge: const Duration(minutes: 50),
  cap: InterstitialFrequencyCap(
    storage: storage ?? MemoryAdsStorage(),
    policy: testCapPolicy,
    now: clock.call,
  ),
);

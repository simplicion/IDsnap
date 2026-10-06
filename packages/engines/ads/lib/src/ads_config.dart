import 'dart:convert';

/// `--dart-define=IDSNAP_ADS_DISABLED=true`: no ads at all (screenshots,
/// store listings, tests on a real phone). The SDK is never initialised.
const adsDisabledDefine = bool.fromEnvironment('IDSNAP_ADS_DISABLED');

// Optional overrides of apps/scanner/assets/config/admob.json (the
// committed defaults). Empty = use the file.
const admobAppIdAndroidDefine = String.fromEnvironment(
  'IDSNAP_ADMOB_APP_ID_ANDROID',
);
const admobAppIdIosDefine = String.fromEnvironment('IDSNAP_ADMOB_APP_ID_IOS');
const admobBannerIdDefine = String.fromEnvironment('IDSNAP_ADMOB_BANNER_ID');
const admobInterstitialIdDefine = String.fromEnvironment(
  'IDSNAP_ADMOB_INTERSTITIAL_ID',
);
const admobNativeIdDefine = String.fromEnvironment('IDSNAP_ADMOB_NATIVE_ID');

/// Comma-separated hashed device IDs (the SDK prints a phone's ID to
/// logcat / the Xcode console on its first ad request).
///
/// - Release build: these phones get test ads from the real ad units.
/// - Debug / profile build: the EXPLICIT OPT-IN to use the real ad units
///   instead of Google's sample units, on these registered phones only
///   (they still get test ads, so nothing counts as invalid traffic).
///   Without it, debug and profile builds always use the sample units.
const admobTestDevicesDefine = String.fromEnvironment(
  'IDSNAP_ADMOB_TEST_DEVICE_IDS',
);

/// Google's public sample IDs. They always serve test ads and earn
/// nothing, so debug and profile builds use them and release builds
/// refuse them.
/// https://developers.google.com/admob/flutter/test-ads
abstract final class GoogleTestAdIds {
  static const publisher = 'ca-app-pub-3940256099942544';
  static const android = AdUnitIds(
    appId: '$publisher~3347511713',
    banner: '$publisher/9214589741',
    interstitial: '$publisher/1033173712',
    native: '$publisher/2247696110',
  );
  static const ios = AdUnitIds(
    appId: '$publisher~1458002511',
    banner: '$publisher/2435281174',
    interstitial: '$publisher/4411468910',
    native: '$publisher/3986624511',
  );
}

enum AdsTarget { android, ios }

/// One platform's AdMob App ID and ad units.
class AdUnitIds {
  const AdUnitIds({
    required this.appId,
    required this.banner,
    required this.interstitial,
    required this.native,
  });

  /// Nothing configured.
  const AdUnitIds.none()
    : appId = '',
      banner = '',
      interstitial = '',
      native = '';

  factory AdUnitIds.fromJson(Object? json) {
    if (json is! Map) return const AdUnitIds.none();
    String read(String key) => (json[key] as String? ?? '').trim();
    return AdUnitIds(
      appId: read('appId'),
      banner: read('banner'),
      interstitial: read('interstitial'),
      native: read('native'),
    );
  }

  final String appId;
  final String banner;
  final String interstitial;
  final String native;

  /// Nothing configured at all (iOS until its IDs exist).
  bool get isEmpty =>
      appId.isEmpty && banner.isEmpty && interstitial.isEmpty && native.isEmpty;

  /// [other]'s non-empty values win.
  AdUnitIds overriddenBy(AdUnitIds other) => AdUnitIds(
    appId: other.appId.isEmpty ? appId : other.appId.trim(),
    banner: other.banner.isEmpty ? banner : other.banner.trim(),
    interstitial: other.interstitial.isEmpty
        ? interstitial
        : other.interstitial.trim(),
    native: other.native.isEmpty ? native : other.native.trim(),
  );
}

/// The committed AdMob IDs: `apps/scanner/assets/config/admob.json`. ONE
/// file, read by Gradle (the manifest's App ID) and, as a bundled asset,
/// by the app. AdMob IDs are not secrets: they are readable in every APK.
class AdmobIdsFile {
  const AdmobIdsFile({
    this.android = const AdUnitIds.none(),
    this.ios = const AdUnitIds.none(),
  });

  /// Parses the file's text. Throws [AdsConfigError] when it isn't the
  /// expected JSON.
  factory AdmobIdsFile.parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) throw const FormatException('not an object');
      return AdmobIdsFile(
        android: AdUnitIds.fromJson(json['android']),
        ios: AdUnitIds.fromJson(json['ios']),
      );
    } on Object catch (e) {
      throw AdsConfigError('assets/config/admob.json is not valid: $e');
    }
  }

  final AdUnitIds android;
  final AdUnitIds ios;

  AdUnitIds of(AdsTarget target) => target == AdsTarget.android ? android : ios;
}

/// An ads build configuration that must not ship.
class AdsConfigError extends Error {
  AdsConfigError(this.message);

  final String message;

  @override
  String toString() => 'AdsConfigError: $message';
}

/// The resolved AdMob IDs for this build.
class AdsConfig {
  const AdsConfig({
    required this.ids,
    required this.usesTestIds,
    this.testDeviceIds = const [],
  });

  final AdUnitIds ids;

  /// True when these are Google's sample units (test ads only).
  final bool usesTestIds;

  /// Registered test phones: they get test ads from real units.
  final List<String> testDeviceIds;
}

final _appIdPattern = RegExp(r'^ca-app-pub-\d{16}~\d{10}$');
final _unitIdPattern = RegExp(r'^ca-app-pub-\d{16}/\d{10}$');

String _publisherOf(String id) => id.split(RegExp('[~/]')).first;

/// The dart-define overrides for [target] (empty values = none).
AdUnitIds admobDefineOverrides(AdsTarget target) => AdUnitIds(
  appId: target == AdsTarget.android
      ? admobAppIdAndroidDefine
      : admobAppIdIosDefine,
  banner: admobBannerIdDefine,
  interstitial: admobInterstitialIdDefine,
  native: admobNativeIdDefine,
);

/// Resolves and checks the AdMob IDs for [target]: the committed [file],
/// with [overrides] (dart-defines) on top.
///
/// Returns null when [target] has no IDs at all: ads are then OFF on that
/// platform (iOS until its AdMob app exists). Android is the shipping
/// platform, so in a release build missing Android IDs are an error.
///
/// Debug and profile builds ALWAYS get Google's sample IDs: tapping your
/// own live ads while developing can get the AdMob account suspended. The
/// only way to the real units outside release is [testDevices], which
/// registers the phones that will then get test ads from them.
///
/// Release builds fail fast ([AdsConfigError]) when an ID is missing,
/// malformed or one of Google's sample IDs (they earn nothing), or when
/// the IDs belong to different AdMob accounts.
AdsConfig? resolveAdsConfig({
  required bool release,
  required AdsTarget target,
  required AdmobIdsFile file,
  AdUnitIds? overrides,
  String testDevices = admobTestDevicesDefine,
}) {
  final ids = file
      .of(target)
      .overriddenBy(overrides ?? admobDefineOverrides(target));
  final android = target == AdsTarget.android;
  if (ids.isEmpty && !(release && android)) return null;

  final devices = [
    for (final id in testDevices.split(','))
      if (id.trim().isNotEmpty) id.trim(),
  ];
  if (!release && devices.isEmpty) {
    return AdsConfig(
      ids: android ? GoogleTestAdIds.android : GoogleTestAdIds.ios,
      usesTestIds: true,
    );
  }

  final problems = checkAdUnitIds(ids);
  if (problems.isNotEmpty) {
    throw AdsConfigError(
      '${release ? 'This release build shows ads' : 'Real ad units were '
                'requested for a test device (IDSNAP_ADMOB_TEST_DEVICE_IDS)'} '
      'but its AdMob IDs for ${target.name} are not usable: '
      '${problems.join('; ')}. Fix apps/scanner/assets/config/admob.json or '
      'the IDSNAP_ADMOB_* dart-defines (README > Release builds), or build '
      'with --dart-define=IDSNAP_ADS_DISABLED=true for a build without ads.',
    );
  }
  return AdsConfig(ids: ids, usesTestIds: false, testDeviceIds: devices);
}

/// What is wrong with [ids] for a build that earns money (empty = fine).
List<String> checkAdUnitIds(AdUnitIds ids) {
  final values = <String, (String, RegExp)>{
    'the App ID': (ids.appId, _appIdPattern),
    'the banner unit': (ids.banner, _unitIdPattern),
    'the interstitial unit': (ids.interstitial, _unitIdPattern),
    'the native unit': (ids.native, _unitIdPattern),
  };
  final problems = <String>[];
  for (final MapEntry(key: name, value: (value, pattern)) in values.entries) {
    if (value.isEmpty) {
      problems.add('$name is missing');
    } else if (!pattern.hasMatch(value)) {
      problems.add('$name is not an AdMob ID');
    } else if (_publisherOf(value) == GoogleTestAdIds.publisher) {
      problems.add("$name is one of Google's TEST IDs (they earn nothing)");
    }
  }
  if (problems.isEmpty) {
    final publishers = values.values.map((v) => _publisherOf(v.$1)).toSet();
    if (publishers.length > 1) {
      problems.add(
        'the App ID and the ad units belong to different AdMob accounts '
        '(${publishers.join(', ')})',
      );
    }
  }
  return problems;
}

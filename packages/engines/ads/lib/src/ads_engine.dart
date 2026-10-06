import 'dart:async';

import 'package:engine_ads/src/ads_config.dart';
import 'package:engine_ads/src/ads_platform.dart';
import 'package:engine_ads/src/frequency_cap.dart';
import 'package:flutter/widgets.dart';

/// Ads for IDSnap, in the order the rules require:
///
/// 1. **Consent first.** [initialize] asks the consent platform, shows its
///    form when one is required, and starts the ads SDK only once ads may
///    be requested. Until then nothing is requested and nothing is shown.
/// 2. **Non-personalised when required.** Every request carries the
///    current choice of the user.
/// 3. **Silent failures.** A banner or interstitial that fails to load is
///    skipped; nothing here throws or waits for an ad.
/// 4. **Capped interstitials** ([InterstitialFrequencyCap]).
/// 5. **Native ads only when already loaded.** [takeNative] never waits;
///    it hands out a preloaded ad or nothing.
///
/// Where ads may appear is NOT decided here: that is the placement policy
/// in docscan_contracts (`ad_placement.dart`).
class AdsEngine extends ChangeNotifier {
  AdsEngine({
    required this.platform,
    required this.config,
    required this.cap,
    required this.bannerRetryAfter,
    required this.nativeMaxAge,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AdsPlatform platform;
  final AdsConfig config;
  final InterstitialFrequencyCap cap;
  final DateTime Function() _now;

  /// After a banner failed to load (offline, no fill), banner slots stay
  /// closed this long instead of showing an empty strip.
  final Duration bannerRetryAfter;

  /// A loaded native ad older than this is thrown away, not shown.
  final Duration nativeMaxAge;

  Future<void>? _starting;
  bool _ready = false;
  bool _nonPersonalized = true;
  bool _privacyOptionsRequired = false;
  PlatformConsentStatus _consent = PlatformConsentStatus.unknown;
  DateTime? _bannerFailedAt;
  final _bannerHeights = <int, double?>{};
  PlatformInterstitial? _interstitial;
  bool _loadingInterstitial = false;
  bool _showing = false;
  bool _disposed = false;
  NativeColors? _nativeColors;
  final _natives = <NativeLayout, _LoadedNative>{};
  final _loadingNatives = <NativeLayout>{};

  /// Consent is resolved and the SDK is running: ads may be requested.
  bool get ready => _ready;

  PlatformConsentStatus get consentStatus => _consent;

  /// The app must offer "Ad privacy choices" (reopens the form).
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  /// Requests currently ask for non-personalised ads.
  bool get nonPersonalized => _nonPersonalized;

  bool get hasInterstitial => _interstitial != null;

  /// Gathers consent, then starts the SDK. Safe to call again: a run
  /// that ended without consent (offline, form closed) is retried.
  Future<void> initialize() => _starting ??= _start().whenComplete(() {
    if (!_ready) _starting = null;
  });

  Future<void> _start() async {
    try {
      await cap.startSession();
      await platform.requestConsentInfoUpdate();
      // Also when the update failed: consent from an earlier session is
      // cached by the platform and still valid.
      await platform.showConsentFormIfRequired();
      await _readConsent();
      if (!await platform.canRequestAds()) {
        _notify();
        return;
      }
      await platform.initializeSdk(testDeviceIds: config.testDeviceIds);
      _ready = true;
      _notify();
      unawaited(loadInterstitial());
      _warmNatives();
    } on Object {
      // Ads are never worth an error: stay off for this session.
    }
  }

  Future<void> _readConsent() async {
    _consent = await platform.consentStatus();
    _privacyOptionsRequired = await platform.privacyOptionsRequired();
    _nonPersonalized = !await platform.personalizedAdsAllowed();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Banner ────────────────────────────────────────────────────────────

  /// Whether a banner slot should open now.
  bool get bannerAvailable {
    if (!_ready) return false;
    final failed = _bannerFailedAt;
    return failed == null || _now().difference(failed) >= bannerRetryAfter;
  }

  /// The banner height for [width] if already known.
  double? bannerHeight(int width) =>
      bannerAvailable ? _bannerHeights[width] : null;

  /// Resolves (once per width) and returns the banner height, or null when
  /// no banner should be shown now.
  Future<double?> resolveBannerHeight(int width) async {
    if (!bannerAvailable || width <= 0) return null;
    if (!_bannerHeights.containsKey(width)) {
      try {
        _bannerHeights[width] = await platform.bannerHeight(width);
      } on Object {
        return null;
      }
    }
    return bannerHeight(width);
  }

  /// The banner for a slot that reserved [bannerHeight] for [width].
  Widget buildBanner({required int width}) {
    if (!_ready) return const SizedBox.shrink();
    return platform.banner(
      unitId: config.ids.banner,
      width: width,
      nonPersonalized: _nonPersonalized,
      onLoaded: () => _bannerFailedAt = null,
      // The open slot keeps its space (no jump); later slots stay closed
      // until the retry time has passed.
      onFailed: () => _bannerFailedAt = _now(),
    );
  }

  // ── Interstitial ──────────────────────────────────────────────────────

  /// Loads one interstitial in the background for a later
  /// [maybeShowInterstitial]. Does nothing until [ready].
  Future<void> loadInterstitial() async {
    if (!_ready || _interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    try {
      final ad = await platform.loadInterstitial(
        unitId: config.ids.interstitial,
        nonPersonalized: _nonPersonalized,
      );
      if (_disposed) {
        ad?.dispose();
      } else {
        _interstitial = ad;
      }
    } on Object {
      // Skipped silently.
    } finally {
      _loadingInterstitial = false;
    }
  }

  /// Call when the user leaves the result of a finished job. Counts the
  /// job, then shows the loaded interstitial if the frequency cap allows
  /// one now. Returns false without waiting when it does not, or when no
  /// ad is loaded: the user never waits for an ad. True after an ad was
  /// shown and closed.
  Future<bool> maybeShowInterstitial() async {
    try {
      // Counted even while ads are off, so "never after the first
      // finished job" holds whenever ads start.
      await cap.startSession();
      if (await cap.registerFinishedTask() != null) return false;
    } on Object {
      return false;
    }
    if (!_ready || _showing) return false;
    final ad = _interstitial;
    if (ad == null) {
      unawaited(loadInterstitial());
      return false;
    }
    _interstitial = null;
    _showing = true;
    try {
      // Counted before it opens, so nothing can show two in a row.
      await cap.recordShown();
      return await ad.show();
    } on Object {
      return false;
    } finally {
      _showing = false;
      ad.dispose();
      unawaited(loadInterstitial());
    }
  }

  // ── Native ────────────────────────────────────────────────────────────

  /// A native ad that is already loaded for [layout] in [colors], or
  /// null. Never waits. Remembers [colors] and keeps one ad of each layout
  /// loading in the background for the screens that come next.
  PlatformNative? takeNative(NativeLayout layout, NativeColors colors) {
    if (_nativeColors != colors) {
      // Theme changed: the loaded ads were drawn in the old colours.
      for (final loaded in _natives.values) {
        loaded.ad.dispose();
      }
      _natives.clear();
      _nativeColors = colors;
    }
    PlatformNative? result;
    final loaded = _natives.remove(layout);
    if (loaded != null) {
      if (_ready && _now().difference(loaded.at) < nativeMaxAge) {
        result = loaded.ad;
      } else {
        loaded.ad.dispose();
      }
    }
    _warmNatives();
    return result;
  }

  void _warmNatives() {
    final colors = _nativeColors;
    if (!_ready || colors == null) return;
    for (final layout in NativeLayout.values) {
      final loaded = _natives[layout];
      if (loaded != null && _now().difference(loaded.at) >= nativeMaxAge) {
        _natives.remove(layout)?.ad.dispose();
      }
      if (_natives.containsKey(layout) || !_loadingNatives.add(layout)) {
        continue;
      }
      unawaited(_loadNative(layout, colors));
    }
  }

  Future<void> _loadNative(NativeLayout layout, NativeColors colors) async {
    try {
      final ad = await platform.loadNative(
        unitId: config.ids.native,
        layout: layout,
        colors: colors,
        nonPersonalized: _nonPersonalized,
      );
      if (ad == null) return;
      if (_disposed || !_ready || colors != _nativeColors) {
        ad.dispose();
      } else {
        _natives[layout] = _LoadedNative(ad, _now());
      }
    } on Object {
      // Skipped silently.
    } finally {
      _loadingNatives.remove(layout);
    }
  }

  void _dropNatives() {
    for (final loaded in _natives.values) {
      loaded.ad.dispose();
    }
    _natives.clear();
  }

  // ── Privacy options ───────────────────────────────────────────────────

  /// Reopens the privacy options form of the consent platform and applies
  /// the new choice to later requests.
  Future<void> openPrivacyOptions() async {
    try {
      await platform.showPrivacyOptionsForm();
      await _readConsent();
      if (!_ready) {
        _starting = null;
        await initialize();
      } else if (!await platform.canRequestAds()) {
        _ready = false;
        _interstitial?.dispose();
        _interstitial = null;
        _dropNatives();
      } else {
        // The loaded ads were requested under the previous choice.
        _interstitial?.dispose();
        _interstitial = null;
        _dropNatives();
        unawaited(loadInterstitial());
        _warmNatives();
      }
      _notify();
    } on Object {
      // Nothing to tell the user: the form simply did not open.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _interstitial?.dispose();
    _interstitial = null;
    _dropNatives();
    super.dispose();
  }
}

class _LoadedNative {
  _LoadedNative(this.ad, this.at);

  final PlatformNative ad;
  final DateTime at;
}

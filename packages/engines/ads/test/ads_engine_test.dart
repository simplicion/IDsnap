import 'dart:ui' show Color;

import 'package:engine_ads/engine_ads.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

void main() {
  late FakeAdsPlatform platform;
  late FakeClock clock;

  setUp(() {
    platform = FakeAdsPlatform();
    clock = FakeClock(DateTime(2026, 10, 7, 9));
  });

  group('consent first', () {
    test('nothing is requested or shown before initialize()', () async {
      final engine = buildEngine(platform, clock);
      expect(engine.ready, isFalse);
      expect(await engine.resolveBannerHeight(360), isNull);
      expect(engine.takeNative(NativeLayout.small, testColors), isNull);
      await engine.loadInterstitial();
      expect(await engine.maybeShowInterstitial(), isFalse);
      expect(platform.log, isEmpty);
      expect(platform.requests, isEmpty);
    });

    test('consent not required: update, then SDK, then ad requests', () async {
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      await pumpEventQueue();
      expect(engine.ready, isTrue);
      expect(engine.consentStatus, PlatformConsentStatus.notRequired);
      expect(platform.log.take(2), ['consentUpdate', 'sdkInit']);
      expect(platform.log, isNot(contains('consentForm')));
      // The first ad request comes after the SDK started.
      expect(
        platform.log.indexOf('loadInterstitial'),
        greaterThan(platform.log.indexOf('sdkInit')),
      );
    });

    test('consent required: the form is shown BEFORE the SDK starts and '
        'before any ad request', () async {
      platform.requireConsent();
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      await pumpEventQueue();
      expect(platform.log.take(3), ['consentUpdate', 'consentForm', 'sdkInit']);
      expect(engine.ready, isTrue);
      expect(engine.consentStatus, PlatformConsentStatus.obtained);
      expect(engine.privacyOptionsRequired, isTrue);
      for (final kind in ['loadInterstitial', 'banner']) {
        final at = platform.log.indexOf(kind);
        if (at >= 0) expect(at, greaterThan(platform.log.indexOf('sdkInit')));
      }
    });

    test('consent required but unreachable (offline, first run): the SDK is '
        'never started and no ad is requested; a later try works', () async {
      platform
        ..requireConsent()
        ..consentServerReachable = false;
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      await pumpEventQueue();
      expect(engine.ready, isFalse);
      expect(platform.log, ['consentUpdate']);
      expect(platform.requests, isEmpty);
      expect(await engine.resolveBannerHeight(360), isNull);
      expect(await engine.maybeShowInterstitial(), isFalse);

      // Back online: the next visible ad slot calls initialize() again.
      platform.consentServerReachable = true;
      await engine.initialize();
      await pumpEventQueue();
      expect(engine.ready, isTrue);
      expect(platform.log, containsAllInOrder(['consentForm', 'sdkInit']));
    });

    test('initialize() is idempotent', () async {
      final engine = buildEngine(platform, clock);
      await Future.wait([engine.initialize(), engine.initialize()]);
      await engine.initialize();
      expect(platform.log.where((e) => e == 'sdkInit'), hasLength(1));
      expect(platform.log.where((e) => e == 'consentUpdate'), hasLength(1));
    });

    test('listeners hear when ads become ready', () async {
      final engine = buildEngine(platform, clock);
      var notified = 0;
      engine.addListener(() => notified++);
      await engine.initialize();
      expect(notified, greaterThan(0));
    });
  });

  group('personalisation', () {
    test('consented: personalised requests', () async {
      platform.requireConsent();
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      await pumpEventQueue();
      engine.buildBanner(width: 360);
      expect(engine.nonPersonalized, isFalse);
      expect(platform.requests, isNotEmpty);
      expect(platform.requests.every((r) => !r.nonPersonalized), isTrue);
    });

    test('refused: EVERY request asks for non-personalised ads', () async {
      platform
        ..requireConsent()
        ..userConsents = false;
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      await pumpEventQueue();
      engine
        ..buildBanner(width: 360)
        ..takeNative(NativeLayout.small, testColors);
      await pumpEventQueue();
      expect(engine.nonPersonalized, isTrue);
      expect(platform.requests.map((r) => r.kind).toSet(), {
        'banner',
        'interstitial',
        'native',
      });
      expect(platform.requests.every((r) => r.nonPersonalized), isTrue);
    });

    test('changing the choice in "Ad privacy choices" applies to later '
        'requests and drops ads loaded under the old choice', () async {
      platform.requireConsent();
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      engine.takeNative(NativeLayout.small, testColors);
      await pumpEventQueue();
      expect(engine.hasInterstitial, isTrue);
      platform.requests.clear();

      platform.userConsents = false;
      await engine.openPrivacyOptions();
      await pumpEventQueue();
      expect(platform.log, contains('privacyOptions'));
      expect(engine.nonPersonalized, isTrue);
      expect(platform.nativesDisposed, isNotEmpty);
      expect(platform.requests, isNotEmpty);
      expect(platform.requests.every((r) => r.nonPersonalized), isTrue);
    });
  });

  group('each format uses its own ad unit', () {
    test('banner, interstitial, native', () async {
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      engine
        ..buildBanner(width: 360)
        ..takeNative(NativeLayout.small, testColors);
      await pumpEventQueue();
      final units = {for (final r in platform.requests) r.kind: r.unitId};
      expect(units, {
        'banner': GoogleTestAdIds.android.banner,
        'interstitial': GoogleTestAdIds.android.interstitial,
        'native': GoogleTestAdIds.android.native,
      });
    });
  });

  group('banner', () {
    test('height is resolved once per width and reused', () async {
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      expect(await engine.resolveBannerHeight(360), 60);
      expect(await engine.resolveBannerHeight(360), 60);
      expect(engine.bannerHeight(360), 60);
      expect(platform.log.where((e) => e == 'bannerHeight'), hasLength(1));
    });

    test(
      'a failed load closes later slots for the retry time, silently',
      () async {
        final engine = buildEngine(platform, clock);
        await engine.initialize();
        expect(await engine.resolveBannerHeight(360), 60);
        engine.buildBanner(width: 360);
        platform.lastBannerFailed!();
        expect(await engine.resolveBannerHeight(360), isNull);
        clock.advance(const Duration(minutes: 4, seconds: 59));
        expect(await engine.resolveBannerHeight(360), isNull);
        clock.advance(const Duration(seconds: 1));
        expect(await engine.resolveBannerHeight(360), 60);
      },
    );

    test('a device that cannot size a banner shows none', () async {
      platform.bannerHeightValue = null;
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      expect(await engine.resolveBannerHeight(360), isNull);
    });
  });

  group('native', () {
    test('never waits: the first ask returns nothing and preloads both '
        'layouts; later asks get a loaded ad', () async {
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      expect(engine.takeNative(NativeLayout.small, testColors), isNull);
      await pumpEventQueue();
      expect(
        platform.log,
        containsAll(['loadNative:small', 'loadNative:medium']),
      );
      expect(engine.takeNative(NativeLayout.small, testColors), isNotNull);
      // The result screen's layout was warmed by the earlier screen.
      expect(engine.takeNative(NativeLayout.medium, testColors), isNotNull);
      // Taken ads are replaced in the background.
      expect(engine.takeNative(NativeLayout.small, testColors), isNull);
      await pumpEventQueue();
      expect(engine.takeNative(NativeLayout.small, testColors), isNotNull);
    });

    test('no ad available: always nothing, never an error', () async {
      platform.nativeAvailable = false;
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      for (var i = 0; i < 3; i++) {
        expect(engine.takeNative(NativeLayout.small, testColors), isNull);
        await pumpEventQueue();
      }
    });

    test('an ad loaded too long ago is thrown away, not shown', () async {
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      engine.takeNative(NativeLayout.small, testColors);
      await pumpEventQueue();
      clock.advance(const Duration(minutes: 51));
      expect(engine.takeNative(NativeLayout.small, testColors), isNull);
      expect(platform.nativesDisposed, contains(NativeLayout.small));
    });

    test('a theme change drops ads drawn in the old colours', () async {
      final engine = buildEngine(platform, clock);
      await engine.initialize();
      engine.takeNative(NativeLayout.small, testColors);
      await pumpEventQueue();
      const dark = NativeColors(
        background: Color(0xFF111111),
        primaryText: Color(0xFFFFFFFF),
        secondaryText: Color(0xFFCCCCCC),
        buttonBackground: Color(0xFF8888FF),
        buttonText: Color(0xFF000000),
      );
      expect(engine.takeNative(NativeLayout.small, dark), isNull);
      expect(platform.nativesDisposed, hasLength(2));
    });
  });

  group('interstitial', () {
    Future<AdsEngine> readyEngine({int tasksBefore = 5}) async {
      final engine = buildEngine(
        platform,
        clock,
        storage: MemoryAdsStorage({'tasks': tasksBefore}),
      );
      await engine.initialize();
      await pumpEventQueue();
      return engine;
    }

    test('the first finished task ever: no interstitial', () async {
      final engine = await readyEngine(tasksBefore: 0);
      clock.advance(const Duration(minutes: 10));
      expect(await engine.maybeShowInterstitial(), isFalse);
      expect(platform.interstitialsShown, 0);
      // The second finished task may get one.
      expect(await engine.maybeShowInterstitial(), isTrue);
      expect(platform.interstitialsShown, 1);
    });

    test('not in the first 60 seconds; then one; then not again for 3 '
        'minutes', () async {
      final engine = await readyEngine();
      clock.advance(const Duration(seconds: 30));
      expect(await engine.maybeShowInterstitial(), isFalse);
      clock.advance(const Duration(seconds: 31));
      expect(await engine.maybeShowInterstitial(), isTrue);
      await pumpEventQueue();
      clock.advance(const Duration(minutes: 2));
      expect(await engine.maybeShowInterstitial(), isFalse);
      clock.advance(const Duration(minutes: 1, seconds: 1));
      expect(await engine.maybeShowInterstitial(), isTrue);
      expect(platform.interstitialsShown, 2);
    });

    test('at most 6 a day', () async {
      final engine = await readyEngine();
      clock.advance(const Duration(minutes: 2));
      for (var i = 0; i < 9; i++) {
        await engine.maybeShowInterstitial();
        await pumpEventQueue();
        clock.advance(const Duration(minutes: 5));
      }
      expect(platform.interstitialsShown, 6);
    });

    test('no ad loaded: skipped at once, the user never waits, and the cap '
        'is not spent', () async {
      platform.interstitialAvailable = false;
      final engine = await readyEngine();
      clock.advance(const Duration(minutes: 2));
      expect(engine.hasInterstitial, isFalse);
      expect(await engine.maybeShowInterstitial(), isFalse);
      expect(engine.cap.shownToday, 0);
      // One becomes available: the next finished task shows it.
      await pumpEventQueue();
      platform.interstitialAvailable = true;
      await engine.loadInterstitial();
      expect(await engine.maybeShowInterstitial(), isTrue);
    });

    test('a failure to show is swallowed', () async {
      platform.interstitialShows = false;
      final engine = await readyEngine();
      clock.advance(const Duration(minutes: 2));
      expect(await engine.maybeShowInterstitial(), isFalse);
    });

    test('tasks are counted even while ads are off, so the first-task rule '
        'cannot be dodged by a late start', () async {
      final storage = MemoryAdsStorage();
      final engine = buildEngine(platform, clock, storage: storage);
      expect(await engine.maybeShowInterstitial(), isFalse);
      expect(storage.state['tasks'], 1);
      expect(platform.requests, isEmpty);
    });
  });

  test('GoogleAdsPlatform: personalised ads need TCF purposes 1, 3 and 4 '
      'where the GDPR applies', () {
    bool allowed(int? gdpr, String? purposes) =>
        GoogleAdsPlatform.personalizedAllowedByTcf(
          gdprApplies: gdpr,
          purposeConsents: purposes,
        );
    expect(allowed(0, null), isTrue);
    expect(allowed(null, null), isTrue);
    expect(allowed(1, '1111111111'), isTrue);
    expect(allowed(1, '1011'), isTrue);
    expect(allowed(1, '1101'), isFalse); // purpose 3 refused
    expect(allowed(1, '0111'), isFalse); // purpose 1 refused
    expect(allowed(1, '111'), isFalse); // purpose 4 missing
    expect(allowed(1, ''), isFalse);
    expect(allowed(1, null), isFalse);
  });
}

// How the app wires monetization (ADR-0013): the committed AdMob IDs, the
// release fail-fast, the kill switch, iOS staying ad-free, and the engine's
// caps coming from the one placement-policy file.
import 'dart:convert';
import 'dart:io';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_scanner/ads.dart';
import 'package:docscan_scanner/startup_failure.dart';
import 'package:docscan_scanner/vault_startup.dart';
import 'package:engine_ads/engine_ads.dart' as ads;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _ownerPublisher = 'ca-app-pub-6432767564862835';

Future<String> _committedIds() => File(admobIdsAsset).readAsString();

Future<MonetizationSetup> _check({
  String mode = 'ads',
  bool release = true,
  bool adsDisabled = false,
  TargetPlatform platform = TargetPlatform.android,
  String? ids,
  String testDevices = '',
}) => checkMonetizationConfig(
  mode: mode,
  release: release,
  adsDisabled: adsDisabled,
  platform: platform,
  loadIds: ids == null ? _committedIds : () async => ids,
  overrides: const ads.AdUnitIds.none(),
  testDevices: testDevices,
);

void main() {
  group('the committed AdMob IDs (assets/config/admob.json)', () {
    test("are the owner's real Android IDs, one per format", () async {
      final file = ads.AdmobIdsFile.parse(await _committedIds());
      expect(file.android.appId, '$_ownerPublisher~9537044782');
      expect(file.android.banner, '$_ownerPublisher/5924357972');
      expect(file.android.interstitial, '$_ownerPublisher/9301241060');
      expect(file.android.native, '$_ownerPublisher/7595523131');
      expect(ads.checkAdUnitIds(file.android), isEmpty);
    });

    test('have no iOS IDs yet', () async {
      final file = ads.AdmobIdsFile.parse(await _committedIds());
      expect(file.ios.isEmpty, isTrue);
    });

    test('ship in the app bundle and are the file Gradle reads', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- $admobIdsAsset'));
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('../$admobIdsAsset'));
      expect(gradle, contains('manifestPlaceholders["admobAppId"]'));
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('com.google.android.gms.ads.APPLICATION_ID'));
      expect(manifest, contains(r'android:value="${admobAppId}"'));
      // No real or sample App ID is hard-coded in the manifest.
      expect(manifest, isNot(contains('ca-app-pub-')));
    });
  });

  group('a plain release build (no extra flags)', () {
    test('Android: free with ads, with the real units', () async {
      final setup = await _check();
      expect(setup.mode, MonetizationMode.ads);
      expect(setup.adsConfig, isNotNull);
      expect(setup.adsConfig!.usesTestIds, isFalse);
      expect(setup.adsConfig!.ids.banner, startsWith(_ownerPublisher));
      expect(setup.adsConfig!.ids.interstitial, startsWith(_ownerPublisher));
      expect(setup.adsConfig!.ids.native, startsWith(_ownerPublisher));
    });

    test('iOS: ads are off until iOS IDs exist; nothing fails', () async {
      final setup = await _check(platform: TargetPlatform.iOS);
      expect(setup.mode, MonetizationMode.ads);
      expect(setup.adsConfig, isNull);
      expect(
        createAdsService(setup: setup, supportDirectory: '.'),
        isA<NoopAdsService>(),
      );
    });
  });

  group('release fail-fast', () {
    test('missing IDs', () {
      expect(
        () => _check(ids: '{"android": {}, "ios": {}}'),
        throwsA(
          isA<ads.AdsConfigError>().having(
            (e) => e.message,
            'message',
            allOf(contains('the App ID is missing'), contains('admob.json')),
          ),
        ),
      );
    });

    test("Google's sample IDs", () {
      final sample = jsonEncode({
        'android': {
          'appId': ads.GoogleTestAdIds.android.appId,
          'banner': ads.GoogleTestAdIds.android.banner,
          'interstitial': ads.GoogleTestAdIds.android.interstitial,
          'native': ads.GoogleTestAdIds.android.native,
        },
      });
      expect(
        () => _check(ids: sample),
        throwsA(
          isA<ads.AdsConfigError>().having(
            (e) => e.message,
            'message',
            contains("Google's TEST IDs"),
          ),
        ),
      );
    });

    test('an unknown IDSNAP_MONETIZATION', () {
      expect(
        () => _check(mode: 'freemium'),
        throwsA(isA<MonetizationConfigError>()),
      );
    });

    test('the failure reaches the startup recovery screen, by name', () async {
      final failure = await runStartupStep(
        StartupStep.billing,
        () => _check(ids: '{}'),
      ).then<Object?>((_) => null, onError: (Object e) => e);
      expect(failure, isA<StartupFailure>());
      expect((failure! as StartupFailure).cause, isA<ads.AdsConfigError>());
    });
  });

  group('debug and profile builds', () {
    test("always use Google's sample units, never the real ones", () async {
      final setup = await _check(release: false);
      final ids = setup.adsConfig!.ids;
      expect(setup.adsConfig!.usesTestIds, isTrue);
      for (final id in [ids.appId, ids.banner, ids.interstitial, ids.native]) {
        expect(id, startsWith(ads.GoogleTestAdIds.publisher));
        expect(id, isNot(contains('6432767564862835')));
      }
    });

    test('real units only with the explicit test-device opt-in', () async {
      final setup = await _check(release: false, testDevices: 'ABCDEF012345');
      expect(setup.adsConfig!.usesTestIds, isFalse);
      expect(setup.adsConfig!.testDeviceIds, ['ABCDEF012345']);
      expect(setup.adsConfig!.ids.banner, startsWith(_ownerPublisher));
    });
  });

  group('no ads service at all', () {
    test('kill switch IDSNAP_ADS_DISABLED=true (IDs not even read)', () async {
      final setup = await checkMonetizationConfig(
        release: true,
        adsDisabled: true,
        platform: TargetPlatform.android,
        loadIds: () => fail('the IDs were read with ads disabled'),
      );
      expect(setup.mode, MonetizationMode.ads);
      expect(
        createAdsService(setup: setup, supportDirectory: '.'),
        isA<NoopAdsService>(),
      );
    });

    for (final mode in ['licence', 'store']) {
      test('$mode mode: no ads, and AdMob IDs are not required', () async {
        final setup = await checkMonetizationConfig(
          mode: mode,
          release: true,
          platform: TargetPlatform.android,
          loadIds: () => fail('the IDs were read in a paid mode'),
        );
        expect(setup.mode.showsAds, isFalse);
        expect(
          createAdsService(
            setup: setup,
            supportDirectory: '.',
            sdk: () => fail('the ads SDK was constructed in a paid mode'),
          ),
          isA<NoopAdsService>(),
        );
      });
    }

    test('desktop (tests, tools)', () async {
      final setup = await _check(platform: TargetPlatform.windows);
      expect(setup.adsConfig, isNull);
    });
  });

  group('the ads service', () {
    test('is built without running any ad code: nothing happens until an '
        'ad slot is on screen', () async {
      final setup = await _check();
      var built = 0;
      final service = createAdsService(
        setup: setup,
        supportDirectory: Directory.systemTemp.path,
        sdk: () {
          built++;
          return _InertSdk();
        },
      );
      expect(service, isA<EngineAdsService>());
      expect(built, 1);
      expect(_InertSdk.calls, 0);
      expect(service.canShowAds, isFalse);
      expect(service.privacyOptionsRequired, isFalse);
      expect(service.consentStatus, AdConsentStatus.unknown);
    });

    test(
      "takes every number from the placement policy (the owner's caps)",
      () async {
        final service =
            createAdsService(
                  setup: await _check(),
                  supportDirectory: Directory.systemTemp.path,
                  sdk: _InertSdk.new,
                )
                as EngineAdsService;
        final cap = service.engine.cap.policy;
        expect(cap.minGap, AdPlacementPolicy.interstitialMinGap);
        expect(cap.minGap, const Duration(minutes: 3));
        expect(cap.maxPerDay, AdPlacementPolicy.interstitialMaxPerDay);
        expect(cap.maxPerDay, 6);
        expect(cap.warmUp, AdPlacementPolicy.interstitialSessionWarmUp);
        expect(cap.warmUp, const Duration(seconds: 60));
        expect(cap.freeTasks, AdPlacementPolicy.interstitialFreeTasks);
        expect(cap.freeTasks, 1);
        expect(
          service.engine.bannerRetryAfter,
          AdPlacementPolicy.bannerRetryAfter,
        );
        expect(service.engine.nativeMaxAge, AdPlacementPolicy.nativeMaxAge);
      },
    );
  });

  group('startup and recovery screens never show ads', () {
    testWidgets('splash, vault recovery, startup recovery', (tester) async {
      for (final screen in <Widget>[
        VaultStartupScreen(progress: ValueNotifier<(int, int)?>(null)),
        VaultStartupScreen(progress: ValueNotifier<(int, int)?>((1, 4))),
        StartupRecoveryScreen(
          failure: StartupFailure(
            StartupStep.billing,
            ads.AdsConfigError('x'),
            StackTrace.empty,
          ),
          onRetry: () async {},
        ),
      ]) {
        await tester.pumpWidget(screen);
        await tester.pump();
        expect(find.byType(AdBannerSlot), findsNothing);
        expect(find.byType(AdNativeSlot), findsNothing);
      }
    });

    test('they are built outside the provider scope that holds the ads '
        'service', () {
      final source = File('lib/vault_startup.dart').readAsStringSync();
      expect(source, isNot(contains('adsServiceProvider')));
      expect(source, isNot(contains('AdBannerSlot')));
      final lock = File('lib/lock_gate.dart').readAsStringSync();
      expect(lock, isNot(contains('adsServiceProvider')));
      expect(lock, isNot(contains('AdBannerSlot')));
      expect(lock, isNot(contains('AdNativeSlot')));
    });
  });

  group('native hosts', () {
    test('both read the consent choice on the channel Dart calls', () {
      final kotlin = File(
        'android/app/src/main/kotlin/com/docscan/docscan_scanner/MainActivity.kt',
      ).readAsStringSync();
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      for (final src in [kotlin, swift]) {
        expect(src, contains('"${ads.GoogleAdsPlatform.consentChannelName}"'));
        expect(src, contains('"tcf"'));
        expect(src, contains('IABTCF_gdprApplies'));
        expect(src, contains('IABTCF_PurposeConsents'));
      }
    });

    test('Android: the permissions the ads SDK needs, HTTPS only, consent '
        'before measurement', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android.permission.INTERNET'));
      expect(manifest, contains('com.google.android.gms.permission.AD_ID'));
      expect(
        manifest,
        contains(
          '<uses-permission '
          'android:name="android.permission.ACCESS_NETWORK_STATE" />',
        ),
      );
      expect(manifest, contains('DELAY_APP_MEASUREMENT_INIT'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      // TLS is not pinned to one host: the ads SDK must reach Google's.
      final network = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();
      final rules = network.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      expect(rules, isNot(contains('<domain-config')));
      expect(rules, contains('cleartextTrafficPermitted="false"'));
      expect(rules, contains('<certificates src="system" />'));
    });

    test('iOS: App ID, SKAdNetwork IDs, delayed measurement, and NO '
        'tracking prompt (the IDFA is never requested)', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<key>GADApplicationIdentifier</key>'));
      expect(plist, contains(r'$(IDSNAP_ADMOB_APP_ID_IOS)'));
      expect(plist, contains('<key>GADDelayAppMeasurementInit</key>'));
      expect(plist, contains('<key>SKAdNetworkItems</key>'));
      expect(plist, contains('cstr6suwn9.skadnetwork'));
      expect(plist, isNot(contains('NSUserTrackingUsageDescription')));
      final xcconfig = File('ios/Flutter/AdMob.xcconfig').readAsStringSync();
      expect(xcconfig, contains('IDSNAP_ADMOB_APP_ID_IOS = ca-app-pub-'));
      for (final name in ['Debug.xcconfig', 'Release.xcconfig']) {
        expect(
          File('ios/Flutter/$name').readAsStringSync(),
          contains('#include "AdMob.xcconfig"'),
        );
      }
    });
  });
}

/// An ads SDK that counts calls and does nothing.
class _InertSdk implements ads.AdsPlatform {
  static int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return super.noSuchMethod(invocation);
  }
}

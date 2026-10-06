import 'package:engine_ads/engine_ads.dart';
import 'package:flutter_test/flutter_test.dart';

const _real = AdUnitIds(
  appId: 'ca-app-pub-1234567890123456~1111111111',
  banner: 'ca-app-pub-1234567890123456/2222222222',
  interstitial: 'ca-app-pub-1234567890123456/3333333333',
  native: 'ca-app-pub-1234567890123456/4444444444',
);

const _file = AdmobIdsFile(android: _real);
const _none = AdUnitIds.none();

AdsConfig? _resolve({
  required bool release,
  AdsTarget target = AdsTarget.android,
  AdmobIdsFile file = _file,
  AdUnitIds overrides = _none,
  String testDevices = '',
}) => resolveAdsConfig(
  release: release,
  target: target,
  file: file,
  overrides: overrides,
  testDevices: testDevices,
);

Matcher _configError(String text) => throwsA(
  isA<AdsConfigError>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  test('the file format', () {
    final file = AdmobIdsFile.parse('''
      {"_about": "x",
       "android": {"appId": " ca-app-pub-1234567890123456~1111111111 ",
                   "banner": "b", "interstitial": "i", "native": "n"},
       "ios": {"appId": "", "banner": "", "interstitial": "", "native": ""}}
    ''');
    expect(file.android.appId, 'ca-app-pub-1234567890123456~1111111111');
    expect(file.android.native, 'n');
    expect(file.ios.isEmpty, isTrue);
    expect(AdmobIdsFile.parse('{}').android.isEmpty, isTrue);
    expect(() => AdmobIdsFile.parse('nope'), _configError('not valid'));
    expect(() => AdmobIdsFile.parse('[]'), _configError('not valid'));
  });

  group('debug and profile builds', () {
    test("ALWAYS use Google's sample IDs for every format, even when real "
        'IDs are configured', () {
      final config = _resolve(release: false)!;
      expect(config.usesTestIds, isTrue);
      expect(config.ids.appId, GoogleTestAdIds.android.appId);
      expect(config.ids.banner, GoogleTestAdIds.android.banner);
      expect(config.ids.interstitial, GoogleTestAdIds.android.interstitial);
      expect(config.ids.native, GoogleTestAdIds.android.native);
      for (final id in [
        config.ids.appId,
        config.ids.banner,
        config.ids.interstitial,
        config.ids.native,
      ]) {
        expect(id, startsWith(GoogleTestAdIds.publisher));
      }
    });

    test('dart-define overrides do not switch a debug build to real ads', () {
      final config = _resolve(release: false, overrides: _real)!;
      expect(config.usesTestIds, isTrue);
    });

    test('the explicit opt-in: real units ONLY together with registered '
        'test devices', () {
      final config = _resolve(release: false, testDevices: ' ABC123 , DEF456')!;
      expect(config.usesTestIds, isFalse);
      expect(config.ids.banner, _real.banner);
      expect(config.testDeviceIds, ['ABC123', 'DEF456']);
    });

    test('the opt-in with unusable IDs is an error, not a silent fallback', () {
      expect(
        () => _resolve(
          release: false,
          testDevices: 'ABC123',
          file: const AdmobIdsFile(android: GoogleTestAdIds.android),
        ),
        _configError('TEST IDs'),
      );
    });
  });

  group('release builds', () {
    test('use the committed IDs with no extra flags', () {
      final config = _resolve(release: true)!;
      expect(config.usesTestIds, isFalse);
      expect(config.ids.appId, _real.appId);
      expect(config.ids.banner, _real.banner);
      expect(config.ids.interstitial, _real.interstitial);
      expect(config.ids.native, _real.native);
      expect(config.testDeviceIds, isEmpty);
    });

    test('a dart-define overrides one value of the file', () {
      const other = 'ca-app-pub-1234567890123456/9999999999';
      final config = _resolve(
        release: true,
        overrides: const AdUnitIds(
          appId: '',
          banner: other,
          interstitial: '',
          native: '',
        ),
      )!;
      expect(config.ids.banner, other);
      expect(config.ids.native, _real.native);
    });

    test('fail fast when the IDs are missing', () {
      expect(
        () => _resolve(release: true, file: const AdmobIdsFile()),
        _configError('the App ID is missing'),
      );
      expect(
        () => _resolve(
          release: true,
          file: const AdmobIdsFile(
            android: AdUnitIds(
              appId: 'ca-app-pub-1234567890123456~1111111111',
              banner: 'ca-app-pub-1234567890123456/2222222222',
              interstitial: 'ca-app-pub-1234567890123456/3333333333',
              native: '',
            ),
          ),
        ),
        _configError('the native unit is missing'),
      );
    });

    test("fail fast on Google's sample IDs (they earn nothing)", () {
      expect(
        () => _resolve(
          release: true,
          file: const AdmobIdsFile(android: GoogleTestAdIds.android),
        ),
        _configError("Google's TEST IDs"),
      );
      expect(
        () => _resolve(
          release: true,
          overrides: AdUnitIds(
            appId: '',
            banner: GoogleTestAdIds.android.banner,
            interstitial: '',
            native: '',
          ),
        ),
        _configError('the banner unit is one of'),
      );
    });

    test('fail fast on malformed IDs and mixed AdMob accounts', () {
      expect(
        () => _resolve(
          release: true,
          overrides: const AdUnitIds(
            appId: 'ca-app-pub-123~1',
            banner: '',
            interstitial: '',
            native: '',
          ),
        ),
        _configError('the App ID is not an AdMob ID'),
      );
      // An ad unit where the App ID belongs.
      expect(
        () => _resolve(
          release: true,
          overrides: const AdUnitIds(
            appId: 'ca-app-pub-1234567890123456/2222222222',
            banner: '',
            interstitial: '',
            native: '',
          ),
        ),
        _configError('not an AdMob ID'),
      );
      expect(
        () => _resolve(
          release: true,
          overrides: const AdUnitIds(
            appId: '',
            banner: 'ca-app-pub-6543210987654321/2222222222',
            interstitial: '',
            native: '',
          ),
        ),
        _configError('different AdMob accounts'),
      );
    });

    test('the message says what to do', () {
      expect(
        () => _resolve(release: true, file: const AdmobIdsFile()),
        throwsA(
          isA<AdsConfigError>()
              .having((e) => e.message, 'message', contains('admob.json'))
              .having(
                (e) => e.message,
                'message',
                contains('IDSNAP_ADS_DISABLED=true'),
              ),
        ),
      );
    });
  });

  group('iOS has no AdMob IDs yet', () {
    test('ads are simply off (null), in release and in debug: an Android '
        'release never fails for missing iOS IDs', () {
      expect(_resolve(release: true, target: AdsTarget.ios), isNull);
      expect(_resolve(release: false, target: AdsTarget.ios), isNull);
      expect(_resolve(release: true), isNotNull);
    });

    test('once iOS IDs exist they are used (and checked) like Android', () {
      const withIos = AdmobIdsFile(android: _real, ios: _real);
      expect(
        _resolve(
          release: true,
          target: AdsTarget.ios,
          file: withIos,
        )!.ids.banner,
        _real.banner,
      );
      expect(
        _resolve(
          release: false,
          target: AdsTarget.ios,
          file: withIos,
        )!.ids.banner,
        GoogleTestAdIds.ios.banner,
      );
      // Half-configured iOS is an error rather than a silent "off".
      expect(
        () => _resolve(
          release: true,
          target: AdsTarget.ios,
          file: const AdmobIdsFile(
            ios: AdUnitIds(
              appId: 'ca-app-pub-1234567890123456~1111111111',
              banner: '',
              interstitial: '',
              native: '',
            ),
          ),
        ),
        _configError('the banner unit is missing'),
      );
    });
  });
}

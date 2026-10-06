// Explicit empty URL/key arguments keep the config tests independent of
// any --dart-define the test run was started with.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:convert';

import 'package:engine_billing/engine_billing.dart';
import 'package:engine_license/engine_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_store.dart' show TestClock;

/// A scriptable licence server: signs real tokens with the dev key.
class FakeLicenceClient implements LicenceClient {
  FakeLicenceClient(this.clock);

  final TestClock clock;
  late LicenceSigner signer;
  bool online = true;
  LicenceFailureKind? failWith;

  /// Server-side state per device hash.
  final trialEnds = <String, DateTime>{};
  final plans = <String, (LicencePlan, DateTime, Duration, bool?)>{};
  final calls = <String>[];
  final checkouts = <(CheckoutProduct, int?)>[];

  /// Called on each entitlement fetch (lets a test "pay" mid-polling).
  void Function(int call)? onEntitlement;
  int _entitlementCalls = 0;

  /// Signs tokens for a different device (a misbehaving server/MITM).
  String? overrideDevice;

  Future<void> init() async =>
      signer = await LicenceSigner.fromEncodedSeed(DevLicenceKeys.privateKey);

  void _check() {
    if (!online) {
      throw const LicenceClientException(LicenceFailureKind.offline);
    }
    final f = failWith;
    if (f != null) throw LicenceClientException(f);
  }

  Future<LicenceResponse> _token(String did) async {
    final now = clock.now;
    final paid = plans[did];
    final trial = trialEnds[did]!;
    final (plan, exp, grace, rn) = paid != null && paid.$2.isAfter(trial)
        ? paid
        : (LicencePlan.trial, trial, Duration.zero, null);
    final token = await signer.sign(
      LicencePayload(
        deviceHash: overrideDevice ?? did,
        plan: plan,
        issuedAt: now,
        expiresAt: exp,
        tokenId: 't${calls.length}',
        grace: grace,
        willRenew: rn,
      ),
    );
    return LicenceResponse(
      token: token,
      serverTime: now,
      pricing: const ServerPricing(
        dayPriceCents: 10,
        monthPriceCents: 250,
        currency: 'USD',
        minDays: 1,
        maxDays: 24,
      ),
    );
  }

  @override
  Future<LicenceResponse> register({
    required String deviceHash,
    required String platform,
    required String appVersion,
  }) async {
    calls.add('register');
    _check();
    trialEnds.putIfAbsent(
      deviceHash,
      () => clock.now.add(const Duration(hours: 24)),
    );
    return await _token(deviceHash);
  }

  @override
  Future<LicenceResponse> entitlement(String deviceHash) async {
    calls.add('entitlement');
    _check();
    onEntitlement?.call(++_entitlementCalls);
    if (!trialEnds.containsKey(deviceHash)) {
      throw const LicenceClientException(LicenceFailureKind.notRegistered);
    }
    return await _token(deviceHash);
  }

  @override
  Future<ServerPricing> config() async {
    calls.add('config');
    _check();
    return const ServerPricing(
      dayPriceCents: 12,
      monthPriceCents: 300,
      currency: 'USD',
      minDays: 1,
      maxDays: 30,
    );
  }

  @override
  Future<CheckoutResponse> checkout({
    required String deviceHash,
    required CheckoutProduct product,
    int? days,
  }) async {
    calls.add('checkout');
    _check();
    checkouts.add((product, days));
    return CheckoutResponse(
      sessionId: 'cs_1',
      checkoutUrl: Uri.parse('https://pay.180workspace.com/checkout/cs_1'),
      amountCents: product == CheckoutProduct.day ? days! * 10 : 250,
      currency: 'USD',
    );
  }

  @override
  Future<Uri> portal(String deviceHash) async {
    calls.add('portal');
    _check();
    return Uri.parse('https://auth.180workspace.com/portal/pts_1');
  }
}

void main() {
  late TestClock clock;
  late FakeLicenceClient server;
  late MemoryBillingStorage storage;
  late List<Uri> opened;
  final identity = FixedDeviceIdentity('android-id-1');
  late String did;

  setUp(() async {
    clock = TestClock(DateTime.utc(2026, 10, 6, 12));
    server = FakeLicenceClient(clock);
    await server.init();
    storage = MemoryBillingStorage();
    opened = [];
    did = await identity.deviceHash();
  });

  LicenceEngine engine({
    DeviceIdentity? id,
    List<Duration> poll = const [
      Duration(seconds: 5),
      Duration(seconds: 5),
      Duration(seconds: 5),
    ],
  }) => LicenceEngine(
    storage: storage,
    client: server,
    verifier: LicenceVerifier.fromEncodedKey(DevLicenceKeys.publicKey),
    identity: id ?? identity,
    openUrl: (url) async {
      opened.add(url);
      return true;
    },
    platform: 'android',
    appVersion: '1.0.0',
    now: clock.call,
    sleep: (d) async => clock.advance(d),
    pollSchedule: poll,
  );

  group('first launch', () {
    test('online: registers and starts the free day', () async {
      final e = engine();
      await e.start();
      expect(e.status.lapse, LicenceLapse.notActivated);
      final r = await e.refresh();
      expect(r.ok, isTrue);
      expect(server.calls, ['register']);
      expect(e.status.kind, LicenceKind.trial);
      expect(e.status.expiresAt, clock.now.add(const Duration(hours: 24)));
      expect(storage.values[LicenceEngine.tokenKey], isNotNull);
    });

    test('offline with no token: not activated, never silent access', () async {
      server.online = false;
      final e = engine();
      await e.start();
      final r = await e.refresh();
      expect(r.ok, isFalse);
      expect(r.failure, LicenceFailureKind.offline);
      expect(e.status.isEntitled, isFalse);
      expect(e.status.lapse, LicenceLapse.notActivated);
      // Coming online later activates it.
      server.online = true;
      await e.refresh();
      expect(e.status.kind, LicenceKind.trial);
    });

    test('reinstall: re-registering keeps the original free day', () async {
      final first = engine();
      await first.start();
      await first.refresh();
      clock.advance(const Duration(hours: 30));
      storage = MemoryBillingStorage(); // app data wiped
      final again = engine();
      await again.start();
      await again.refresh();
      expect(again.status.kind, LicenceKind.expired);
      expect(again.status.lapse, LicenceLapse.trialEnded);
    });
  });

  group('offline use', () {
    test('a valid token works with no network at all', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      server.online = false;
      clock.advance(const Duration(hours: 10));
      final cold = engine();
      await cold.start();
      await cold.refresh();
      expect(cold.status.kind, LicenceKind.trial);
    });

    test('trial → expiry → paywall, on time, offline', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      server.online = false;
      clock.advance(const Duration(hours: 23, minutes: 59));
      expect(e.status.isEntitled, isTrue);
      clock.advance(const Duration(minutes: 1));
      expect(e.status.isEntitled, isFalse);
      expect(e.status.lapse, LicenceLapse.trialEnded);
    });

    test('server unreachable keeps a valid token working', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      server.failWith = LicenceFailureKind.server;
      final r = await e.refresh();
      expect(r.ok, isFalse);
      expect(e.status.kind, LicenceKind.trial);
      server
        ..failWith = null
        ..online = false;
      expect((await e.refresh()).ok, isFalse);
      expect(e.status.kind, LicenceKind.trial);
    });
  });

  group('purchases', () {
    test('day pass: checkout opens in the browser, polling unlocks', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      clock.advance(const Duration(hours: 25));
      expect(e.status.isEntitled, isFalse);
      server.onEntitlement = (call) {
        // The webhook arrives while the app polls (second poll).
        if (call == 2) {
          server.plans[did] = (
            LicencePlan.day,
            clock.now.add(const Duration(days: 3)),
            Duration.zero,
            null,
          );
        }
      };
      final pending = <bool>[];
      final sub = e.changes.listen((s) => pending.add(s.purchasePending));
      final r = await e.purchase(CheckoutProduct.day, days: 3);
      await sub.cancel();
      expect(r.kind, LicencePurchaseKind.purchased);
      expect(server.checkouts.single, (CheckoutProduct.day, 3));
      expect(opened.single.host, 'pay.180workspace.com');
      expect(e.status.kind, LicenceKind.dayPass);
      expect(pending, contains(true));
      expect(e.status.purchasePending, isFalse);
    });

    test('no payment within the window: pending, still locked', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      clock.advance(const Duration(hours: 25));
      final r = await e.purchase(CheckoutProduct.day, days: 1);
      expect(r.kind, LicencePurchaseKind.pending);
      expect(e.status.isEntitled, isFalse);
      // The webhook arrives later; the next refresh (resume) unlocks.
      server.plans[did] = (
        LicencePlan.day,
        clock.now.add(const Duration(days: 1)),
        Duration.zero,
        null,
      );
      await e.refresh();
      expect(e.status.kind, LicenceKind.dayPass);
    });

    test('monthly: purchase, grace past the period, refresh window', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      final periodEnd = clock.now.add(const Duration(days: 30));
      server.onEntitlement = (_) => server.plans[did] = (
        LicencePlan.monthly,
        periodEnd.add(const Duration(days: 3)),
        const Duration(days: 3),
        true,
      );
      expect(
        (await e.purchase(CheckoutProduct.monthly)).kind,
        LicencePurchaseKind.purchased,
      );
      expect(e.status.kind, LicenceKind.monthly);
      expect(e.status.paidUntil, periodEnd);
      expect(e.status.willRenew, isTrue);
      expect(e.shouldRefresh, isFalse);
      // Within 3 days of the end: the app tries to refresh.
      clock.now = periodEnd.subtract(const Duration(days: 1));
      expect(e.shouldRefresh, isTrue);
      // Offline past the period end: grace keeps it unlocked.
      server.online = false;
      clock.now = periodEnd.add(const Duration(days: 1));
      expect(e.status.kind, LicenceKind.monthly);
      expect(e.status.inGracePeriod, isTrue);
      clock.now = periodEnd.add(const Duration(days: 3));
      expect(e.status.lapse, LicenceLapse.monthlyEnded);
    });

    test('offline: purchase says so and opens nothing', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      server.online = false;
      final r = await e.purchase(CheckoutProduct.day, days: 1);
      expect(r.kind, LicencePurchaseKind.offline);
      expect(opened, isEmpty);
    });

    test('server rejection carries its message', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      server.failWith = LicenceFailureKind.rejected;
      final r = await e.purchase(CheckoutProduct.monthly);
      expect(r.kind, LicencePurchaseKind.failed);
    });

    test('manage subscription opens the portal URL', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      expect(await e.openManageSubscription(), isTrue);
      expect(opened.single.path, '/portal/pts_1');
      server.online = false;
      expect(await e.openManageSubscription(), isFalse);
    });
  });

  group('tamper and rollback', () {
    test('clock set back: locked until fixed (offline)', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      server.online = false;
      clock.advance(const Duration(hours: 30)); // trial over
      expect(e.status.isEntitled, isFalse);
      clock.now = DateTime.utc(2026, 10, 6, 13); // set back into the trial
      expect(e.status.lapse, LicenceLapse.clockTampered);
      // Survives a cold start (max-time-seen is persisted).
      final cold = engine();
      await cold.start();
      expect(cold.status.lapse, LicenceLapse.clockTampered);
    });

    test('server time catches a clock set back while online', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      // The server's clock moves on; the phone's is set back two days.
      final real = clock.now.add(const Duration(days: 2));
      clock.now = real;
      await e.refresh();
      clock.now = real.subtract(const Duration(days: 2));
      expect(e.status.lapse, LicenceLapse.clockTampered);
    });

    test('a token for another device is rejected', () async {
      server.overrideDevice = hashDeviceId('someone-else');
      final e = engine();
      await e.start();
      final r = await e.refresh();
      expect(r.ok, isFalse);
      expect(r.failure, LicenceFailureKind.invalidResponse);
      expect(e.status.lapse, LicenceLapse.notActivated);
    });

    test('a stored token copied from another phone is discarded', () async {
      final other = engine(id: FixedDeviceIdentity('other-phone'));
      await other.start();
      await other.refresh();
      expect(storage.values[LicenceEngine.tokenKey], isNotNull);
      server.online = false;
      final mine = engine();
      await mine.start();
      expect(mine.status.lapse, LicenceLapse.notActivated);
      expect(storage.values[LicenceEngine.tokenKey], isNull);
    });

    test('an edited stored token is discarded', () async {
      final e = engine();
      await e.start();
      await e.refresh();
      final token = storage.values[LicenceEngine.tokenKey]!;
      final parts = token.split('.');
      final json =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
              )
              as Map<String, Object?>;
      json['exp'] = 4102444800; // 2100
      storage.values[LicenceEngine.tokenKey] =
          '${base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '')}.${parts[1]}';
      server.online = false;
      final cold = engine();
      await cold.start();
      expect(cold.status.lapse, LicenceLapse.notActivated);
    });

    test('a token signed with another key is rejected', () async {
      final pair = await generateLicenceKeyPair();
      server.signer = await LicenceSigner.fromEncodedSeed(pair.privateKey);
      final e = engine();
      await e.start();
      expect((await e.refresh()).failure, LicenceFailureKind.invalidResponse);
      expect(e.status.isEntitled, isFalse);
    });
  });

  group('pricing', () {
    test(
      'server prices, cached; labelled fallback before first contact',
      () async {
        server.online = false;
        final e = engine();
        await e.start();
        final fallback = await e.pricing();
        expect(fallback.fromServer, isFalse);
        expect(fallback.monthPriceCents, 250);
        server.online = true;
        final live = await e.pricing();
        expect(
          (live.fromServer, live.dayPriceCents, live.maxDays),
          (true, 12, 30),
        );
        server.online = false;
        expect((await e.pricing()).dayPriceCents, 12);
      },
    );
  });

  group('config', () {
    test('release builds fail fast without a URL or with the dev key', () {
      expect(
        () => resolveLicenceSettings(release: true, url: '', publicKey: ''),
        throwsA(isA<LicenceConfigError>()),
      );
      expect(
        () => resolveLicenceSettings(
          release: true,
          url: 'http://licence.example.com',
          publicKey: 'x',
        ),
        throwsA(isA<LicenceConfigError>()),
      );
      expect(
        () => resolveLicenceSettings(
          release: true,
          url: 'https://licence.example.com',
          publicKey: DevLicenceKeys.publicKey,
        ),
        throwsA(isA<LicenceConfigError>()),
      );
    });

    test(
      'release with a real key; debug defaults to localhost + dev key',
      () async {
        final pair = await generateLicenceKeyPair();
        final s = resolveLicenceSettings(
          release: true,
          url: 'https://licence.example.com',
          publicKey: pair.publicKey,
        );
        expect(s.baseUrl.host, 'licence.example.com');
        final d = resolveLicenceSettings(
          release: false,
          url: '',
          publicKey: '',
        );
        expect(d.baseUrl.toString(), debugLicenceUrl);
        expect(d.publicKey, DevLicenceKeys.publicKey);
      },
    );
  });

  group('HttpLicenceClient', () {
    test('typed failures, retries with backoff for idempotent calls', () async {
      var attempts = 0;
      final waits = <Duration>[];
      final client = HttpLicenceClient(
        baseUrl: Uri.parse('https://licence.example.com'),
        sleep: (d) async => waits.add(d),
        client: MockClient((request) async {
          attempts++;
          if (attempts < 3) return http.Response('oops', 503);
          return http.Response(
            jsonEncode({'token': 'a.b', 'serverTime': 1791230400}),
            200,
          );
        }),
      );
      final r = await client.entitlement('d' * 64);
      expect(r.token, 'a.b');
      expect(attempts, 3);
      expect(waits, hasLength(2));
      expect(waits[1] > waits[0], isTrue);
    });

    test('error mapping', () async {
      Future<LicenceFailureKind> kindFor(http.Response response) async {
        final client = HttpLicenceClient(
          baseUrl: Uri.parse('https://licence.example.com'),
          retries: 0,
          client: MockClient((_) async => response),
        );
        try {
          await client.entitlement('d' * 64);
        } on LicenceClientException catch (e) {
          return e.kind;
        }
        fail('expected an exception');
      }

      expect(
        await kindFor(
          http.Response(
            jsonEncode({
              'error': {'code': 'device_not_registered', 'message': 'x'},
            }),
            404,
          ),
        ),
        LicenceFailureKind.notRegistered,
      );
      expect(
        await kindFor(http.Response('{}', 429)),
        LicenceFailureKind.rateLimited,
      );
      expect(
        await kindFor(http.Response('{}', 500)),
        LicenceFailureKind.server,
      );
      expect(
        await kindFor(http.Response('{}', 409)),
        LicenceFailureKind.rejected,
      );
      expect(
        await kindFor(http.Response('not json', 200)),
        LicenceFailureKind.invalidResponse,
      );
      expect(
        await kindFor(http.Response('{"token": 5}', 200)),
        LicenceFailureKind.invalidResponse,
      );
    });

    test(
      'connection errors are "offline"; checkout is never retried',
      () async {
        var attempts = 0;
        final client = HttpLicenceClient(
          baseUrl: Uri.parse('https://licence.example.com'),
          sleep: (_) async {},
          client: MockClient((_) async {
            attempts++;
            throw http.ClientException('no route');
          }),
        );
        await expectLater(
          client.checkout(
            deviceHash: 'd' * 64,
            product: CheckoutProduct.monthly,
          ),
          throwsA(
            isA<LicenceClientException>().having(
              (e) => e.kind,
              'kind',
              LicenceFailureKind.offline,
            ),
          ),
        );
        expect(attempts, 1);
      },
    );

    test('sends only the device hash; checkout URL must be https', () async {
      late http.Request seen;
      final client = HttpLicenceClient(
        baseUrl: Uri.parse('https://licence.example.com/base'),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'sessionId': 'cs_1',
              'checkoutUrl': 'http://pay.example.com/x',
              'amountCents': 30,
              'currency': 'USD',
            }),
            200,
          );
        }),
      );
      await expectLater(
        client.checkout(
          deviceHash: 'd' * 64,
          product: CheckoutProduct.day,
          days: 3,
        ),
        throwsA(isA<LicenceClientException>()),
      );
      expect(
        seen.url.toString(),
        'https://licence.example.com/base/v1/checkout',
      );
      expect(jsonDecode(seen.body), {
        'deviceId': 'd' * 64,
        'product': 'day',
        'days': 3,
      });
    });
  });
}

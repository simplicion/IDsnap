import 'dart:convert';

import 'package:license_server/license_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../tool/create_plan.dart' show createMonthlyPlan, monthlyPlan;
import 'support.dart';

void main() {
  late Harness h;
  late Handler handler;

  Future<Response> call(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    String ip = '1.2.3.4',
    bool proxy = true,
  }) async => await handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : (body is String ? body : jsonEncode(body)),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (proxy) 'x-forwarded-for': ip,
        ...?headers,
      },
    ),
  );

  Future<Map<String, Object?>> json(Response r) async =>
      jsonDecode(await r.readAsString()) as Map<String, Object?>;

  setUp(() async {
    h = await Harness.create();
    handler = buildHandler(
      h.service,
      trustProxy: true,
      limits: RateLimits(
        now: h.clock.call,
        perIpPerMinute: 20,
        perDevicePerMinute: 8,
        checkoutsPerDevicePer10Min: 3,
        newDevicesPerIpPerHour: 2,
      ),
    );
  });

  test('register → entitlement → config over HTTP', () async {
    final r = await call(
      'POST',
      '/v1/devices/register',
      body: {
        'deviceId': device(1),
        'platform': 'android',
        'appVersion': '1.0.0',
      },
    );
    expect(r.statusCode, 200);
    expect(r.headers['cache-control'], 'no-store');
    final reg = await json(r);
    expect((await h.token(reg)).deviceHash, device(1));

    final e = await call('GET', '/v1/entitlement?deviceId=${device(1)}');
    expect(e.statusCode, 200);
    expect((await json(e))['serverTime'], isA<int>());

    final c = await json(await call('GET', '/v1/config'));
    expect(c['monthPriceCents'], 250);
    expect(c['maxDays'], 24);
  });

  test(
    'strict input: unknown fields, wrong type, bad JSON, too large',
    () async {
      expect(
        (await call(
          'POST',
          '/v1/devices/register',
          body: {
            'deviceId': device(1),
            'platform': 'android',
            'appVersion': '1',
            'trialHours': 9999,
          },
        )).statusCode,
        400,
      );
      expect(
        (await call(
          'POST',
          '/v1/checkout',
          body: {
            'deviceId': device(1),
            'product': 'day',
            'days': 1,
            'amount': 0.01,
          },
        )).statusCode,
        400,
        reason: 'the client can never send a price',
      );
      expect(
        (await call('POST', '/v1/checkout', body: '{nope')).statusCode,
        400,
      );
      expect((await call('POST', '/v1/checkout', body: '[]')).statusCode, 400);
      expect(
        (await call(
          'POST',
          '/v1/checkout',
          body: '{}',
          headers: {'content-type': 'text/plain'},
        )).statusCode,
        415,
      );
      expect(
        (await call(
          'POST',
          '/v1/checkout',
          body: {'deviceId': 'x' * 5000},
        )).statusCode,
        413,
      );
      expect((await call('GET', '/v1/entitlement')).statusCode, 400);
      expect(
        (await call('GET', '/v1/entitlement?deviceId=abc')).statusCode,
        400,
      );
      expect((await call('GET', '/v1/nope')).statusCode, 404);
      expect((await call('GET', '/webhooks/180-pay')).statusCode, 405);
    },
  );

  test('errors have a stable shape and leak nothing', () async {
    final r = await call('GET', '/v1/entitlement?deviceId=${device(7)}');
    expect(r.statusCode, 404);
    expect(await json(r), {
      'error': {
        'code': 'device_not_registered',
        'message': 'Unknown device. Register it first.',
      },
    });
  });

  test('checkout and webhook over HTTP with the raw body', () async {
    await call(
      'POST',
      '/v1/devices/register',
      body: {'deviceId': device(1), 'platform': 'ios', 'appVersion': '1.0'},
    );
    final c = await json(
      await call(
        'POST',
        '/v1/checkout',
        body: {'deviceId': device(1), 'product': 'day', 'days': 3},
      ),
    );
    expect(c['amountCents'], 30);
    // Unusual but valid JSON formatting: the signature is over these exact
    // bytes, so re-serialising would break it.
    final raw =
        '{ "event" : "payment.captured",\n  "data": {"sessionId":"${c['sessionId']}","amount":0.30,"currency":"USD"} }';
    final ok = await call(
      'POST',
      '/webhooks/180-pay',
      body: raw,
      headers: signedHeaders(utf8.encode(raw), sentAt: h.clock.now),
    );
    expect(ok.statusCode, 200);
    expect((await json(ok))['outcome'], 'fulfilled_day');

    final bad = await call(
      'POST',
      '/webhooks/180-pay',
      body: raw,
      headers: {
        ...signedHeaders(utf8.encode(raw), sentAt: h.clock.now),
        'X-180-Signature': '0' * 64,
      },
    );
    expect(bad.statusCode, 401);
  });

  group('rate limiting', () {
    test('per IP', () async {
      for (var i = 0; i < 20; i++) {
        expect((await call('GET', '/v1/config')).statusCode, 200);
      }
      final limited = await call('GET', '/v1/config');
      expect(limited.statusCode, 429);
      expect(limited.headers['retry-after'], isNotNull);
      // Another address is unaffected; the window slides.
      expect((await call('GET', '/v1/config', ip: '5.6.7.8')).statusCode, 200);
      h.clock.advance(const Duration(minutes: 1, seconds: 1));
      expect((await call('GET', '/v1/config')).statusCode, 200);
    });

    test('per device, across addresses', () async {
      await h.register(device(1));
      for (var i = 0; i < 8; i++) {
        expect(
          (await call(
            'GET',
            '/v1/entitlement?deviceId=${device(1)}',
            ip: '10.0.0.$i',
          )).statusCode,
          200,
        );
      }
      expect(
        (await call(
          'GET',
          '/v1/entitlement?deviceId=${device(1)}',
          ip: '10.0.1.1',
        )).statusCode,
        429,
      );
    });

    test('checkouts per device', () async {
      await h.register(device(1));
      for (var i = 0; i < 3; i++) {
        expect(
          (await call(
            'POST',
            '/v1/checkout',
            body: {'deviceId': device(1), 'product': 'day', 'days': 1},
          )).statusCode,
          200,
        );
      }
      expect(
        (await call(
          'POST',
          '/v1/checkout',
          body: {'deviceId': device(1), 'product': 'day', 'days': 1},
        )).statusCode,
        429,
      );
    });

    test(
      'new trials per IP; re-registering a known device is not limited',
      () async {
        Future<int> reg(int n) async => (await call(
          'POST',
          '/v1/devices/register',
          body: {
            'deviceId': device(n),
            'platform': 'android',
            'appVersion': '1',
          },
        )).statusCode;
        expect(await reg(1), 200);
        expect(await reg(2), 200);
        expect(await reg(3), 429);
        expect(await reg(1), 200);
      },
    );
  });

  test('return page is static HTML with a strict CSP', () async {
    final r = await call('GET', '/v1/checkout/return?status=success');
    expect(r.statusCode, 200);
    expect(
      r.headers['content-security-policy'],
      contains("default-src 'none'"),
    );
    expect(await r.readAsString(), contains('go back to IDSnap'));
  });

  group('config', () {
    test('defaults', () {
      final c = ServerConfig.fromEnv(testEnv());
      expect(c.coreUrl.toString(), 'https://services.180workspace.com');
      expect(c.payUrl.toString(), 'https://pay.180workspace.com');
      expect(
        (c.trialHours, c.dayPriceCents, c.monthPriceCents, c.currency),
        (24, 10, 250, 'USD'),
      );
      expect(
        (c.minDays, c.maxDays, c.monthlyPlanCode),
        (1, 24, 'idsnap-monthly'),
      );
    });

    test('secrets are required; problems name variables, not values', () {
      try {
        ServerConfig.fromEnv({'LICENSE_SIGNING_KEY': 'garbage-secret-value'});
        fail('should throw');
      } on ConfigException catch (e) {
        final text = e.toString();
        expect(text, contains('ONE_EIGHTY_CLIENT_ID'));
        expect(text, contains('ONE_EIGHTY_CLIENT_SECRET'));
        expect(text, contains('ONE_EIGHTY_WEBHOOK_SECRET'));
        expect(text, contains('LICENSE_SIGNING_KEY must be'));
        expect(text, isNot(contains('garbage-secret-value')));
      }
    });

    test('the published dev key is refused unless ALLOW_DEV_KEY', () {
      expect(
        () => ServerConfig.fromEnv(testEnv({'ALLOW_DEV_KEY': ''})),
        throwsA(isA<ConfigException>()),
      );
    });

    test('validation of numbers, URLs and modes', () {
      for (final bad in [
        {'MIN_DAYS': '5', 'MAX_DAYS': '2'},
        {'DAY_PRICE_CENTS': '0'},
        {'DAY_PRICE_CENTS': 'ten'},
        {'ONE_EIGHTY_CORE_URL': 'http://services.180workspace.com'},
        {'PUBLIC_BASE_URL': 'ftp://x'},
        {'CURRENCY': 'dollars'},
        {'MONTHLY_PLAN_CODE': 'bad code!'},
        {'ONE_EIGHTY_CHECKOUT_MODE': 'magic'},
      ]) {
        expect(
          () => ServerConfig.fromEnv(testEnv(bad)),
          throwsA(isA<ConfigException>()),
          reason: '$bad',
        );
      }
      expect(
        ServerConfig.fromEnv(
          testEnv({'ONE_EIGHTY_CORE_URL': 'http://localhost:4003'}),
        ).coreUrl.port,
        4003,
      );
    });
  });

  group('tool/create_plan.dart', () {
    test('posts the documented body with the bearer secret', () async {
      final lines = <String>[];
      final code = await createMonthlyPlan(
        config: h.config,
        gateway: OneEightyPayGateway(h.config, client: h.fake.client),
        out: lines.add,
      );
      expect(code, 0);
      final req = h.fake.requests.single;
      expect(req.method, 'POST');
      expect(
        req.url.toString(),
        'https://services.180workspace.com/api/v1/subscriptions/plans',
      );
      expect(req.headers['authorization'], 'Bearer 180_secret_test');
      final body = jsonDecode(req.body) as Map<String, Object?>;
      expect(body, {
        'planCode': 'idsnap-monthly',
        'name': 'IDSnap Monthly',
        'description': monthlyPlan(h.config).description,
        'amount': 2.5,
        'currency': 'USD',
        'interval': 'MONTHLY',
        'intervalCount': 1,
        'trialDays': 0,
        'metadata': {'app': 'idsnap', 'product': 'monthly'},
      });
      expect(lines.last, contains('Plan created'));
    });

    test('reports a refusal with a non-zero exit code', () async {
      h.fake.status = 409;
      final lines = <String>[];
      final code = await createMonthlyPlan(
        config: h.config,
        gateway: OneEightyPayGateway(h.config, client: h.fake.client),
        out: lines.add,
      );
      expect(code, 1);
      expect(lines.first, 'HTTP 409');
    });
  });
}

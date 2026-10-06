import 'dart:convert';

import 'package:engine_license/engine_license.dart';
import 'package:license_server/license_server.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Harness h;

  setUp(() async => h = await Harness.create());

  group('registration', () {
    test(
      'first registration starts a 24 h trial with a signed token',
      () async {
        final r = await h.register(device(1));
        final t = await h.token(r);
        expect(t.plan, LicencePlan.trial);
        expect(t.deviceHash, device(1));
        expect(t.expiresAt, h.clock.now.add(const Duration(hours: 24)));
        expect(r['serverTime'], h.clock.now.millisecondsSinceEpoch ~/ 1000);
        expect((r['entitlement']! as Map)['status'], 'trial');
        expect((r['pricing']! as Map)['dayPriceCents'], 10);
      },
    );

    test('re-registering (reinstall) never restarts the trial', () async {
      final first = await h.token(await h.register(device(1)));
      h.clock.advance(const Duration(hours: 30));
      final again = await h.register(device(1));
      final t = await h.token(again);
      expect(t.expiresAt, first.expiresAt);
      expect((again['entitlement']! as Map)['status'], 'expired');
      expect((again['entitlement']! as Map)['reason'], 'trial_ended');
      // And again, later: still no new trial.
      h.clock.advance(const Duration(days: 300));
      expect(
        (await h.token(await h.register(device(1)))).expiresAt,
        first.expiresAt,
      );
    });

    test('strict validation', () async {
      Future<void> bad(
        Object? id,
        Object? platform,
        Object? version,
        String code,
      ) => expectLater(
        h.service.register(
          deviceId: id,
          platform: platform,
          appVersion: version,
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
      );
      await bad('not-a-hash', 'android', '1.0', 'invalid_device_id');
      await bad(device(1).toUpperCase(), 'android', '1.0', 'invalid_device_id');
      await bad(42, 'android', '1.0', 'invalid_device_id');
      await bad(device(1), 'windows', '1.0', 'invalid_platform');
      await bad(device(1), 'android', '', 'invalid_app_version');
      await bad(device(1), 'android', '1.0; DROP TABLE', 'invalid_app_version');
      expect(h.store.device(device(1)), isNull);
    });

    test('unknown device: entitlement is 404', () async {
      await expectLater(
        h.service.entitlement(device(9)),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
    });

    test('new-device limiter is consulted only for new devices', () async {
      await h.register(device(1));
      var asked = 0;
      await h.service.register(
        deviceId: device(1),
        platform: 'ios',
        appVersion: '1.0',
        allowNewDevice: () {
          asked++;
          return false;
        },
      );
      expect(asked, 0);
      await expectLater(
        h.service.register(
          deviceId: device(2),
          platform: 'ios',
          appVersion: '1.0',
          allowNewDevice: () => false,
        ),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 429)),
      );
    });
  });

  group('checkout', () {
    setUp(() => h.register(device(1)));

    test('day pass: amount computed server-side, days x price', () async {
      final c = await h.checkout(device(1), days: 7);
      expect(c['amountCents'], 70);
      expect(c['amount'], 0.7);
      expect(c['currency'], 'USD');
      expect(c['sessionId'], 'cs_gw_1');
      expect(c['orderRef'], matches(RegExp(r'^cs_[A-Za-z0-9]{24}$')));
      expect(c['checkoutUrl'], startsWith('https://auth.180workspace.com/'));
      final sent = jsonDecode(h.fake.requests.single.body) as Map;
      expect(sent['amount'], 0.7);
      expect(sent['mode'], 'payment');
      expect((sent['metadata'] as Map)['orderRef'], c['orderRef']);
      expect(
        h.fake.requests.single.headers['authorization'],
        'Bearer 180_secret_test',
      );
    });

    test('monthly: 2.50 USD with the plan code', () async {
      final c = await h.checkout(device(1), product: 'monthly');
      expect(c['amountCents'], 250);
      final sent = jsonDecode(h.fake.requests.single.body) as Map;
      expect(sent['mode'], 'subscription');
      expect(sent['planCode'], 'idsnap-monthly');
      expect(sent['amount'], 2.5);
    });

    test('validation: days within MIN..MAX, known product', () async {
      Future<void> bad(Object? product, Object? days, String code) =>
          expectLater(
            h.service.checkout(
              deviceId: device(1),
              product: product,
              days: days,
            ),
            throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
          );
      await bad('day', 0, 'invalid_days');
      await bad('day', 25, 'invalid_days');
      await bad('day', null, 'invalid_days');
      await bad('day', 1.5, 'invalid_days');
      await bad('day', '3', 'invalid_days');
      await bad('monthly', 3, 'invalid_days');
      await bad('lifetime', null, 'invalid_product');
      await bad(null, 1, 'invalid_product');
      expect((await h.checkout(device(1), days: 24))['amountCents'], 240);
    });

    test('unregistered device cannot check out', () async {
      await expectLater(
        h.checkout(device(5)),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'device_not_registered',
          ),
        ),
      );
    });

    test('gateway down: 502 and the order is marked failed', () async {
      h.fake.status = 503;
      await expectLater(
        h.checkout(device(1)),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 502)),
      );
    });

    test('hosted_url mode builds the documented checkout URL', () async {
      final hosted = await Harness.create(
        env: {'ONE_EIGHTY_CHECKOUT_MODE': 'hosted_url'},
      );
      await hosted.register(device(1));
      final c = await hosted.checkout(device(1), days: 3);
      expect(c['sessionId'], c['orderRef']);
      final url = Uri.parse(c['checkoutUrl']! as String);
      expect(url.origin, 'https://pay.180workspace.com');
      expect(url.path, '/checkout/${c['sessionId']}');
      expect(url.queryParameters, containsPair('amount', '0.3'));
      expect(url.queryParameters, containsPair('currency', 'USD'));
      expect(url.queryParameters, containsPair('app', 'pay'));
      expect(url.queryParameters, containsPair('ux_mode', 'full_page'));
      expect(url.queryParameters, containsPair('env', 'production'));
      expect(url.queryParameters, containsPair('appName', 'IDSnap'));
      expect(hosted.fake.requests, isEmpty);
    });

    test('a second monthly plan is refused while one renews', () async {
      final c = await h.checkout(device(1), product: 'monthly');
      expect(h.pay(c).outcome, 'fulfilled_monthly');
      await expectLater(
        h.checkout(device(1), product: 'monthly'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'already_subscribed',
          ),
        ),
      );
    });
  });

  group('webhook security', () {
    late Map<String, Object?> c;

    setUp(() async {
      await h.register(device(1));
      c = await h.checkout(device(1), days: 2);
    });

    test('valid signature fulfils', () async {
      expect(h.pay(c).outcome, 'fulfilled_day');
      expect((await h.current(device(1))).plan, LicencePlan.day);
    });

    test('bad signature (wrong secret) is 401 and grants nothing', () async {
      final r = h.deliver('payment.captured', {
        'sessionId': c['sessionId'],
        'amount': c['amount'],
        'currency': 'USD',
      }, secret: 'whsec_attacker');
      expect((r.status, r.outcome), (401, 'bad_signature'));
      expect(h.store.device(device(1))!.paidUntil, isNull);
    });

    test('tampered body with the original signature is rejected', () {
      final body = utf8.encode(
        jsonEncode({
          'event': 'payment.captured',
          'data': {
            'sessionId': c['sessionId'],
            'amount': 0.2,
            'currency': 'USD',
          },
        }),
      );
      final headers = signedHeaders(body, sentAt: h.clock.now);
      final forged = utf8.encode(utf8.decode(body).replaceAll('0.2', '0.02'));
      final r = h.service.webhook(headers: headers, rawBody: forged);
      expect(r.outcome, 'bad_signature');
    });

    test('stale timestamp: > 300 s either way is refused, 300 s is fine', () {
      final c2Data = {'sessionId': 'x', 'amount': 1, 'currency': 'USD'};
      expect(
        h
            .deliver(
              'payment.captured',
              c2Data,
              sentAt: h.clock.now.subtract(const Duration(seconds: 301)),
            )
            .outcome,
        'stale_timestamp',
      );
      expect(
        h
            .deliver(
              'payment.captured',
              c2Data,
              sentAt: h.clock.now.add(const Duration(seconds: 301)),
            )
            .outcome,
        'stale_timestamp',
      );
      expect(
        h
            .deliver(
              'payment.captured',
              c2Data,
              sentAt: h.clock.now.subtract(const Duration(seconds: 300)),
            )
            .status,
        200,
      );
    });

    test('missing headers is 400', () {
      final r = h.service.webhook(
        headers: const {},
        rawBody: utf8.encode('{}'),
      );
      expect((r.status, r.outcome), (400, 'missing_headers'));
    });

    test('header names are case-insensitive', () {
      final body = utf8.encode(
        jsonEncode({'event': 'coupon.redeemed', 'data': <String, Object?>{}}),
      );
      final headers = signedHeaders(
        body,
        sentAt: h.clock.now,
      ).map((k, v) => MapEntry(k.toLowerCase(), v));
      expect(h.service.webhook(headers: headers, rawBody: body).status, 200);
    });

    test('replay of the same event extends only once', () async {
      final body = utf8.encode(
        jsonEncode({
          'event': 'payment.captured',
          'data': {
            'sessionId': c['sessionId'],
            'amount': c['amount'],
            'currency': 'USD',
          },
        }),
      );
      final headers = signedHeaders(body, sentAt: h.clock.now);
      expect(
        h.service.webhook(headers: headers, rawBody: body).outcome,
        'fulfilled_day',
      );
      h.clock.advance(const Duration(seconds: 60));
      expect(
        h.service.webhook(headers: headers, rawBody: body).outcome,
        'duplicate',
      );
      expect(
        h.store.device(device(1))!.paidUntil,
        h.clock.now
            .subtract(const Duration(seconds: 60))
            .add(const Duration(hours: 48)),
      );
    });

    test(
      'duplicate delivery with a new id/timestamp: session paid once',
      () async {
        expect(h.pay(c, extra: {}).outcome, 'fulfilled_day');
        final paid = h.store.device(device(1))!.paidUntil;
        h.clock.advance(const Duration(minutes: 1));
        expect(
          h.deliver('payment.succeeded', {
            'sessionId': c['sessionId'],
            'amount': c['amount'],
            'currency': 'USD',
          }, id: 'evt_other').outcome,
          'already_paid',
        );
        expect(h.store.device(device(1))!.paidUntil, paid);
      },
    );

    test('underpayment (tampered checkout URL) grants nothing', () async {
      expect(h.pay(c, amount: 0.01).outcome, 'amount_mismatch');
      expect(h.pay(c, amount: 0.1).outcome, 'amount_mismatch');
      expect(h.store.device(device(1))!.paidUntil, isNull);
      expect((await h.current(device(1))).plan, LicencePlan.trial);
    });

    test('wrong currency or missing amount grants nothing', () async {
      expect(h.pay(c, currency: 'INR').outcome, 'amount_mismatch');
      expect(
        h.deliver('payment.captured', {
          'sessionId': c['sessionId'],
          'currency': 'USD',
        }).outcome,
        'amount_mismatch',
      );
      expect(h.store.device(device(1))!.paidUntil, isNull);
    });

    test('a corrected payment after a mismatch still works', () {
      expect(h.pay(c, amount: 0.01).outcome, 'amount_mismatch');
      expect(h.pay(c).outcome, 'fulfilled_day');
    });

    test('unknown session grants nothing, but is acknowledged', () {
      final r = h.deliver('payment.captured', {
        'sessionId': 'cs_unknown',
        'amount': 0.2,
        'currency': 'USD',
      });
      expect((r.status, r.outcome), (200, 'unknown_session'));
    });

    test('orderRef in metadata finds the order when sessionId differs', () {
      final r = h.deliver('payment.captured', {
        'sessionId': 'cs_something_else',
        'amount': c['amount'],
        'currency': 'USD',
        'metadata': {'orderRef': c['orderRef']},
      });
      expect(r.outcome, 'fulfilled_day');
    });

    test('unhandled events are logged and acknowledged', () {
      final r = h.deliver('identity.user.revoked', {'userId': 'u'});
      expect((r.status, r.outcome), (200, 'unhandled'));
    });

    test('invalid JSON with a valid signature is 400', () {
      final body = utf8.encode('not json');
      final r = h.service.webhook(
        headers: signedHeaders(body, sentAt: h.clock.now),
        rawBody: body,
      );
      expect(r.status, 400);
    });
  });

  group('entitlement math', () {
    setUp(() => h.register(device(1)));

    test('day passes stack from max(now, paid-until)', () async {
      final a = await h.checkout(device(1), days: 3);
      expect(h.pay(a).outcome, 'fulfilled_day');
      final start = h.clock.now;
      h.clock.advance(const Duration(hours: 10));
      final b = await h.checkout(device(1), days: 2);
      expect(h.pay(b).outcome, 'fulfilled_day');
      final t = await h.current(device(1));
      expect(t.plan, LicencePlan.day);
      expect(t.expiresAt, start.add(const Duration(hours: 24 * 5)));
    });

    test('a day pass bought after expiry starts now', () async {
      final a = await h.checkout(device(1));
      h.pay(a);
      h.clock.advance(const Duration(days: 10));
      final b = await h.checkout(device(1));
      h.pay(b);
      expect(
        (await h.current(device(1))).expiresAt,
        h.clock.now.add(const Duration(hours: 24)),
      );
    });

    test('a day pass bought during the trial runs from now', () async {
      // The trial and paid time are independent; the token shows whichever
      // lasts longer.
      final a = await h.checkout(device(1), days: 2);
      h.pay(a);
      final t = await h.current(device(1));
      expect(t.plan, LicencePlan.day);
      expect(t.expiresAt, h.clock.now.add(const Duration(hours: 48)));
    });

    test('day pass expires automatically', () async {
      h.pay(await h.checkout(device(1)));
      h.clock.advance(const Duration(hours: 25));
      final r = await h.service.entitlement(device(1));
      expect((r['entitlement']! as Map)['status'], 'expired');
      expect((r['entitlement']! as Map)['reason'], 'plan_ended');
      final t = await h.token(r);
      expect(t.plan, LicencePlan.day);
      expect(t.expiresAt.isBefore(h.clock.now), isTrue);
    });

    group('monthly', () {
      late Map<String, Object?> c;
      final periodEnd = DateTime.utc(2026, 11, 6, 12);

      setUp(() async {
        c = await h.checkout(device(1), product: 'monthly');
        expect(h.pay(c).outcome, 'fulfilled_monthly');
        expect(
          h.deliver('subscription.created', {
            'subscriptionId': 'sub_1',
            'planCode': 'idsnap-monthly',
            'amount': 2.5,
            'currentPeriodEnd': periodEnd.toIso8601String(),
            'metadata': {'orderRef': c['orderRef']},
          }).outcome,
          'subscription_created',
        );
      });

      test('token: period end + 3-day grace, renewing', () async {
        final t = await h.current(device(1));
        expect(t.plan, LicencePlan.monthly);
        expect(t.paidUntil, periodEnd);
        expect(t.expiresAt, periodEnd.add(const Duration(days: 3)));
        expect(t.willRenew, isTrue);
      });

      test('renewal extends to the next period', () async {
        h.clock.now = periodEnd.subtract(const Duration(hours: 1));
        final next = DateTime.utc(2026, 12, 6, 12);
        expect(
          h.deliver('subscription.renewed', {
            'subscriptionId': 'sub_1',
            'amount': 2.5,
            'currentPeriodEnd': next.toIso8601String(),
            'transactionId': 'tx_2',
          }).outcome,
          'subscription_renewed',
        );
        expect((await h.current(device(1))).paidUntil, next);
      });

      test('renewal without a date adds one month; never moves back', () async {
        h.deliver('subscription.renewed', {
          'subscriptionId': 'sub_1',
          'amount': 2.5,
        }, id: 'r1');
        expect(
          (await h.current(device(1))).paidUntil,
          DateTime.utc(2026, 12, 6, 12),
        );
        h.deliver('subscription.renewed', {
          'subscriptionId': 'sub_1',
          'currentPeriodEnd': '2026-01-01T00:00:00Z',
        }, id: 'r2');
        expect(
          (await h.current(device(1))).paidUntil,
          DateTime.utc(2026, 12, 6, 12),
        );
      });

      test('renewal with the wrong amount is refused', () {
        expect(
          h.deliver('subscription.renewed', {
            'subscriptionId': 'sub_1',
            'amount': 0.5,
          }).outcome,
          'amount_mismatch',
        );
      });

      test('cancellation keeps access until period end, no grace', () async {
        expect(
          h.deliver('subscription.cancelled_by_customer', {
            'subscriptionId': 'sub_1',
            'planCode': 'idsnap-monthly',
            'cancelReason': 'too expensive',
            'currentPeriodEnd': periodEnd.toIso8601String(),
          }).outcome,
          'subscription_cancelled_by_customer',
        );
        final t = await h.current(device(1));
        expect(t.expiresAt, periodEnd);
        expect(t.willRenew, isFalse);
        h.clock.now = periodEnd;
        final r = await h.service.entitlement(device(1));
        expect((r['entitlement']! as Map)['status'], 'expired');
      });

      test('cancellation cannot extend access', () async {
        h.deliver('subscription.cancelled', {
          'subscriptionId': 'sub_1',
          'currentPeriodEnd': '2030-01-01T00:00:00Z',
        });
        expect((await h.current(device(1))).expiresAt, periodEnd);
      });

      test('PAST_DUE keeps the 3-day grace; EXPIRED ends it', () async {
        h.clock.now = periodEnd.add(const Duration(hours: 1));
        h.deliver('subscription.payment_failed', {
          'subscriptionId': 'sub_1',
          'status': 'PAST_DUE',
        });
        var r = await h.service.entitlement(device(1));
        expect((r['entitlement']! as Map)['status'], 'monthly');
        expect((r['entitlement']! as Map)['subscriptionStatus'], 'PAST_DUE');
        h.clock.now = periodEnd.add(const Duration(days: 2));
        h.deliver('subscription.expired', {
          'subscriptionId': 'sub_1',
          'status': 'EXPIRED',
        });
        r = await h.service.entitlement(device(1));
        expect((r['entitlement']! as Map)['status'], 'expired');
      });

      test('renewal after cancellation resumes renewing', () async {
        h
          ..deliver('subscription.cancelled_by_customer', {
            'subscriptionId': 'sub_1',
          })
          ..deliver('subscription.renewed', {
            'subscriptionId': 'sub_1',
            'amount': 2.5,
          });
        expect((await h.current(device(1))).willRenew, isTrue);
      });

      test('day pass and monthly: the longer one shows', () async {
        final d = await h.checkout(device(1), days: 24);
        h.pay(d);
        expect((await h.current(device(1))).plan, LicencePlan.monthly);
        h.deliver('subscription.cancelled_by_customer', {
          'subscriptionId': 'sub_1',
        });
        h.clock.now = periodEnd.add(const Duration(hours: 1));
        // Monthly ended; day pass (24 days from purchase) has too. Buy more.
        final e = await h.checkout(device(1), days: 2);
        h.pay(e);
        expect((await h.current(device(1))).plan, LicencePlan.day);
      });
    });

    test(
      'subscription.created alone (no payment.captured) needs the amount',
      () async {
        final c = await h.checkout(device(1), product: 'monthly');
        expect(
          h.deliver('subscription.created', {
            'subscriptionId': 'sub_9',
            'metadata': {'orderRef': c['orderRef']},
          }).outcome,
          'amount_mismatch',
        );
        expect(
          h.deliver('subscription.created', {
            'subscriptionId': 'sub_9',
            'amount': 2.5,
            'currency': 'USD',
            'metadata': {'orderRef': c['orderRef']},
          }, id: 'e2').outcome,
          'subscription_created',
        );
        expect((await h.current(device(1))).plan, LicencePlan.monthly);
      },
    );

    test('payment.captured for monthly without a date: +1 month', () async {
      final c = await h.checkout(device(1), product: 'monthly');
      h.pay(c);
      final t = await h.current(device(1));
      expect(t.paidUntil, addMonths(h.clock.now, 1));
    });
  });

  group('helpers', () {
    test('addMonths clamps the day', () {
      expect(
        addMonths(DateTime.utc(2026, 1, 31), 1),
        DateTime.utc(2026, 2, 28),
      );
      expect(
        addMonths(DateTime.utc(2026, 12, 15), 1),
        DateTime.utc(2027, 1, 15),
      );
    });

    test('amount parsing', () {
      expect(parseAmountCents(2.5, AmountUnit.major), 250);
      expect(parseAmountCents('0.10', AmountUnit.major), 10);
      expect(parseAmountCents(250, AmountUnit.minor), 250);
      expect(parseAmountCents(0.001, AmountUnit.major), isNull);
      expect(parseAmountCents(-1, AmountUnit.major), isNull);
      expect(parseAmountCents('abc', AmountUnit.major), isNull);
      expect(parseAmountCents(null, AmountUnit.major), isNull);
      expect(majorUnits(250), 2.5);
      expect(majorUnits(500), 5);
    });

    test('gateway time parsing', () {
      expect(
        parseGatewayTime('2026-11-06T12:00:00Z'),
        DateTime.utc(2026, 11, 6, 12),
      );
      expect(parseGatewayTime(1793966400), DateTime.utc(2026, 11, 6, 12));
      expect(parseGatewayTime(1793966400000), DateTime.utc(2026, 11, 6, 12));
      expect(parseGatewayTime('nope'), isNull);
    });

    test('constant-time compare', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'ab'), isFalse);
      expect(constantTimeEquals('', 'a'), isFalse);
    });

    test('a checkout URL off the gateway domain is never handed out', () {
      final g = OneEightyPayGateway(h.config);
      expect(
        g.isAllowedCustomerUrl(Uri.parse('https://pay.180workspace.com/x')),
        isTrue,
      );
      expect(
        g.isAllowedCustomerUrl(Uri.parse('https://evil.com/180workspace.com')),
        isFalse,
      );
      expect(
        g.isAllowedCustomerUrl(Uri.parse('https://evil180workspace.com/')),
        isFalse,
      );
      expect(
        g.isAllowedCustomerUrl(Uri.parse('http://pay.180workspace.com/')),
        isFalse,
      );
    });
  });
}

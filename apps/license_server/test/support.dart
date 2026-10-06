import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:engine_license/engine_license.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:license_server/license_server.dart';

const webhookSecret = 'whsec_test_secret';

/// Mutable clock.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

Map<String, String> testEnv([Map<String, String> overrides = const {}]) => {
  'ONE_EIGHTY_CLIENT_ID': '180_client_test',
  'ONE_EIGHTY_CLIENT_SECRET': '180_secret_test',
  'ONE_EIGHTY_WEBHOOK_SECRET': webhookSecret,
  'LICENSE_SIGNING_KEY': DevLicenceKeys.privateKey,
  'ALLOW_DEV_KEY': 'true',
  'PUBLIC_BASE_URL': 'https://licence.example.com',
  ...overrides,
};

String device(int n) => hashDeviceId('device-$n');

/// A fake 180 Pay backend for the documented session API. Records requests.
class FakeOneEighty {
  final requests = <http.Request>[];
  int sessionCounter = 0;
  int status = 200;

  late final client = MockClient((request) async {
    requests.add(request);
    if (status != 200) return http.Response('{"success":false}', status);
    if (request.url.path == '/api/v1/checkout/sessions') {
      sessionCounter++;
      final id = 'cs_gw_$sessionCounter';
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode({
          'success': true,
          'sessionId': id,
          'checkoutUrl': 'https://auth.180workspace.com/pay/checkout/$id',
          'amount': body['amount'],
          'currency': body['currency'],
          'status': 'PENDING',
        }),
        200,
      );
    }
    if (request.url.path == '/api/v1/portal/sessions') {
      return http.Response(
        jsonEncode({
          'success': true,
          'portalUrl': 'https://auth.180workspace.com/portal/pts_1',
        }),
        200,
      );
    }
    if (request.url.path == '/api/v1/subscriptions/plans') {
      return http.Response(jsonEncode({'success': true, 'id': 'plan_1'}), 201);
    }
    return http.Response('not found', 404);
  });
}

class Harness {
  Harness._(this.service, this.clock, this.store, this.fake, this.config);

  static Future<Harness> create({
    Map<String, String> env = const {},
    DateTime? start,
  }) async {
    final config = ServerConfig.fromEnv(testEnv(env));
    final clock = TestClock(start ?? DateTime.utc(2026, 10, 6, 12));
    final store = LicenceStore.memory();
    final fake = FakeOneEighty();
    final service = LicenceService(
      config: config,
      store: store,
      gateway: OneEightyPayGateway(config, client: fake.client),
      signer: await LicenceSigner.fromEncodedSeed(config.signingKey),
      now: clock.call,
      random: Random(42),
    );
    return Harness._(service, clock, store, fake, config);
  }

  final LicenceService service;
  final TestClock clock;
  final LicenceStore store;
  final FakeOneEighty fake;
  final ServerConfig config;
  final verifier = LicenceVerifier.fromEncodedKey(DevLicenceKeys.publicKey);

  Future<Map<String, Object?>> register(String did) => service.register(
    deviceId: did,
    platform: 'android',
    appVersion: '1.0.0+1',
  );

  Future<LicencePayload> token(Map<String, Object?> response) =>
      verifier.verify(response['token']! as String);

  Future<LicencePayload> current(String did) async =>
      await token(await service.entitlement(did));

  Future<Map<String, Object?>> checkout(
    String did, {
    String product = 'day',
    int? days = 1,
  }) => service.checkout(
    deviceId: did,
    product: product,
    days: product == 'day' ? days : null,
  );

  /// Delivers a correctly signed webhook.
  WebhookResult deliver(
    String event,
    Map<String, Object?> data, {
    String? secret,
    DateTime? sentAt,
    String? id,
  }) {
    final body = utf8.encode(
      jsonEncode({'id': ?id, 'event': event, 'data': data}),
    );
    return service.webhook(
      headers: signedHeaders(body, secret: secret, sentAt: sentAt ?? clock.now),
      rawBody: body,
    );
  }

  /// `payment.captured` for a checkout response, amount as charged.
  WebhookResult pay(
    Map<String, Object?> checkout, {
    num? amount,
    String? currency,
    Map<String, Object?> extra = const {},
  }) => deliver('payment.captured', {
    'sessionId': checkout['sessionId'],
    'amount': amount ?? checkout['amount'],
    'currency': currency ?? checkout['currency'],
    'customerEmail': 'buyer@example.com',
    'metadata': {'orderRef': checkout['orderRef']},
    ...extra,
  });
}

Map<String, String> signedHeaders(
  List<int> body, {
  required DateTime sentAt,
  String? secret,
}) {
  final ts = '${sentAt.millisecondsSinceEpoch ~/ 1000}';
  final sig = Hmac(
    sha256,
    utf8.encode(secret ?? webhookSecret),
  ).convert([...utf8.encode('$ts.'), ...body]).toString();
  return {
    'X-180-Signature': sig,
    'X-180-Timestamp': ts,
    'content-type': 'application/json',
  };
}

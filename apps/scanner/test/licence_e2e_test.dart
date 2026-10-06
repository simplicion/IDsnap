// End to end: the real licence server (shelf + SQLite, in memory) runs
// in-process on localhost with a fake 180 Pay; the app's real licensing
// stack (HttpLicenceClient → LicenceEngine → contracts port → providers)
// talks to it over HTTP. register → checkout → signed webhook → entitlement
// → the app unlocks.
//
// Only `test` (no `testWidgets`) in this file: the widget binding would
// replace dart:io HTTP with a fake that answers 400.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_scanner/billing.dart';
import 'package:engine_billing/engine_billing.dart' as billing;
import 'package:engine_license/engine_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:license_server/license_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _webhookSecret = 'whsec_e2e';

void main() {
  late HttpServer server;
  late Uri baseUrl;
  late DateTime serverNow;

  setUp(() async {
    serverNow = DateTime.now().toUtc();
    final config = ServerConfig.fromEnv({
      'ONE_EIGHTY_CLIENT_ID': '180_client_e2e',
      'ONE_EIGHTY_CLIENT_SECRET': '180_secret_e2e',
      'ONE_EIGHTY_WEBHOOK_SECRET': _webhookSecret,
      'LICENSE_SIGNING_KEY': DevLicenceKeys.privateKey,
      'ALLOW_DEV_KEY': 'true',
    });
    // Fake 180 Pay: the documented checkout-session API.
    var sessions = 0;
    final fakePay = MockClient((request) async {
      sessions++;
      return http.Response(
        jsonEncode({
          'success': true,
          'sessionId': 'cs_e2e_$sessions',
          'checkoutUrl':
              'https://pay.180workspace.com/checkout/cs_e2e_$sessions',
        }),
        200,
      );
    });
    final service = LicenceService(
      config: config,
      store: LicenceStore.memory(),
      gateway: OneEightyPayGateway(config, client: fakePay),
      signer: await LicenceSigner.fromEncodedSeed(DevLicenceKeys.privateKey),
      now: () => serverNow,
    );
    server = await shelf_io.serve(
      buildHandler(service),
      InternetAddress.loopbackIPv4,
      0,
    );
    baseUrl = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() => server.close(force: true));

  /// What 180 Pay does after the customer pays: a signed webhook.
  Future<int> deliverWebhook(Map<String, Object?> event) async {
    final body = utf8.encode(jsonEncode(event));
    final ts = '${serverNow.millisecondsSinceEpoch ~/ 1000}';
    final sig = Hmac(
      sha256,
      utf8.encode(_webhookSecret),
    ).convert([...utf8.encode('$ts.'), ...body]).toString();
    final r = await http.post(
      baseUrl.replace(path: '/webhooks/180-pay'),
      headers: {
        'content-type': 'application/json',
        'X-180-Signature': sig,
        'X-180-Timestamp': ts,
      },
      body: body,
    );
    return r.statusCode;
  }

  test('register → checkout → webhook → entitlement → unlocked', () async {
    final opened = <Uri>[];
    final storage = billing.MemoryBillingStorage();
    final service = await startBilling(
      mode: MonetizationMode.licence,
      client: billing.HttpLicenceClient(baseUrl: baseUrl),
      storage: storage,
      identity: billing.FixedDeviceIdentity('e2e-phone'),
      now: () => serverNow,
      openUrl: (url) async {
        opened.add(url);
        return true;
      },
      pollSchedule: const [
        Duration(milliseconds: 50),
        Duration(milliseconds: 50),
        Duration(milliseconds: 100),
        Duration(milliseconds: 200),
        Duration(milliseconds: 400),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        // The paid licence build (the default is free with ads, ADR-0013).
        monetizationModeProvider.overrideWithValue(MonetizationMode.licence),
        entitlementServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);

    // First launch: background registration starts the free day.
    await service.refreshLicence();
    container.read(entitlementProvider.notifier).recheck();
    expect(container.read(entitlementProvider), isA<TrialEntitlement>());
    expect(container.read(canUseProvider(ProFeature.scan)), isTrue);

    // The free day passes (server clock); the app locks Pro features.
    serverNow = serverNow.add(const Duration(hours: 25));
    await service.refreshLicence();
    container.read(entitlementProvider.notifier).recheck();
    final pricing = await service.pricing();
    expect(pricing.fromServer, isTrue);
    expect(pricing.dayPriceCents, 10);

    // Buy a 3-day pass; the "customer" pays while the app polls.
    final purchase = service.purchase(const ProPurchase.dayPass(3));
    while (opened.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(opened.single.host, 'pay.180workspace.com');
    expect(
      await deliverWebhook({
        'event': 'payment.captured',
        'data': {
          'sessionId': opened.single.pathSegments.last,
          'amount': 0.30,
          'currency': 'USD',
        },
      }),
      200,
    );
    final outcome = await purchase;
    expect(outcome.kind, PurchaseOutcomeKind.purchased);
    container.read(entitlementProvider.notifier).recheck();
    final state = container.read(entitlementProvider);
    expect(state, isA<DayPassEntitlement>());
    expect(container.read(canUseProvider(ProFeature.scan)), isTrue);

    // The licence is stored: a cold start works with the server gone.
    await server.close(force: true);
    final offline = await startBilling(
      mode: MonetizationMode.licence,
      client: billing.HttpLicenceClient(baseUrl: baseUrl, retries: 0),
      storage: storage,
      identity: billing.FixedDeviceIdentity('e2e-phone'),
      now: () => serverNow,
    );
    expect(offline.current, isA<DayPassEntitlement>());
  });

  test('an underpaying webhook never unlocks the app', () async {
    final opened = <Uri>[];
    final service = await startBilling(
      mode: MonetizationMode.licence,
      client: billing.HttpLicenceClient(baseUrl: baseUrl),
      storage: billing.MemoryBillingStorage(),
      identity: billing.FixedDeviceIdentity('e2e-cheat'),
      now: () => serverNow,
      openUrl: (url) async {
        opened.add(url);
        return true;
      },
      pollSchedule: const [
        Duration(milliseconds: 50),
        Duration(milliseconds: 100),
      ],
    );
    await service.refreshLicence();
    serverNow = serverNow.add(const Duration(hours: 25));
    await service.refreshLicence();
    final purchase = service.purchase(const ProPurchase.dayPass(24));
    while (opened.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await deliverWebhook({
      'event': 'payment.captured',
      'data': {
        'sessionId': opened.single.pathSegments.last,
        'amount': 0.01,
        'currency': 'USD',
      },
    });
    expect((await purchase).kind, PurchaseOutcomeKind.pending);
    expect(service.current.isEntitled, isFalse);
  });
}

// Everything this server knows or assumes about 180 Pay lives in this file.
//
// ╔══════════════════════════════════════════════════════════════════════════╗
// ║ VERIFY WITH 180 PAY                                                      ║
// ║                                                                          ║
// ║ Sources read on 2026-10-06 (public, no account):                         ║
// ║  [SDK]  https://auth.180workspace.com/sdk/v1/180-core-sdk.js             ║
// ║  [DOCS] https://docs.180workspace.com/docs/products/180-core/180-pay/    ║
// ║         checkout-integration, recurring-subscriptions,                   ║
// ║         webhook-integration, customer-portal                             ║
// ║  [DEV]  https://developers.180workspace.com/pay (code samples)           ║
// ║                                                                          ║
// ║ Nothing here was exercised against the live service. Each assumption     ║
// ║ below is marked `ASSUMPTION An` where the code relies on it.             ║
// ║                                                                          ║
// ║ DOCUMENTED (implemented as written)                                      ║
// ║  D1 Webhook signature: headers X-180-Signature (hex) and                 ║
// ║     X-180-Timestamp (epoch seconds); expected =                          ║
// ║     hex(HMAC_SHA256(secret, `${timestamp}.${rawBody}`)); reject when     ║
// ║     |now − timestamp| > 300 s; constant-time compare. [DOCS]             ║
// ║  D2 Hosted checkout URL: {PAY_URL}/checkout/{sessionId}?amount=…&        ║
// ║     currency=…&title=…&plan=…&description=…&appName=…&app=pay&           ║
// ║     ux_mode=full_page&env=production. [SDK]                              ║
// ║  D3 Create plan: POST {CORE}/api/v1/subscriptions/plans, Bearer          ║
// ║     client secret. [DOCS]                                                ║
// ║  D4 Create checkout session: POST {CORE}/api/v1/checkout/sessions →      ║
// ║     {success, sessionId, checkoutUrl, amount, currency, status}. [DOCS]  ║
// ║  D5 Portal session: POST {CORE}/api/v1/portal/sessions → {portalUrl}.    ║
// ║     [DOCS]                                                               ║
// ║                                                                          ║
// ║ ASSUMPTIONS (confirm each with 180 Pay before going live)                ║
// ║  A1 Session API auth. [DOCS] puts clientId + clientSecret in the JSON    ║
// ║     body; [DEV] sends `Authorization: Bearer <client_secret>` plus       ║
// ║     clientId in the body. We send both forms.                            ║
// ║  A2 Session API response field. [DOCS] says `sessionId`, the [DEV]       ║
// ║     sample reads `id`. We accept either.                                 ║
// ║  A3 `amount` is in MAJOR units (2.50 = $2.50) in API requests, the       ║
// ║     hosted URL and webhook payloads (ONE_EIGHTY_WEBHOOK_AMOUNT_UNIT      ║
// ║     switches the webhook side to minor units).                           ║
// ║  A4 `metadata` sent when creating a session is echoed back unchanged     ║
// ║     in `payment.captured` and `subscription.created` (`data.metadata`).  ║
// ║     We use `metadata.orderRef` only as a fallback to find the order;     ║
// ║     the primary key is `data.sessionId`.                                 ║
// ║  A5 `subscription.*` events may not carry `sessionId` (the catalogue     ║
// ║     lists subscriptionId, planCode, amount, currentPeriodEnd,            ║
// ║     metadata). A subscription is tied to a device through its order,     ║
// ║     found by sessionId or metadata.orderRef.                             ║
// ║  A6 Dates (`currentPeriodEnd`, `nextBillingDate`) are ISO-8601 strings   ║
// ║     or epoch seconds/milliseconds. Both are parsed.                      ║
// ║  A7 A subscription's lifecycle status (TRIALING, ACTIVE, PAST_DUE,       ║
// ║     CANCELLED, EXPIRED) may arrive as `data.status` on any               ║
// ║     `subscription.*` event. No dedicated "past due" event is             ║
// ║     documented, so the server also applies the 3-day grace on its own.   ║
// ║  A8 A webhook event has no documented unique id. We de-duplicate on      ║
// ║     `id`/`eventId` when present, else on the SHA-256 of the raw body.    ║
// ║  A9 In `hosted_url` mode (no API call) it is UNKNOWN how 180 Pay binds   ║
// ║     a self-generated session id to this merchant: the SDK URL carries    ║
// ║     no client id. Treat that mode as experimental.                       ║
// ║  A10 Minimum charge and fees: UNKNOWN whether US$0.10 can be charged     ║
// ║     at all. Docs state a 1.5% platform fee. We assume `data.amount` is   ║
// ║     the gross amount the customer paid.                                  ║
// ║  A11 `returnUrl` / `cancelUrl` are honoured for redirect checkouts, and  ║
// ║     `mode: "subscription"` + `planCode` starts the recurring plan.       ║
// ║  A12 Portal sessions accept `externalCustomerId` alone; we also send     ║
// ║     the customer e-mail when a webhook gave us one.                      ║
// ║  A13 Refunds / chargebacks: no event is documented, so none is handled.  ║
// ╚══════════════════════════════════════════════════════════════════════════╝

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:license_server/src/config.dart';

// ── Gateway-neutral types ────────────────────────────────────────────────────

/// An order this server wants paid.
class CheckoutRequest {
  const CheckoutRequest({
    required this.orderRef,
    required this.deviceHash,
    required this.amountCents,
    required this.currency,
    required this.title,
    required this.description,
    this.planCode,
  });

  /// Our own order id (`cs_` + 24 random characters).
  final String orderRef;
  final String deviceHash;
  final int amountCents;
  final String currency;
  final String title;
  final String description;

  /// Set for the monthly subscription, null for one-time day passes.
  final String? planCode;
}

class CheckoutSession {
  const CheckoutSession({required this.sessionId, required this.checkoutUrl});

  /// The id 180 Pay will report in `data.sessionId`. Equal to the order
  /// ref in `hosted_url` mode.
  final String sessionId;
  final Uri checkoutUrl;
}

/// The gateway couldn't be reached or answered unusably. Never carries
/// secrets or response bodies.
class GatewayException implements Exception {
  const GatewayException(this.message);

  final String message;

  @override
  String toString() => 'GatewayException($message)';
}

enum WebhookVerdict { ok, missingHeaders, staleTimestamp, badSignature }

enum GatewayEventKind {
  /// `payment.captured` / `payment.succeeded`.
  paymentCaptured,
  subscriptionCreated,
  subscriptionRenewed,

  /// `subscription.cancelled_by_customer`: stops renewing, access stays
  /// until the period ends.
  subscriptionCancelledByCustomer,

  /// `subscription.cancelled`: ended by the gateway (dunning) or merchant.
  subscriptionCancelled,

  /// Any other `subscription.*` event (ASSUMPTION A7): only `status` is
  /// applied.
  subscriptionOther,

  /// Everything else: logged, acknowledged, ignored.
  unhandled,
}

/// Subscription statuses per the 180 Pay docs.
enum SubscriptionStatus {
  trialing('TRIALING'),
  active('ACTIVE'),
  pastDue('PAST_DUE'),
  cancelled('CANCELLED'),
  expired('EXPIRED');

  const SubscriptionStatus(this.wire);
  final String wire;

  static SubscriptionStatus? parse(Object? value) {
    if (value is! String) return null;
    final upper = value.trim().toUpperCase();
    for (final s in values) {
      if (s.wire == upper) return s;
    }
    return upper == 'CANCELED' ? cancelled : null;
  }
}

/// A webhook event, normalised. Only produced from a body whose signature
/// was verified.
class GatewayEvent {
  const GatewayEvent({
    required this.kind,
    required this.type,
    required this.dedupeKey,
    this.sessionId,
    this.orderRef,
    this.amountCents,
    this.currency,
    this.customerEmail,
    this.subscriptionId,
    this.planCode,
    this.periodEnd,
    this.status,
    this.transactionId,
  });

  final GatewayEventKind kind;

  /// The raw event name, for logs.
  final String type;

  /// Stable per event (ASSUMPTION A8).
  final String dedupeKey;
  final String? sessionId;

  /// `metadata.orderRef` (ASSUMPTION A4).
  final String? orderRef;

  /// Null when absent or not a whole number of cents.
  final int? amountCents;
  final String? currency;
  final String? customerEmail;
  final String? subscriptionId;
  final String? planCode;

  /// `currentPeriodEnd`, else `nextBillingDate` (ASSUMPTION A6).
  final DateTime? periodEnd;
  final SubscriptionStatus? status;
  final String? transactionId;
}

class PlanDefinition {
  const PlanDefinition({
    required this.planCode,
    required this.name,
    required this.description,
    required this.amountCents,
    required this.currency,
    this.interval = 'MONTHLY',
    this.intervalCount = 1,
    this.trialDays = 0,
    this.metadata = const {},
  });

  final String planCode;
  final String name;
  final String description;
  final int amountCents;
  final String currency;
  final String interval;
  final int intervalCount;
  final int trialDays;
  final Map<String, Object?> metadata;
}

class PlanResult {
  const PlanResult({required this.ok, required this.statusCode, this.body});

  final bool ok;
  final int statusCode;

  /// The gateway's JSON answer, for the operator running the script.
  final Object? body;
}

/// The ONLY door to the payment provider. Swap the implementation to
/// change provider; nothing else in the server knows 180 Pay exists.
abstract interface class PayGateway {
  /// Starts a checkout for [request] and says where to send the customer.
  Future<CheckoutSession> createCheckout(CheckoutRequest request);

  /// The hosted checkout page for an existing [sessionId].
  Uri buildCheckoutUrl({
    required String sessionId,
    required int amountCents,
    required String currency,
    required String title,
    String? description,
    String? planCode,
  });

  /// Authenticates a webhook from its headers and RAW body bytes.
  WebhookVerdict verifyWebhook({
    required Map<String, String> headers,
    required List<int> rawBody,
    required DateTime now,
  });

  /// Parses a verified body. Null if it isn't an event object.
  GatewayEvent? parseEvent(List<int> rawBody);

  /// Creates (or tries to create) a recurring plan.
  Future<PlanResult> createPlan(PlanDefinition plan);

  /// A one-time link to the customer's billing portal, or null when the
  /// gateway can't provide one.
  Future<Uri?> createPortalSession({
    required String externalCustomerId,
    String? customerEmail,
    Uri? returnUrl,
  });
}

// ── 180 Pay ──────────────────────────────────────────────────────────────────

/// How far a webhook's timestamp may be from this server's clock (D1).
const webhookTolerance = Duration(seconds: 300);

class OneEightyPayGateway implements PayGateway {
  OneEightyPayGateway(
    this.config, {
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final ServerConfig config;
  final http.Client _client;
  final Duration timeout;

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    // D3, and one of the two documented forms for sessions (ASSUMPTION A1).
    'authorization': 'Bearer ${config.clientSecret}',
    'accept': 'application/json',
  };

  Uri _core(String path) => config.coreUrl.replace(
    path: '${config.coreUrl.path.replaceAll(RegExp(r'/+$'), '')}$path',
  );

  @override
  Future<CheckoutSession> createCheckout(CheckoutRequest request) async {
    if (config.checkoutMode == CheckoutMode.hostedUrl) {
      // ASSUMPTION A9: the session id is ours and nothing is registered
      // with 180 Pay first.
      return CheckoutSession(
        sessionId: request.orderRef,
        checkoutUrl: buildCheckoutUrl(
          sessionId: request.orderRef,
          amountCents: request.amountCents,
          currency: request.currency,
          title: request.title,
          description: request.description,
          planCode: request.planCode,
        ),
      );
    }

    // D4, with ASSUMPTIONS A1, A3, A4 and A11.
    final base = config.publicBaseUrl;
    final body = <String, Object?>{
      'clientId': config.clientId,
      'clientSecret': config.clientSecret,
      'amount': majorUnits(request.amountCents),
      'currency': request.currency,
      'title': request.title,
      'description': request.description,
      'mode': request.planCode == null ? 'payment' : 'subscription',
      'planCode': ?request.planCode,
      if (base != null) ...{
        'returnUrl': _join(base, '/v1/checkout/return', {'status': 'success'}),
        'cancelUrl': _join(base, '/v1/checkout/return', {
          'status': 'cancelled',
        }),
      },
      'metadata': {
        'orderRef': request.orderRef,
        // Lets the customer portal find this customer (ASSUMPTION A12).
        'externalCustomerId': request.deviceHash,
      },
    };
    final json = await _postJson('/api/v1/checkout/sessions', body);
    // ASSUMPTION A2.
    final id = json['sessionId'] ?? json['id'];
    if (id is! String || !_safeId.hasMatch(id)) {
      throw const GatewayException('checkout session: no usable session id');
    }
    final rawUrl = json['checkoutUrl'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    return CheckoutSession(
      sessionId: id,
      checkoutUrl: url != null && isAllowedCustomerUrl(url)
          ? url
          : buildCheckoutUrl(
              sessionId: id,
              amountCents: request.amountCents,
              currency: request.currency,
              title: request.title,
              description: request.description,
              planCode: request.planCode,
            ),
    );
  }

  @override
  Uri buildCheckoutUrl({
    required String sessionId,
    required int amountCents,
    required String currency,
    required String title,
    String? description,
    String? planCode,
  }) {
    // D2: the same query the public SDK builds.
    final basePath = config.payUrl.path.replaceAll(RegExp(r'/+$'), '');
    return config.payUrl.replace(
      path: '$basePath/checkout/${Uri.encodeComponent(sessionId)}',
      queryParameters: {
        'amount': majorUnits(amountCents).toString(),
        'currency': currency,
        'title': title,
        'plan': ?planCode,
        if (description != null && description.isNotEmpty)
          'description': description,
        'appName': config.appName,
        'app': 'pay',
        'ux_mode': 'full_page',
        'env': 'production',
      },
    );
  }

  @override
  WebhookVerdict verifyWebhook({
    required Map<String, String> headers,
    required List<int> rawBody,
    required DateTime now,
  }) {
    // D1. Header names are case-insensitive on the wire.
    String? header(String name) {
      for (final e in headers.entries) {
        if (e.key.toLowerCase() == name) return e.value.trim();
      }
      return null;
    }

    final signature = header('x-180-signature');
    final timestamp = header('x-180-timestamp');
    if (signature == null ||
        signature.isEmpty ||
        timestamp == null ||
        timestamp.isEmpty) {
      return WebhookVerdict.missingHeaders;
    }
    final seconds = RegExp(r'^[0-9]{1,12}$').hasMatch(timestamp)
        ? int.parse(timestamp)
        : null;
    if (seconds == null) return WebhookVerdict.staleTimestamp;
    final drift = (now.millisecondsSinceEpoch ~/ 1000 - seconds).abs();
    if (drift > webhookTolerance.inSeconds) {
      return WebhookVerdict.staleTimestamp;
    }

    // HMAC over the bytes exactly as received: `${timestamp}.` + raw body.
    final mac = Hmac(sha256, utf8.encode(config.webhookSecret));
    final expected = mac.convert([
      ...utf8.encode('$timestamp.'),
      ...rawBody,
    ]).toString();
    return constantTimeEquals(expected, signature.toLowerCase())
        ? WebhookVerdict.ok
        : WebhookVerdict.badSignature;
  }

  @override
  GatewayEvent? parseEvent(List<int> rawBody) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(rawBody));
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final type = json['event'];
    if (type is! String || type.isEmpty || type.length > 100) return null;
    final rawData = json['data'];
    final data = rawData is Map<String, Object?>
        ? rawData
        : const <String, Object?>{};
    final rawMeta = data['metadata'];
    final meta = rawMeta is Map<String, Object?>
        ? rawMeta
        : const <String, Object?>{};

    final kind = switch (type) {
      'payment.captured' ||
      'payment.succeeded' => GatewayEventKind.paymentCaptured,
      'subscription.created' => GatewayEventKind.subscriptionCreated,
      'subscription.renewed' => GatewayEventKind.subscriptionRenewed,
      'subscription.cancelled_by_customer' =>
        GatewayEventKind.subscriptionCancelledByCustomer,
      'subscription.cancelled' ||
      'subscription.canceled' => GatewayEventKind.subscriptionCancelled,
      _ when type.startsWith('subscription.') =>
        GatewayEventKind.subscriptionOther,
      _ => GatewayEventKind.unhandled,
    };

    // ASSUMPTION A8.
    final explicitId = _text(json['id']) ?? _text(json['eventId']);
    final dedupeKey = explicitId != null
        ? 'id:$explicitId'
        : 'sha256:${sha256.convert(rawBody)}';

    return GatewayEvent(
      kind: kind,
      type: type,
      dedupeKey: dedupeKey,
      sessionId: _text(data['sessionId']),
      orderRef: _text(meta['orderRef']),
      amountCents: parseAmountCents(data['amount'], config.webhookAmountUnit),
      currency: _text(data['currency'])?.toUpperCase(),
      customerEmail: _text(data['customerEmail'], max: 254),
      subscriptionId: _text(data['subscriptionId']),
      planCode: _text(data['planCode']),
      periodEnd:
          parseGatewayTime(data['currentPeriodEnd']) ??
          parseGatewayTime(data['nextBillingDate']),
      status: SubscriptionStatus.parse(data['status']),
      transactionId: _text(data['transactionId']),
    );
  }

  @override
  Future<PlanResult> createPlan(PlanDefinition plan) async {
    // D3.
    final http.Response response;
    try {
      response = await _client
          .post(
            _core('/api/v1/subscriptions/plans'),
            headers: _headers,
            body: jsonEncode({
              'planCode': plan.planCode,
              'name': plan.name,
              'description': plan.description,
              'amount': majorUnits(plan.amountCents),
              'currency': plan.currency,
              'interval': plan.interval,
              'intervalCount': plan.intervalCount,
              'trialDays': plan.trialDays,
              'metadata': plan.metadata,
            }),
          )
          .timeout(timeout);
    } on Object {
      throw const GatewayException('create plan: gateway unreachable');
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    return PlanResult(
      ok: response.statusCode >= 200 && response.statusCode < 300,
      statusCode: response.statusCode,
      body: body,
    );
  }

  @override
  Future<Uri?> createPortalSession({
    required String externalCustomerId,
    String? customerEmail,
    Uri? returnUrl,
  }) async {
    // D5 with ASSUMPTION A12.
    final Map<String, Object?> json;
    try {
      json = await _postJson('/api/v1/portal/sessions', {
        'externalCustomerId': externalCustomerId,
        'customerEmail': ?customerEmail,
        if (returnUrl != null) 'returnUrl': returnUrl.toString(),
      });
    } on GatewayException {
      return null;
    }
    final raw = json['portalUrl'];
    final url = raw is String ? Uri.tryParse(raw) : null;
    return url != null && isAllowedCustomerUrl(url) ? url : null;
  }

  /// Only https URLs on the gateway's own domain are ever handed to the
  /// app, whatever the API answered.
  bool isAllowedCustomerUrl(Uri url) {
    final host = url.host.toLowerCase();
    final suffix = config.checkoutHostSuffix;
    return url.scheme == 'https' &&
        (host == suffix ||
            host.endsWith('.$suffix') ||
            host == config.payUrl.host.toLowerCase());
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(_core(path), headers: _headers, body: jsonEncode(body))
          .timeout(timeout);
    } on Object {
      throw GatewayException('$path: gateway unreachable');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GatewayException('$path: HTTP ${response.statusCode}');
    }
    Object? json;
    try {
      json = jsonDecode(response.body);
    } on FormatException {
      json = null;
    }
    if (json is! Map<String, Object?> || json['success'] == false) {
      throw GatewayException('$path: unexpected response');
    }
    return json;
  }

  static String _join(Uri base, String path, Map<String, String> query) => base
      .replace(
        path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path',
        queryParameters: query,
      )
      .toString();
}

final _safeId = RegExp(r'^[A-Za-z0-9_.:-]{1,128}$');

String? _text(Object? value, {int max = 128}) =>
    value is String && value.isNotEmpty && value.length <= max ? value : null;

/// 250 → 2.5 (ASSUMPTION A3). Whole amounts stay integers (499, not 499.0).
num majorUnits(int cents) => cents % 100 == 0 ? cents ~/ 100 : cents / 100;

/// A gateway amount as cents, or null if absent, negative, not finite or
/// not a whole number of cents.
int? parseAmountCents(Object? value, AmountUnit unit) {
  final n = switch (value) {
    final num v => v,
    final String s => num.tryParse(s.trim()),
    _ => null,
  };
  if (n == null || n.isNaN || n.isInfinite || n < 0 || n > 1e9) return null;
  final cents = unit == AmountUnit.major ? n * 100 : n;
  final rounded = cents.round();
  return (cents - rounded).abs() < 1e-6 ? rounded : null;
}

/// ISO-8601 or epoch seconds/milliseconds (ASSUMPTION A6), as UTC.
DateTime? parseGatewayTime(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    final asNumber = num.tryParse(trimmed);
    if (asNumber != null) return parseGatewayTime(asNumber);
    return DateTime.tryParse(trimmed)?.toUtc();
  }
  if (value is num && value.isFinite && value > 0) {
    // Seconds until the year 2286 are below 1e10; anything larger is ms.
    final ms = value < 1e10 ? value * 1000 : value;
    if (ms > 8.64e15) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  }
  return null;
}

/// Compares without leaking where the first difference is.
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ (i < y.length ? y[i] : 0);
  }
  return diff == 0;
}

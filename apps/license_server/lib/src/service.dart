import 'dart:math';

import 'package:engine_license/engine_license.dart';
import 'package:license_server/src/config.dart';
import 'package:license_server/src/entitlement.dart';
import 'package:license_server/src/gateway.dart';
import 'package:license_server/src/store.dart';

/// A request this server refuses, with an HTTP status and a stable code.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, {this.retryAfter});

  final int status;
  final String code;
  final String message;
  final Duration? retryAfter;

  @override
  String toString() => 'ApiException($status, $code)';
}

class WebhookResult {
  const WebhookResult(this.status, this.outcome);

  /// HTTP status to answer the gateway with.
  final int status;

  /// What happened, for logs and tests: `fulfilled_day`, `duplicate`,
  /// `amount_mismatch`, `unknown_session`, `unhandled`, ...
  final String outcome;
}

/// One line of structured log. Never receives secrets, tokens, raw device
/// ids, e-mail addresses or IP addresses.
typedef LogSink = void Function(String event, Map<String, Object?> fields);

final _platforms = {'android', 'ios'};
final _appVersion = RegExp(r'^[0-9A-Za-z.+_-]{1,32}$');
const _idAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// The licence rules, independent of HTTP: registration and the free day,
/// server-side pricing, checkout orders, webhook fulfilment and signed
/// tokens.
class LicenceService {
  LicenceService({
    required this.config,
    required this.store,
    required this.gateway,
    required this.signer,
    DateTime Function()? now,
    Random? random,
    LogSink? log,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure(),
       _log = log ?? ((_, _) {});

  final ServerConfig config;
  final LicenceStore store;
  final PayGateway gateway;
  final LicenceSigner signer;
  final DateTime Function() _now;
  final Random _random;
  final LogSink _log;

  DateTime get _utcNow {
    final now = _now().toUtc();
    // Whole seconds: everything stored and signed is in seconds.
    return DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    );
  }

  /// This server's clock, in epoch seconds (what `serverTime` reports).
  int get serverTime => _utcNow.millisecondsSinceEpoch ~/ 1000;

  // ── Devices and licences ───────────────────────────────────────────────────

  /// Creates the device on first sight and starts its free day. Always
  /// idempotent: a known device keeps its original trial window, so
  /// reinstalling never gives a new one.
  ///
  /// [allowNewDevice] is asked only when the device is new (rate limiting
  /// of trial creation).
  Future<Map<String, Object?>> register({
    required Object? deviceId,
    required Object? platform,
    required Object? appVersion,
    bool Function()? allowNewDevice,
  }) async {
    final did = _deviceId(deviceId);
    if (platform is! String || !_platforms.contains(platform)) {
      throw const ApiException(
        400,
        'invalid_platform',
        'platform must be "android" or "ios".',
      );
    }
    if (appVersion is! String || !_appVersion.hasMatch(appVersion)) {
      throw const ApiException(
        400,
        'invalid_app_version',
        'appVersion must be 1-32 characters: letters, digits and . + _ -',
      );
    }
    final now = _utcNow;
    if (store.device(did) == null &&
        allowNewDevice != null &&
        !allowNewDevice()) {
      throw const ApiException(
        429,
        'rate_limited',
        'Too many new devices from this network. Try again later.',
        retryAfter: Duration(minutes: 10),
      );
    }
    // INSERT OR IGNORE: for a known device the trial window is untouched.
    final created = store.insertDeviceIfAbsent(
      did: did,
      platform: platform,
      appVersion: appVersion,
      now: now,
      trialEndsAt: now.add(config.trial),
    );
    if (created) _log('device_registered', {'did': _short(did)});
    return await _licence(did, now);
  }

  /// The device's current signed token. An ended licence is still a signed
  /// token (of the plan that ended, `exp` in the past), so the app can
  /// trust "expired" as much as "valid".
  Future<Map<String, Object?>> entitlement(Object? deviceId) async {
    final did = _deviceId(deviceId);
    if (store.device(did) == null) throw _unknownDevice;
    return await _licence(did, _utcNow);
  }

  /// Public pricing and limits, so the app never hardcodes them.
  Map<String, Object?> pricing() => {
    'trialHours': config.trialHours,
    'dayPriceCents': config.dayPriceCents,
    'monthPriceCents': config.monthPriceCents,
    'currency': config.currency,
    'minDays': config.minDays,
    'maxDays': config.maxDays,
    'graceDays': config.graceDays,
  };

  Future<Map<String, Object?>> _licence(String did, DateTime now) async {
    final ent = computeEntitlement(
      device: store.device(did)!,
      subscriptions: store.subscriptionsOf(did),
      now: now,
      grace: config.grace,
    );
    final token = await signer.sign(
      LicencePayload(
        deviceHash: did,
        plan: ent.plan,
        issuedAt: now,
        expiresAt: ent.expiresAt,
        tokenId: _randomId(16),
        grace: ent.grace,
        willRenew: ent.willRenew,
      ),
    );
    return {
      'token': token,
      'serverTime': now.millisecondsSinceEpoch ~/ 1000,
      'entitlement': ent.toJson(),
      'pricing': pricing(),
    };
  }

  // ── Checkout ───────────────────────────────────────────────────────────────

  /// Validates the request, computes the amount HERE (the client never
  /// sends a price), stores a pending order and asks the gateway where to
  /// send the customer.
  Future<Map<String, Object?>> checkout({
    required Object? deviceId,
    required Object? product,
    required Object? days,
  }) async {
    final did = _deviceId(deviceId);
    final kind = switch (product) {
      'day' => OrderProduct.day,
      'monthly' => OrderProduct.monthly,
      _ => throw const ApiException(
        400,
        'invalid_product',
        'product must be "day" or "monthly".',
      ),
    };
    int? dayCount;
    if (kind == OrderProduct.day) {
      if (days is! int || days < config.minDays || days > config.maxDays) {
        throw ApiException(
          400,
          'invalid_days',
          'days must be a whole number from ${config.minDays} to '
              '${config.maxDays}.',
        );
      }
      dayCount = days;
    } else if (days != null) {
      throw const ApiException(
        400,
        'invalid_days',
        'days is only for the day pass.',
      );
    }
    final device = store.device(did);
    if (device == null) throw _unknownDevice;

    final now = _utcNow;
    if (kind == OrderProduct.monthly) {
      final renewing = store
          .subscriptionsOf(did)
          .any(
            (s) =>
                !s.cancelAtPeriodEnd &&
                s.status != SubscriptionStatus.cancelled &&
                s.status != SubscriptionStatus.expired &&
                now.isBefore(s.periodEnd.add(config.grace)),
          );
      if (renewing) {
        throw const ApiException(
          409,
          'already_subscribed',
          'This device already has an active monthly plan.',
        );
      }
    }
    if (store.pendingOrdersSince(did, now.subtract(const Duration(hours: 1))) >=
        20) {
      throw const ApiException(
        429,
        'rate_limited',
        'Too many unfinished checkouts. Try again later.',
        retryAfter: Duration(minutes: 30),
      );
    }

    final amountCents = kind == OrderProduct.day
        ? dayCount! * config.dayPriceCents
        : config.monthPriceCents;
    final orderRef = 'cs_${_randomId(24)}';
    store.insertOrder(
      OrderRow(
        orderRef: orderRef,
        deviceHash: did,
        product: kind,
        days: dayCount,
        amountCents: amountCents,
        currency: config.currency,
        status: OrderStatus.pending,
        createdAt: now,
      ),
    );

    final CheckoutSession session;
    try {
      session = await gateway.createCheckout(
        CheckoutRequest(
          orderRef: orderRef,
          deviceHash: did,
          amountCents: amountCents,
          currency: config.currency,
          title: kind == OrderProduct.day
              ? '${config.appName} day pass '
                    '($dayCount ${dayCount == 1 ? 'day' : 'days'})'
              : '${config.appName} monthly',
          description: kind == OrderProduct.day
              ? 'All ${config.appName} features for '
                    '$dayCount × 24 hours on one device.'
              : 'All ${config.appName} features on one device. '
                    'Renews monthly until cancelled.',
          planCode: kind == OrderProduct.monthly
              ? config.monthlyPlanCode
              : null,
        ),
      );
    } on GatewayException catch (e) {
      store.setOrderStatus(orderRef, OrderStatus.failed);
      _log('checkout_gateway_error', {'reason': e.message});
      throw const ApiException(
        502,
        'gateway_unavailable',
        "The payment service couldn't be reached. Try again in a moment.",
      );
    }
    if (session.sessionId != orderRef) {
      try {
        store.setGatewaySession(orderRef, session.sessionId);
      } on Object {
        // A session id we already hold: refuse rather than cross orders.
        store.setOrderStatus(orderRef, OrderStatus.failed);
        throw const ApiException(
          502,
          'gateway_unavailable',
          'The payment service returned an unusable session.',
        );
      }
    }
    _log('checkout_created', {
      'did': _short(did),
      'product': kind.name,
      'days': dayCount,
      'amountCents': amountCents,
    });
    return {
      'sessionId': session.sessionId,
      'orderRef': orderRef,
      'checkoutUrl': session.checkoutUrl.toString(),
      'amount': majorUnits(amountCents),
      'amountCents': amountCents,
      'currency': config.currency,
    };
  }

  /// A one-time link to 180 Pay's customer portal for the device's
  /// subscription (cancel, payment method, invoices).
  Future<Map<String, Object?>> portal(Object? deviceId) async {
    final did = _deviceId(deviceId);
    if (store.device(did) == null) throw _unknownDevice;
    final subs = store.subscriptionsOf(did)
      ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));
    if (subs.isEmpty) {
      throw const ApiException(
        404,
        'no_subscription',
        'This device has no monthly plan.',
      );
    }
    final base = config.publicBaseUrl;
    final url = await gateway.createPortalSession(
      externalCustomerId: did,
      customerEmail: subs.first.customerEmail,
      returnUrl: base?.replace(
        path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/v1/checkout/return',
        queryParameters: {'status': 'portal'},
      ),
    );
    if (url == null) {
      throw const ApiException(
        502,
        'portal_unavailable',
        "The billing portal couldn't be opened right now.",
      );
    }
    return {'portalUrl': url.toString()};
  }

  // ── Webhooks ───────────────────────────────────────────────────────────────

  /// Authenticates and applies one 180 Pay webhook. The ONLY place access
  /// is ever granted for money.
  WebhookResult webhook({
    required Map<String, String> headers,
    required List<int> rawBody,
  }) {
    final now = _utcNow;
    switch (gateway.verifyWebhook(
      headers: headers,
      rawBody: rawBody,
      now: now,
    )) {
      case WebhookVerdict.ok:
        break;
      case WebhookVerdict.missingHeaders:
        _log('webhook_rejected', {'reason': 'missing_headers'});
        return const WebhookResult(400, 'missing_headers');
      case WebhookVerdict.staleTimestamp:
        _log('webhook_rejected', {'reason': 'stale_timestamp'});
        return const WebhookResult(401, 'stale_timestamp');
      case WebhookVerdict.badSignature:
        _log('webhook_rejected', {'reason': 'bad_signature'});
        return const WebhookResult(401, 'bad_signature');
    }
    final event = gateway.parseEvent(rawBody);
    if (event == null) {
      _log('webhook_rejected', {'reason': 'invalid_body'});
      return const WebhookResult(400, 'invalid_body');
    }
    try {
      final outcome = store.transaction(() {
        // Replays and gateway retries: an event is applied at most once.
        if (store.eventSeen(event.dedupeKey)) return 'duplicate';
        final result = _apply(event, now);
        store.recordEvent(event.dedupeKey, event.type, result, now);
        return result;
      });
      _log('webhook', {'type': event.type, 'outcome': outcome});
      // Always 2xx for an authentic event, handled or not, so the gateway
      // doesn't retry something we will never act on.
      return WebhookResult(200, outcome);
    } on Object catch (e) {
      // Rolled back: answer 500 so the gateway retries.
      _log('webhook_failed', {'type': event.type, 'error': e.runtimeType});
      return const WebhookResult(500, 'error');
    }
  }

  String _apply(GatewayEvent e, DateTime now) => switch (e.kind) {
    GatewayEventKind.paymentCaptured => _onPayment(e, now),
    GatewayEventKind.subscriptionCreated => _onSubscriptionCreated(e, now),
    GatewayEventKind.subscriptionRenewed => _onSubscriptionRenewed(e, now),
    GatewayEventKind.subscriptionCancelledByCustomer ||
    GatewayEventKind.subscriptionCancelled ||
    GatewayEventKind.subscriptionOther => _onSubscriptionChange(e, now),
    GatewayEventKind.unhandled => 'unhandled',
  };

  OrderRow? _orderFor(GatewayEvent e) {
    final bySession = e.sessionId == null
        ? null
        : store.findOrder(e.sessionId!);
    final order =
        bySession ?? (e.orderRef == null ? null : store.findOrder(e.orderRef!));
    return order == null || order.status == OrderStatus.failed ? null : order;
  }

  /// The amount and currency the gateway reports must equal what this
  /// server computed for the order. The hosted checkout URL carries the
  /// amount as a query parameter, so a customer can edit it: an
  /// underpayment (or an overpayment, or another currency) grants nothing.
  bool _amountMatches(GatewayEvent e, OrderRow order, {required bool strict}) {
    final amountOk = e.amountCents == null
        ? !strict
        : e.amountCents == order.amountCents;
    final currencyOk = e.currency == null
        ? !strict
        : e.currency == order.currency;
    return amountOk && currencyOk;
  }

  String _onPayment(GatewayEvent e, DateTime now) {
    final order = _orderFor(e);
    if (order == null) return 'unknown_session';
    if (order.status == OrderStatus.paid) return 'already_paid';
    if (!_amountMatches(e, order, strict: true)) return 'amount_mismatch';

    if (order.product == OrderProduct.day) {
      final device = store.device(order.deviceHash)!;
      final current = device.paidUntil;
      // Stacking: time is added after whatever is already paid for.
      final from = current != null && current.isAfter(now) ? current : now;
      store
        ..setPaidUntil(
          order.deviceHash,
          from.add(Duration(hours: 24 * order.days!)),
        )
        ..setOrderStatus(order.orderRef, OrderStatus.paid, paidAt: now);
      return 'fulfilled_day';
    }

    store.setOrderStatus(order.orderRef, OrderStatus.paid, paidAt: now);
    if (store.subscriptionForOrder(order.orderRef) == null) {
      // The first charge of a subscription. `subscription.created` (when it
      // arrives) replaces this row with the gateway's id and period end.
      store.upsertSubscription(
        SubscriptionRow(
          subscriptionId: e.subscriptionId ?? 'order:${order.orderRef}',
          deviceHash: order.deviceHash,
          orderRef: order.orderRef,
          status: SubscriptionStatus.active,
          periodEnd: _laterOf(e.periodEnd, now) ?? addMonths(now, 1),
          cancelAtPeriodEnd: false,
          customerEmail: e.customerEmail,
          updatedAt: now,
        ),
      );
    }
    return 'fulfilled_monthly';
  }

  String _onSubscriptionCreated(GatewayEvent e, DateTime now) {
    final id = e.subscriptionId;
    if (id == null) return 'invalid_event';
    if (store.subscription(id) != null) return _onSubscriptionChange(e, now);

    final order = _orderFor(e);
    if (order == null || order.product != OrderProduct.monthly) {
      return 'unknown_session';
    }
    if (e.planCode != null && e.planCode != config.monthlyPlanCode) {
      return 'plan_mismatch';
    }
    final alreadyPaid = order.status == OrderStatus.paid;
    // If `payment.captured` hasn't proven the payment yet, this event has
    // to: then the amount is mandatory.
    if (!_amountMatches(e, order, strict: false) ||
        (!alreadyPaid && e.amountCents == null)) {
      return 'amount_mismatch';
    }
    if (!alreadyPaid) {
      store.setOrderStatus(order.orderRef, OrderStatus.paid, paidAt: now);
    }
    final provisional = store.subscriptionForOrder(order.orderRef);
    if (provisional != null) {
      store.deleteSubscription(provisional.subscriptionId);
    }
    store.upsertSubscription(
      SubscriptionRow(
        subscriptionId: id,
        deviceHash: order.deviceHash,
        orderRef: order.orderRef,
        status: e.status ?? SubscriptionStatus.active,
        periodEnd: e.periodEnd ?? provisional?.periodEnd ?? addMonths(now, 1),
        cancelAtPeriodEnd: e.status == SubscriptionStatus.cancelled,
        customerEmail: e.customerEmail ?? provisional?.customerEmail,
        updatedAt: now,
      ),
    );
    return 'subscription_created';
  }

  /// The subscription an event is about: by the gateway's id, else the
  /// provisional row of the order it quotes (adopting the gateway's id).
  SubscriptionRow? _subscriptionFor(GatewayEvent e) {
    final id = e.subscriptionId;
    final known = id == null ? null : store.subscription(id);
    if (known != null) return known;
    final order = _orderFor(e);
    final viaOrder = order == null
        ? null
        : store.subscriptionForOrder(order.orderRef);
    if (viaOrder == null || id == null || viaOrder.subscriptionId == id) {
      return viaOrder;
    }
    if (!viaOrder.subscriptionId.startsWith('order:')) return null;
    store.deleteSubscription(viaOrder.subscriptionId);
    final adopted = SubscriptionRow(
      subscriptionId: id,
      deviceHash: viaOrder.deviceHash,
      orderRef: viaOrder.orderRef,
      status: viaOrder.status,
      periodEnd: viaOrder.periodEnd,
      cancelAtPeriodEnd: viaOrder.cancelAtPeriodEnd,
      customerEmail: viaOrder.customerEmail,
      updatedAt: viaOrder.updatedAt,
    );
    store.upsertSubscription(adopted);
    return adopted;
  }

  String _onSubscriptionRenewed(GatewayEvent e, DateTime now) {
    final sub = _subscriptionFor(e);
    if (sub == null) return 'unknown_subscription';
    final order = sub.orderRef == null ? null : store.findOrder(sub.orderRef!);
    if (order != null && !_amountMatches(e, order, strict: false)) {
      return 'amount_mismatch';
    }
    // The gateway's date when it sends one; else one month after the later
    // of "now" and the period being renewed. Never moves backwards.
    final base = sub.periodEnd.isAfter(now) ? sub.periodEnd : now;
    final next = e.periodEnd ?? addMonths(base, 1);
    store.upsertSubscription(
      SubscriptionRow(
        subscriptionId: sub.subscriptionId,
        deviceHash: sub.deviceHash,
        orderRef: sub.orderRef,
        status: SubscriptionStatus.active,
        periodEnd: next.isAfter(sub.periodEnd) ? next : sub.periodEnd,
        cancelAtPeriodEnd: false,
        customerEmail: e.customerEmail,
        updatedAt: now,
      ),
    );
    return 'subscription_renewed';
  }

  String _onSubscriptionChange(GatewayEvent e, DateTime now) {
    final sub = _subscriptionFor(e);
    if (sub == null) return 'unknown_subscription';
    final cancelled =
        e.kind == GatewayEventKind.subscriptionCancelledByCustomer ||
        e.kind == GatewayEventKind.subscriptionCancelled;
    final status = cancelled ? SubscriptionStatus.cancelled : e.status;
    if (status == null) return 'unhandled';
    store.upsertSubscription(
      SubscriptionRow(
        subscriptionId: sub.subscriptionId,
        deviceHash: sub.deviceHash,
        orderRef: sub.orderRef,
        status: status,
        // A cancellation never extends access: the earlier date wins.
        periodEnd: cancelled
            ? _earlierOf(e.periodEnd, sub.periodEnd)
            : (e.periodEnd ?? sub.periodEnd),
        cancelAtPeriodEnd:
            status == SubscriptionStatus.cancelled ||
            (status != SubscriptionStatus.active && sub.cancelAtPeriodEnd),
        customerEmail: e.customerEmail,
        updatedAt: now,
      ),
    );
    return switch (e.kind) {
      GatewayEventKind.subscriptionCancelledByCustomer =>
        'subscription_cancelled_by_customer',
      GatewayEventKind.subscriptionCancelled => 'subscription_cancelled',
      _ => 'subscription_status_${status.wire.toLowerCase()}',
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static const _unknownDevice = ApiException(
    404,
    'device_not_registered',
    'Unknown device. Register it first.',
  );

  String _deviceId(Object? value) {
    if (value is! String || !isDeviceHash(value)) {
      throw const ApiException(
        400,
        'invalid_device_id',
        'deviceId must be 64 lowercase hex characters.',
      );
    }
    return value;
  }

  String _randomId(int length) => String.fromCharCodes([
    for (var i = 0; i < length; i++)
      _idAlphabet.codeUnitAt(_random.nextInt(_idAlphabet.length)),
  ]);

  static DateTime? _laterOf(DateTime? candidate, DateTime floor) =>
      candidate != null && candidate.isAfter(floor) ? candidate : null;

  static DateTime _earlierOf(DateTime? a, DateTime b) =>
      a != null && a.isBefore(b) ? a : b;

  static String _short(String did) => did.substring(0, 8);
}

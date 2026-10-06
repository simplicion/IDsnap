import 'dart:async';
import 'dart:convert';

import 'package:docscan_core/docscan_core.dart';
import 'package:engine_billing/src/billing_storage.dart';
import 'package:engine_billing/src/licence/device_identity.dart';
import 'package:engine_billing/src/licence/licence_client.dart';
import 'package:engine_license/engine_license.dart';
import 'package:flutter/foundation.dart';

/// What the licence on this phone grants right now.
enum LicenceKind { trial, dayPass, monthly, expired }

/// Why [LicenceKind.expired].
enum LicenceLapse {
  trialEnded,
  dayPassEnded,
  monthlyEnded,

  /// The clock is behind a time already seen (on this phone or reported by
  /// the server): expiry can't be trusted until the date is fixed.
  clockTampered,

  /// No licence and the device has never reached the server: the free day
  /// hasn't started. Connect once to start it.
  notActivated,
}

@immutable
class LicenceStatus {
  const LicenceStatus({
    required this.kind,
    this.expiresAt,
    this.paidUntil,
    this.willRenew = false,
    this.inGracePeriod = false,
    this.lapse,
    this.purchasePending = false,
  });

  const LicenceStatus.notActivated({this.purchasePending = false})
    : kind = LicenceKind.expired,
      expiresAt = null,
      paidUntil = null,
      willRenew = false,
      inGracePeriod = false,
      lapse = LicenceLapse.notActivated;

  final LicenceKind kind;

  /// When access ends (or ended), grace included.
  final DateTime? expiresAt;

  /// End of the paid period (monthly: the renewal date).
  final DateTime? paidUntil;
  final bool willRenew;

  /// Monthly: past [paidUntil], inside the grace days.
  final bool inGracePeriod;
  final LicenceLapse? lapse;

  /// A checkout is open and the app is waiting for the payment.
  final bool purchasePending;

  bool get isEntitled => kind != LicenceKind.expired;

  LicenceStatus withPending({required bool pending}) => LicenceStatus(
    kind: kind,
    expiresAt: expiresAt,
    paidUntil: paidUntil,
    willRenew: willRenew,
    inGracePeriod: inGracePeriod,
    lapse: lapse,
    purchasePending: pending,
  );

  @override
  bool operator ==(Object other) =>
      other is LicenceStatus &&
      other.kind == kind &&
      other.expiresAt == expiresAt &&
      other.paidUntil == paidUntil &&
      other.willRenew == willRenew &&
      other.inGracePeriod == inGracePeriod &&
      other.lapse == lapse &&
      other.purchasePending == purchasePending;

  @override
  int get hashCode => Object.hash(
    kind,
    expiresAt,
    paidUntil,
    willRenew,
    inGracePeriod,
    lapse,
    purchasePending,
  );

  @override
  String toString() =>
      'LicenceStatus(${kind.name}, expires: $expiresAt, lapse: $lapse, '
      'pending: $purchasePending)';
}

@immutable
class LicencePricing {
  const LicencePricing({
    required this.dayPriceCents,
    required this.monthPriceCents,
    required this.currency,
    required this.minDays,
    required this.maxDays,
    required this.fromServer,
  });

  factory LicencePricing.fromServer(ServerPricing p) => LicencePricing(
    dayPriceCents: p.dayPriceCents,
    monthPriceCents: p.monthPriceCents,
    currency: p.currency,
    minDays: p.minDays,
    maxDays: p.maxDays,
    fromServer: true,
  );

  /// Shown before the server was ever reached; labelled approximate.
  static const fallback = LicencePricing(
    dayPriceCents: 10,
    monthPriceCents: 250,
    currency: 'USD',
    minDays: 1,
    maxDays: 24,
    fromServer: false,
  );

  final int dayPriceCents;
  final int monthPriceCents;
  final String currency;
  final int minDays;
  final int maxDays;
  final bool fromServer;
}

enum LicencePurchaseKind {
  /// The server confirmed the payment; the new licence is stored.
  purchased,

  /// Checkout opened, no confirmation within the polling window.
  pending,
  failed,

  /// No connection to the licence server.
  offline,
}

@immutable
class LicencePurchaseResult {
  const LicencePurchaseResult(this.kind, {this.message});

  final LicencePurchaseKind kind;
  final String? message;

  @override
  String toString() => 'LicencePurchaseResult(${kind.name}, $message)';
}

@immutable
class LicenceRefreshResult {
  const LicenceRefreshResult({required this.ok, this.failure, this.message});

  final bool ok;
  final LicenceFailureKind? failure;
  final String? message;
}

/// Opens a URL outside the app (browser / custom tab). Returns false if
/// nothing could open it.
typedef UrlOpener = Future<bool> Function(Uri url);

/// About two minutes of polling after checkout opens, quick at first.
const defaultPurchasePollSchedule = [
  Duration(seconds: 3),
  Duration(seconds: 3),
  Duration(seconds: 4),
  Duration(seconds: 5),
  Duration(seconds: 5),
  Duration(seconds: 8),
  Duration(seconds: 10),
  Duration(seconds: 12),
  Duration(seconds: 15),
  Duration(seconds: 15),
  Duration(seconds: 20),
  Duration(seconds: 20),
];

/// Monthly licences are refreshed when they end within this window.
const renewalCheckWindow = Duration(days: 3);

/// Licensing on the phone: a signed licence token from the licence server
/// (docs/adr/0012-180pay-licence-server.md), verified offline with the
/// public key on every read.
///
/// - First launch: registers the device when online (starts the free day).
///   Offline with no token: [LicenceLapse.notActivated], never silent access.
/// - A valid token gives full access with no network at all.
/// - [refresh] at start and on resume; server failures keep the current
///   token.
/// - [purchase] opens checkout in the browser and polls the server; access
///   is granted only by a new signed token, i.e. only after the server got
///   the verified payment webhook.
class LicenceEngine {
  LicenceEngine({
    required BillingStorage storage,
    required LicenceClient client,
    required LicenceVerifier verifier,
    required DeviceIdentity identity,
    required UrlOpener openUrl,
    required this.platform,
    required this.appVersion,
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
    this.pollSchedule = defaultPurchasePollSchedule,
    this.staleAfter = const Duration(hours: 6),
    RedactedLogger? logger,
  }) : _storage = storage,
       _client = client,
       _verifier = verifier,
       _identity = identity,
       _openUrl = openUrl,
       _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _log = logger ?? RedactedLogger('licence');

  static const tokenKey = 'licence.token';
  static const maxSeenKey = 'licence.max_seen';
  static const pricingKey = 'licence.pricing';

  /// "android" or "ios" (sent at registration).
  final String platform;
  final String appVersion;
  final List<Duration> pollSchedule;

  /// [shouldRefresh] is true once the last successful refresh is older.
  final Duration staleAfter;

  final BillingStorage _storage;
  final LicenceClient _client;
  final LicenceVerifier _verifier;
  final DeviceIdentity _identity;
  final UrlOpener _openUrl;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final RedactedLogger _log;

  final _changes = StreamController<LicenceStatus>.broadcast();
  String? _deviceHash;
  LicencePayload? _payload;
  DateTime? _maxSeen;
  DateTime? _persistedMaxSeen;
  DateTime? _lastRefresh;
  ServerPricing? _pricing;
  Future<LicenceRefreshResult>? _refreshing;
  var _pending = false;
  var _purchasing = false;
  LicenceStatus? _last;

  /// The licence right now. Synchronous and cheap: recomputed on every read
  /// so a licence that ends while the app is open lapses on time.
  LicenceStatus get status {
    final now = _now().toUtc();
    final payload = _payload;
    final device = _deviceHash;
    final rolledBack = isClockRolledBack(now, _maxSeen);
    if (!rolledBack) _observe(now);
    if (payload == null || device == null) {
      return LicenceStatus.notActivated(purchasePending: _pending);
    }
    final verdict = evaluateLicence(
      payload: payload,
      deviceHash: device,
      now: now,
      maxSeen: _maxSeen,
    );
    final plan = payload.plan;
    final status = switch (verdict.kind) {
      LicenceVerdictKind.valid => LicenceStatus(
        kind: switch (plan) {
          LicencePlan.trial => LicenceKind.trial,
          LicencePlan.day => LicenceKind.dayPass,
          LicencePlan.monthly => LicenceKind.monthly,
        },
        expiresAt: payload.expiresAt,
        paidUntil: payload.paidUntil,
        willRenew: payload.willRenew ?? false,
        inGracePeriod:
            plan == LicencePlan.monthly && !now.isBefore(payload.paidUntil),
      ),
      LicenceVerdictKind.clockRolledBack => LicenceStatus(
        kind: LicenceKind.expired,
        expiresAt: payload.expiresAt,
        paidUntil: payload.paidUntil,
        lapse: LicenceLapse.clockTampered,
      ),
      LicenceVerdictKind.expired => LicenceStatus(
        kind: LicenceKind.expired,
        expiresAt: payload.expiresAt,
        paidUntil: payload.paidUntil,
        lapse: switch (plan) {
          LicencePlan.trial => LicenceLapse.trialEnded,
          LicencePlan.day => LicenceLapse.dayPassEnded,
          LicencePlan.monthly => LicenceLapse.monthlyEnded,
        },
      ),
      // Never stored (see _accept), but never trusted either.
      _ => const LicenceStatus.notActivated(),
    };
    return status.withPending(pending: _pending);
  }

  Stream<LicenceStatus> get changes => _changes.stream;

  /// Loads the stored licence and verifies it. Doesn't touch the network.
  Future<void> start() async {
    _deviceHash = await _identity.deviceHash();
    _maxSeen = _parseTime(await _read(maxSeenKey));
    _persistedMaxSeen = _maxSeen;
    _pricing = ServerPricing.fromJson(_decode(await _read(pricingKey)));
    final token = await _read(tokenKey);
    if (token != null) {
      try {
        final payload = await _verifier.verify(token);
        if (payload.deviceHash == _deviceHash) {
          _payload = payload;
        } else {
          // Copied from another phone (or the device ID changed).
          _log.warn('stored_token_other_device');
          await _delete(tokenKey);
        }
      } on LicenceTokenException catch (e) {
        _log.warn('stored_token_invalid', {'error': e.error.name});
        await _delete(tokenKey);
      }
    }
    _emit();
  }

  /// True when a background refresh is worth a request: no usable licence,
  /// a licence ending within [renewalCheckWindow], or the last successful
  /// refresh is older than [staleAfter].
  bool get shouldRefresh {
    final s = status;
    final now = _now().toUtc();
    final last = _lastRefresh;
    return !s.isEntitled ||
        (s.expiresAt != null &&
            s.expiresAt!.difference(now) < renewalCheckWindow) ||
        last == null ||
        now.difference(last) > staleAfter;
  }

  /// Registers the device (no licence yet) or fetches its current licence.
  /// Concurrent calls share one request. Never throws: on failure the
  /// stored licence stays in force.
  Future<LicenceRefreshResult> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<LicenceRefreshResult> _refresh() async {
    final device = _deviceHash ?? await _identity.deviceHash();
    _deviceHash = device;
    try {
      LicenceResponse response;
      if (_payload == null) {
        response = await _register(device);
      } else {
        try {
          response = await _client.entitlement(device);
        } on LicenceClientException catch (e) {
          // E.g. the server's database was restored: register again (the
          // server never restarts a trial for a known device).
          if (e.kind != LicenceFailureKind.notRegistered) rethrow;
          response = await _register(device);
        }
      }
      await _accept(response);
      _lastRefresh = _now().toUtc();
      _emit();
      return const LicenceRefreshResult(ok: true);
    } on LicenceClientException catch (e) {
      _log.info('refresh_failed', {'kind': e.kind.name});
      _emit();
      return LicenceRefreshResult(
        ok: false,
        failure: e.kind,
        message: e.message,
      );
    }
  }

  Future<LicenceResponse> _register(String device) => _client.register(
    deviceHash: device,
    platform: platform,
    appVersion: appVersion,
  );

  /// Verifies and stores a token from the server. A token that doesn't
  /// verify, or is for another device, is a bad response, never a licence.
  Future<void> _accept(LicenceResponse response) async {
    final LicencePayload payload;
    try {
      payload = await _verifier.verify(response.token);
    } on LicenceTokenException {
      _log.warn('server_token_invalid');
      throw const LicenceClientException(LicenceFailureKind.invalidResponse);
    }
    if (payload.deviceHash != _deviceHash) {
      _log.warn('server_token_other_device');
      throw const LicenceClientException(LicenceFailureKind.invalidResponse);
    }
    final current = _payload;
    // Never go back to an older licence (a delayed or replayed response).
    if (current == null || !payload.issuedAt.isBefore(current.issuedAt)) {
      _payload = payload;
      await _write(tokenKey, response.token);
    }
    // The server's clock is the reference while online: this also clears a
    // false "clock set back" after the user fixes a clock that was ahead.
    _maxSeen = response.serverTime;
    await _persistMaxSeen(force: true);
    final pricing = response.pricing;
    if (pricing != null) await _savePricing(pricing);
  }

  /// Prices from the server (cached), or the labelled fallback.
  Future<LicencePricing> pricing() async {
    try {
      await _savePricing(await _client.config());
    } on LicenceClientException {
      // Use the cached or fallback prices.
    }
    final p = _pricing;
    return p == null ? LicencePricing.fallback : LicencePricing.fromServer(p);
  }

  /// Creates a checkout order, opens it in the browser, then polls the
  /// server until the payment shows up in a new licence (about two
  /// minutes). Access is never granted from the client side.
  Future<LicencePurchaseResult> purchase(
    CheckoutProduct product, {
    int? days,
  }) async {
    if (_purchasing) {
      return const LicencePurchaseResult(
        LicencePurchaseKind.failed,
        message: 'A payment is already in progress.',
      );
    }
    _purchasing = true;
    try {
      if (_payload == null) {
        final r = await refresh();
        if (!r.ok) return _failure(r.failure);
      }
      final device = _deviceHash!;
      final before = _payload;
      final CheckoutResponse checkout;
      try {
        checkout = await _client.checkout(
          deviceHash: device,
          product: product,
          days: product == CheckoutProduct.day ? days : null,
        );
      } on LicenceClientException catch (e) {
        return _failure(e.kind, e.message);
      }
      var opened = false;
      try {
        opened = await _openUrl(checkout.checkoutUrl);
      } on Object {
        opened = false;
      }
      if (!opened) {
        return const LicencePurchaseResult(
          LicencePurchaseKind.failed,
          message:
              "Couldn't open the payment page. Check that a browser is "
              'installed and try again.',
        );
      }
      _pending = true;
      _emit();
      for (final wait in pollSchedule) {
        await _sleep(wait);
        final r = await refresh();
        if (r.ok && _paidFor(product, before)) {
          _pending = false;
          _emit();
          return const LicencePurchaseResult(LicencePurchaseKind.purchased);
        }
      }
      _pending = false;
      _emit();
      return const LicencePurchaseResult(LicencePurchaseKind.pending);
    } finally {
      _purchasing = false;
    }
  }

  /// The current licence shows the purchase: a monthly plan, or paid
  /// day-pass time beyond what there was before checkout.
  bool _paidFor(CheckoutProduct product, LicencePayload? before) {
    final now = _payload;
    if (now == null || !status.isEntitled) return false;
    if (product == CheckoutProduct.monthly) {
      return now.plan == LicencePlan.monthly;
    }
    final previous = before == null || before.plan == LicencePlan.trial
        ? null
        : before.paidUntil;
    return now.plan != LicencePlan.trial &&
        (previous == null || now.paidUntil.isAfter(previous));
  }

  /// Opens 180 Pay's customer portal (manage / cancel the monthly plan).
  /// False when the server or the portal isn't available.
  Future<bool> openManageSubscription() async {
    try {
      final device = _deviceHash ?? await _identity.deviceHash();
      final url = await _client.portal(device);
      return await _openUrl(url);
    } on Object {
      return false;
    }
  }

  Future<void> dispose() async {
    await _persistMaxSeen(force: true);
    await _changes.close();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  LicencePurchaseResult _failure(LicenceFailureKind? kind, [String? message]) =>
      switch (kind) {
        LicenceFailureKind.offline => const LicencePurchaseResult(
          LicencePurchaseKind.offline,
        ),
        LicenceFailureKind.rejected => LicencePurchaseResult(
          LicencePurchaseKind.failed,
          message: message,
        ),
        LicenceFailureKind.rateLimited => const LicencePurchaseResult(
          LicencePurchaseKind.failed,
          message: 'Too many attempts. Please wait a few minutes.',
        ),
        _ => const LicencePurchaseResult(
          LicencePurchaseKind.failed,
          message:
              "The payment service isn't available right now. You were "
              'not charged. Try again in a moment.',
        ),
      };

  /// Moves max-time-seen forward with the phone's clock. It never moves
  /// back, so setting the date back is detected until the date is fixed
  /// (or the server reports the real time).
  void _observe(DateTime now) {
    final seen = _maxSeen;
    if (seen != null && !now.isAfter(seen)) return;
    _maxSeen = now;
    final persisted = _persistedMaxSeen;
    if (persisted == null ||
        now.difference(persisted) > const Duration(minutes: 1)) {
      unawaited(_persistMaxSeen());
    }
  }

  Future<void> _persistMaxSeen({bool force = false}) async {
    final value = _maxSeen;
    if (value == null) return;
    if (!force && value == _persistedMaxSeen) return;
    _persistedMaxSeen = value;
    await _write(maxSeenKey, '${value.millisecondsSinceEpoch}');
  }

  Future<void> _savePricing(ServerPricing p) async {
    _pricing = p;
    await _write(pricingKey, jsonEncode(p.toJson()));
  }

  void _emit() {
    if (_changes.isClosed) return;
    final s = status;
    if (s == _last) return;
    _last = s;
    _changes.add(s);
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key);
    } on Object {
      // Unreadable (e.g. a restored backup whose Keystore key is gone):
      // start clean.
      await _delete(key);
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key, value);
    } on Object {
      // In memory for this session; the next refresh retries.
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key);
    } on Object {
      // Nothing else to do.
    }
  }

  static DateTime? _parseTime(String? raw) {
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  static Object? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }
}

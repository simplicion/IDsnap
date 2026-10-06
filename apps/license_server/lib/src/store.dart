import 'package:license_server/src/gateway.dart';
import 'package:sqlite3/sqlite3.dart';

int _secs(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime _time(Object? secs) =>
    DateTime.fromMillisecondsSinceEpoch((secs! as int) * 1000, isUtc: true);

DateTime? _timeOrNull(Object? secs) => secs == null ? null : _time(secs);

class DeviceRow {
  const DeviceRow({
    required this.deviceHash,
    required this.createdAt,
    required this.trialEndsAt,
    this.paidUntil,
  });

  final String deviceHash;
  final DateTime createdAt;
  final DateTime trialEndsAt;

  /// End of prepaid day-pass time, if any was ever bought.
  final DateTime? paidUntil;
}

enum OrderProduct { day, monthly }

enum OrderStatus { pending, paid, failed }

class OrderRow {
  const OrderRow({
    required this.orderRef,
    required this.deviceHash,
    required this.product,
    required this.amountCents,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.days,
    this.gatewaySessionId,
  });

  final String orderRef;
  final String? gatewaySessionId;
  final String deviceHash;
  final OrderProduct product;
  final int? days;
  final int amountCents;
  final String currency;
  final OrderStatus status;
  final DateTime createdAt;
}

class SubscriptionRow {
  const SubscriptionRow({
    required this.subscriptionId,
    required this.deviceHash,
    required this.status,
    required this.periodEnd,
    required this.cancelAtPeriodEnd,
    required this.updatedAt,
    this.orderRef,
    this.customerEmail,
  });

  /// The gateway's id, or `order:<orderRef>` until the gateway tells us.
  final String subscriptionId;
  final String deviceHash;
  final SubscriptionStatus status;
  final DateTime periodEnd;
  final bool cancelAtPeriodEnd;
  final DateTime updatedAt;
  final String? orderRef;

  /// Only what the gateway sent, only for the billing portal.
  final String? customerEmail;
}

/// SQLite persistence. Synchronous on purpose: a request's reads and
/// writes run without interleaving, and [transaction] makes them atomic.
class LicenceStore {
  LicenceStore(this._db) {
    _db
      ..execute('PRAGMA foreign_keys = ON')
      ..execute('PRAGMA busy_timeout = 5000');
    _migrate();
  }

  factory LicenceStore.open(String path) {
    final db = sqlite3.open(path)..execute('PRAGMA journal_mode = WAL');
    return LicenceStore(db);
  }

  factory LicenceStore.memory() => LicenceStore(sqlite3.openInMemory());

  final Database _db;

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        did TEXT PRIMARY KEY,
        platform TEXT NOT NULL,
        app_version TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        trial_ends_at INTEGER NOT NULL,
        paid_until INTEGER,
        last_seen_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS orders (
        order_ref TEXT PRIMARY KEY,
        gateway_session_id TEXT UNIQUE,
        did TEXT NOT NULL REFERENCES devices(did),
        product TEXT NOT NULL,
        days INTEGER,
        amount_cents INTEGER NOT NULL,
        currency TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        paid_at INTEGER
      );
      CREATE INDEX IF NOT EXISTS orders_did ON orders(did, created_at);
      CREATE TABLE IF NOT EXISTS subscriptions (
        subscription_id TEXT PRIMARY KEY,
        did TEXT NOT NULL REFERENCES devices(did),
        order_ref TEXT,
        status TEXT NOT NULL,
        period_end INTEGER NOT NULL,
        cancel_at_period_end INTEGER NOT NULL DEFAULT 0,
        customer_email TEXT,
        updated_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS subscriptions_did ON subscriptions(did);
      CREATE TABLE IF NOT EXISTS events (
        event_key TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        outcome TEXT NOT NULL,
        received_at INTEGER NOT NULL
      );
    ''');
  }

  /// Runs [body] atomically; rolls back and rethrows on any error.
  T transaction<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } on Object {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => _db.close();

  // ── Devices ────────────────────────────────────────────────────────────────

  DeviceRow? device(String did) {
    final rows = _db.select('SELECT * FROM devices WHERE did = ?', [did]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return DeviceRow(
      deviceHash: r['did'] as String,
      createdAt: _time(r['created_at']),
      trialEndsAt: _time(r['trial_ends_at']),
      paidUntil: _timeOrNull(r['paid_until']),
    );
  }

  /// Inserts the device if it's new. Returns true when it was created.
  /// An existing device keeps its `created_at` and `trial_ends_at`: this is
  /// what makes re-registering (reinstalling) never restart the trial.
  bool insertDeviceIfAbsent({
    required String did,
    required String platform,
    required String appVersion,
    required DateTime now,
    required DateTime trialEndsAt,
  }) {
    _db.execute(
      'INSERT OR IGNORE INTO devices '
      '(did, platform, app_version, created_at, trial_ends_at, last_seen_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [did, platform, appVersion, _secs(now), _secs(trialEndsAt), _secs(now)],
    );
    final created = _db.updatedRows == 1;
    if (!created) {
      _db.execute(
        'UPDATE devices SET platform = ?, app_version = ?, last_seen_at = ? '
        'WHERE did = ?',
        [platform, appVersion, _secs(now), did],
      );
    }
    return created;
  }

  void setPaidUntil(String did, DateTime paidUntil) => _db.execute(
    'UPDATE devices SET paid_until = ? WHERE did = ?',
    [_secs(paidUntil), did],
  );

  // ── Orders ─────────────────────────────────────────────────────────────────

  void insertOrder(OrderRow order) => _db.execute(
    'INSERT INTO orders (order_ref, did, product, days, amount_cents, '
    'currency, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      order.orderRef,
      order.deviceHash,
      order.product.name,
      order.days,
      order.amountCents,
      order.currency,
      order.status.name,
      _secs(order.createdAt),
    ],
  );

  void setGatewaySession(String orderRef, String sessionId) => _db.execute(
    'UPDATE orders SET gateway_session_id = ? WHERE order_ref = ?',
    [sessionId, orderRef],
  );

  void setOrderStatus(
    String orderRef,
    OrderStatus status, {
    DateTime? paidAt,
  }) => _db.execute(
    'UPDATE orders SET status = ?, paid_at = ? WHERE order_ref = ?',
    [status.name, if (paidAt == null) null else _secs(paidAt), orderRef],
  );

  /// Finds an order by any id the gateway may quote: the session id it
  /// gave us, or our own order ref.
  OrderRow? findOrder(String id) {
    final rows = _db.select(
      'SELECT * FROM orders WHERE gateway_session_id = ?1 OR order_ref = ?1 '
      'LIMIT 1',
      [id],
    );
    return rows.isEmpty ? null : _order(rows.first);
  }

  int pendingOrdersSince(String did, DateTime since) =>
      _db.select(
            'SELECT COUNT(*) AS n FROM orders WHERE did = ? AND status = ? '
            'AND created_at >= ?',
            [did, OrderStatus.pending.name, _secs(since)],
          ).first['n']
          as int;

  OrderRow _order(Row r) => OrderRow(
    orderRef: r['order_ref'] as String,
    gatewaySessionId: r['gateway_session_id'] as String?,
    deviceHash: r['did'] as String,
    product: OrderProduct.values.byName(r['product'] as String),
    days: r['days'] as int?,
    amountCents: r['amount_cents'] as int,
    currency: r['currency'] as String,
    status: OrderStatus.values.byName(r['status'] as String),
    createdAt: _time(r['created_at']),
  );

  // ── Subscriptions ──────────────────────────────────────────────────────────

  void upsertSubscription(SubscriptionRow s) => _db.execute(
    'INSERT INTO subscriptions (subscription_id, did, order_ref, status, '
    'period_end, cancel_at_period_end, customer_email, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
    'ON CONFLICT(subscription_id) DO UPDATE SET status = excluded.status, '
    'period_end = excluded.period_end, '
    'cancel_at_period_end = excluded.cancel_at_period_end, '
    'customer_email = COALESCE(excluded.customer_email, customer_email), '
    'updated_at = excluded.updated_at',
    [
      s.subscriptionId,
      s.deviceHash,
      s.orderRef,
      s.status.wire,
      _secs(s.periodEnd),
      if (s.cancelAtPeriodEnd) 1 else 0,
      s.customerEmail,
      _secs(s.updatedAt),
    ],
  );

  void deleteSubscription(String subscriptionId) => _db.execute(
    'DELETE FROM subscriptions WHERE subscription_id = ?',
    [subscriptionId],
  );

  SubscriptionRow? subscription(String subscriptionId) {
    final rows = _db.select(
      'SELECT * FROM subscriptions WHERE subscription_id = ?',
      [subscriptionId],
    );
    return rows.isEmpty ? null : _subscription(rows.first);
  }

  SubscriptionRow? subscriptionForOrder(String orderRef) {
    final rows = _db.select(
      'SELECT * FROM subscriptions WHERE order_ref = ? LIMIT 1',
      [orderRef],
    );
    return rows.isEmpty ? null : _subscription(rows.first);
  }

  List<SubscriptionRow> subscriptionsOf(String did) => [
    for (final r in _db.select('SELECT * FROM subscriptions WHERE did = ?', [
      did,
    ]))
      _subscription(r),
  ];

  SubscriptionRow _subscription(Row r) => SubscriptionRow(
    subscriptionId: r['subscription_id'] as String,
    deviceHash: r['did'] as String,
    orderRef: r['order_ref'] as String?,
    status: SubscriptionStatus.parse(r['status']) ?? SubscriptionStatus.expired,
    periodEnd: _time(r['period_end']),
    cancelAtPeriodEnd: r['cancel_at_period_end'] == 1,
    customerEmail: r['customer_email'] as String?,
    updatedAt: _time(r['updated_at']),
  );

  // ── Processed webhook events ───────────────────────────────────────────────

  bool eventSeen(String key) =>
      _db.select('SELECT 1 FROM events WHERE event_key = ?', [key]).isNotEmpty;

  void recordEvent(String key, String type, String outcome, DateTime now) =>
      _db.execute(
        'INSERT OR IGNORE INTO events (event_key, type, outcome, received_at) '
        'VALUES (?, ?, ?, ?)',
        [key, type, outcome, _secs(now)],
      );

  String? eventOutcome(String key) {
    final rows = _db.select('SELECT outcome FROM events WHERE event_key = ?', [
      key,
    ]);
    return rows.isEmpty ? null : rows.first['outcome'] as String;
  }
}

import 'package:engine_license/engine_license.dart';

/// Thrown when the environment is incomplete or invalid. The message lists
/// every problem (variable names only, never values).
class ConfigException implements Exception {
  const ConfigException(this.problems);

  final List<String> problems;

  @override
  String toString() => 'Invalid configuration:\n- ${problems.join('\n- ')}';
}

/// How a checkout is started at 180 Pay (see PayGateway).
enum CheckoutMode {
  /// Documented server-to-server call: `POST /api/v1/checkout/sessions`.
  /// 180 Pay creates the session, so the amount is fixed on their side.
  api,

  /// No API call: the hosted checkout URL is built with a session id this
  /// server generated (the pattern the public JS SDK uses). The amount is
  /// then only a query parameter the customer can edit.
  hostedUrl,
}

/// Unit of `data.amount` in 180 Pay webhooks.
enum AmountUnit {
  /// 2.50 means two dollars fifty (what the documented API requests use).
  major,

  /// 250 means two dollars fifty.
  minor,
}

/// All configuration, read ONLY from environment variables. Secrets are
/// never logged and never have defaults.
class ServerConfig {
  const ServerConfig({
    required this.clientId,
    required this.clientSecret,
    required this.webhookSecret,
    required this.signingKey,
    required this.coreUrl,
    required this.payUrl,
    this.publicBaseUrl,
    this.trialHours = 24,
    this.dayPriceCents = 10,
    this.monthPriceCents = 250,
    this.currency = 'USD',
    this.minDays = 1,
    this.maxDays = 24,
    this.monthlyPlanCode = 'idsnap-monthly',
    this.graceDays = 3,
    this.checkoutMode = CheckoutMode.api,
    this.webhookAmountUnit = AmountUnit.major,
    this.checkoutHostSuffix = '180workspace.com',
    this.appName = 'IDSnap',
    this.databasePath = 'license.db',
    this.port = 8080,
    this.trustProxy = false,
  });

  /// Reads and validates [env] (normally `Platform.environment`).
  factory ServerConfig.fromEnv(Map<String, String> env) {
    final problems = <String>[];

    String required(String name) {
      final value = env[name]?.trim() ?? '';
      if (value.isEmpty) problems.add('$name is required');
      return value;
    }

    int integer(String name, int fallback, {int min = 0, int max = 1 << 31}) {
      final raw = env[name]?.trim();
      if (raw == null || raw.isEmpty) return fallback;
      final value = int.tryParse(raw);
      if (value == null || value < min || value > max) {
        problems.add('$name must be a whole number from $min to $max');
        return fallback;
      }
      return value;
    }

    Uri url(String name, String? fallback, {bool httpsOnly = true}) {
      final raw = env[name]?.trim();
      final text = raw == null || raw.isEmpty ? fallback : raw;
      final uri = text == null ? null : Uri.tryParse(text);
      final local = uri != null && _isLocalHost(uri.host);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          !(uri.scheme == 'https' ||
              (uri.scheme == 'http' && (local || !httpsOnly)))) {
        problems.add('$name must be an https:// URL');
        return Uri.parse('https://invalid.invalid');
      }
      return uri;
    }

    bool flag(String name) =>
        const {'1', 'true', 'yes'}.contains(env[name]?.trim().toLowerCase());

    final signingKey = required('LICENSE_SIGNING_KEY');
    if (signingKey.isNotEmpty) {
      if (decodeLicenceKey(signingKey) == null) {
        problems.add(
          'LICENSE_SIGNING_KEY must be a 32-byte Ed25519 seed in base64url '
          '(dart run tool/keygen.dart)',
        );
      } else if (isDevLicencePrivateKey(signingKey) && !flag('ALLOW_DEV_KEY')) {
        problems.add(
          'LICENSE_SIGNING_KEY is the published dev key; generate a real one '
          '(or set ALLOW_DEV_KEY=true for local development only)',
        );
      }
    }

    final currency = (env['CURRENCY']?.trim() ?? '').isEmpty
        ? 'USD'
        : env['CURRENCY']!.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      problems.add('CURRENCY must be a 3-letter code');
    }

    final planCode = (env['MONTHLY_PLAN_CODE']?.trim() ?? '').isEmpty
        ? 'idsnap-monthly'
        : env['MONTHLY_PLAN_CODE']!.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(planCode)) {
      problems.add('MONTHLY_PLAN_CODE may only contain letters, digits, - _');
    }

    final minDays = integer('MIN_DAYS', 1, min: 1, max: 366);
    final maxDays = integer('MAX_DAYS', 24, min: 1, max: 366);
    if (minDays > maxDays) problems.add('MIN_DAYS must not exceed MAX_DAYS');

    final modeRaw = env['ONE_EIGHTY_CHECKOUT_MODE']?.trim().toLowerCase() ?? '';
    final mode = switch (modeRaw) {
      '' || 'api' => CheckoutMode.api,
      'hosted_url' => CheckoutMode.hostedUrl,
      _ => null,
    };
    if (mode == null) {
      problems.add('ONE_EIGHTY_CHECKOUT_MODE must be api or hosted_url');
    }

    final unitRaw =
        env['ONE_EIGHTY_WEBHOOK_AMOUNT_UNIT']?.trim().toLowerCase() ?? '';
    final unit = switch (unitRaw) {
      '' || 'major' => AmountUnit.major,
      'minor' => AmountUnit.minor,
      _ => null,
    };
    if (unit == null) {
      problems.add('ONE_EIGHTY_WEBHOOK_AMOUNT_UNIT must be major or minor');
    }

    final publicRaw = env['PUBLIC_BASE_URL']?.trim() ?? '';
    final config = ServerConfig(
      clientId: required('ONE_EIGHTY_CLIENT_ID'),
      clientSecret: required('ONE_EIGHTY_CLIENT_SECRET'),
      webhookSecret: required('ONE_EIGHTY_WEBHOOK_SECRET'),
      signingKey: signingKey,
      coreUrl: url('ONE_EIGHTY_CORE_URL', 'https://services.180workspace.com'),
      payUrl: url('ONE_EIGHTY_PAY_URL', 'https://pay.180workspace.com'),
      publicBaseUrl: publicRaw.isEmpty ? null : url('PUBLIC_BASE_URL', null),
      trialHours: integer('TRIAL_HOURS', 24, max: 24 * 365),
      dayPriceCents: integer('DAY_PRICE_CENTS', 10, min: 1, max: 1000000),
      monthPriceCents: integer('MONTH_PRICE_CENTS', 250, min: 1, max: 10000000),
      currency: currency,
      minDays: minDays,
      maxDays: maxDays,
      monthlyPlanCode: planCode,
      graceDays: integer('MONTHLY_GRACE_DAYS', 3, max: 30),
      checkoutMode: mode ?? CheckoutMode.api,
      webhookAmountUnit: unit ?? AmountUnit.major,
      checkoutHostSuffix:
          (env['ONE_EIGHTY_CHECKOUT_HOST_SUFFIX']?.trim() ?? '').isEmpty
          ? '180workspace.com'
          : env['ONE_EIGHTY_CHECKOUT_HOST_SUFFIX']!.trim().toLowerCase(),
      appName: (env['APP_NAME']?.trim() ?? '').isEmpty
          ? 'IDSnap'
          : env['APP_NAME']!.trim(),
      databasePath: (env['DATABASE_PATH']?.trim() ?? '').isEmpty
          ? 'license.db'
          : env['DATABASE_PATH']!.trim(),
      port: integer('PORT', 8080, min: 1, max: 65535),
      trustProxy: flag('TRUST_PROXY'),
    );
    if (problems.isNotEmpty) throw ConfigException(problems);
    return config;
  }

  // ── 180 Pay credentials (secrets: never log) ───────────────────────────────
  final String clientId;
  final String clientSecret;
  final String webhookSecret;

  /// Ed25519 private seed, base64url (secret: never log).
  final String signingKey;

  /// 180 Core API (`ONE_EIGHTY_CORE_URL`).
  final Uri coreUrl;

  /// 180 Pay hosted checkout (`ONE_EIGHTY_PAY_URL`).
  final Uri payUrl;

  /// Where this server is reachable from the internet. Used for the
  /// checkout return page (`/v1/checkout/return`).
  final Uri? publicBaseUrl;

  // ── Business rules ─────────────────────────────────────────────────────────
  final int trialHours;
  final int dayPriceCents;
  final int monthPriceCents;
  final String currency;
  final int minDays;
  final int maxDays;
  final String monthlyPlanCode;

  /// Days a renewing monthly plan stays unlocked past its period end
  /// (matches 180 Pay's 3-day dunning window).
  final int graceDays;

  // ── Gateway behaviour ──────────────────────────────────────────────────────
  final CheckoutMode checkoutMode;
  final AmountUnit webhookAmountUnit;

  /// Checkout and portal URLs returned by the gateway must be https and on
  /// this domain (or a subdomain) before they are handed to the app.
  final String checkoutHostSuffix;

  /// Shown on the hosted checkout page.
  final String appName;

  // ── Runtime ────────────────────────────────────────────────────────────────
  final String databasePath;
  final int port;

  /// True when exactly one trusted reverse proxy sits in front and sets
  /// `X-Forwarded-For`. Otherwise the socket address is the client.
  final bool trustProxy;

  Duration get trial => Duration(hours: trialHours);
  Duration get grace => Duration(days: graceDays);
}

bool _isLocalHost(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

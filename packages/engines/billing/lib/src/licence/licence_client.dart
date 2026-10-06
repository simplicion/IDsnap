import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Why a licence-server call failed. The engine maps these to user-facing
/// states; none of them ever unlocks anything.
enum LicenceFailureKind {
  /// No connection, DNS failure, timeout.
  offline,

  /// 5xx, or the payment service behind the server is down.
  server,

  /// The answer wasn't the JSON we expect (or a token didn't verify).
  invalidResponse,

  /// The server doesn't know this device (404 device_not_registered).
  notRegistered,

  /// 429.
  rateLimited,

  /// 4xx with a message for the user (e.g. already subscribed).
  rejected,
}

class LicenceClientException implements Exception {
  const LicenceClientException(this.kind, {this.code, this.message});

  final LicenceFailureKind kind;

  /// The server's error code, when it sent one.
  final String? code;

  /// The server's user-facing message, when it sent one.
  final String? message;

  @override
  String toString() => 'LicenceClientException(${kind.name}, $code)';
}

/// Server pricing (`pricing` / `GET /v1/config`).
@immutable
class ServerPricing {
  const ServerPricing({
    required this.dayPriceCents,
    required this.monthPriceCents,
    required this.currency,
    required this.minDays,
    required this.maxDays,
  });

  final int dayPriceCents;
  final int monthPriceCents;
  final String currency;
  final int minDays;
  final int maxDays;

  Map<String, Object?> toJson() => {
    'dayPriceCents': dayPriceCents,
    'monthPriceCents': monthPriceCents,
    'currency': currency,
    'minDays': minDays,
    'maxDays': maxDays,
  };

  static ServerPricing? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final day = json['dayPriceCents'];
    final month = json['monthPriceCents'];
    final currency = json['currency'];
    final min = json['minDays'];
    final max = json['maxDays'];
    if (day is! int ||
        month is! int ||
        currency is! String ||
        min is! int ||
        max is! int ||
        day <= 0 ||
        month <= 0 ||
        min < 1 ||
        max < min ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      return null;
    }
    return ServerPricing(
      dayPriceCents: day,
      monthPriceCents: month,
      currency: currency,
      minDays: min,
      maxDays: max,
    );
  }
}

/// `register` / `entitlement`: a signed token plus the server's clock.
@immutable
class LicenceResponse {
  const LicenceResponse({
    required this.token,
    required this.serverTime,
    this.pricing,
  });

  /// Not yet verified: the engine checks the signature.
  final String token;
  final DateTime serverTime;
  final ServerPricing? pricing;
}

@immutable
class CheckoutResponse {
  const CheckoutResponse({
    required this.sessionId,
    required this.checkoutUrl,
    required this.amountCents,
    required this.currency,
  });

  final String sessionId;

  /// Opened in the external browser. Card data never touches the app.
  final Uri checkoutUrl;
  final int amountCents;
  final String currency;
}

enum CheckoutProduct { day, monthly }

/// The licence server API. The ONLY network code in the app (an
/// architecture test enforces it). Only the device-ID hash is ever sent.
abstract interface class LicenceClient {
  Future<LicenceResponse> register({
    required String deviceHash,
    required String platform,
    required String appVersion,
  });

  Future<LicenceResponse> entitlement(String deviceHash);

  Future<ServerPricing> config();

  Future<CheckoutResponse> checkout({
    required String deviceHash,
    required CheckoutProduct product,
    int? days,
  });

  /// 180 Pay's customer portal for this device's monthly plan.
  Future<Uri> portal(String deviceHash);
}

/// [LicenceClient] over `package:http`: JSON, timeouts, and retries with
/// exponential backoff for calls that are safe to repeat (everything but
/// checkout, which would create a second order).
class HttpLicenceClient implements LicenceClient {
  HttpLicenceClient({
    required this.baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.retries = 2,
    this.backoff = const Duration(milliseconds: 500),
    Future<void> Function(Duration)? sleep,
  }) : _client = client ?? http.Client(),
       _sleep = sleep ?? Future<void>.delayed;

  final Uri baseUrl;
  final Duration timeout;

  /// Extra attempts after the first, for idempotent calls.
  final int retries;
  final Duration backoff;
  final http.Client _client;
  final Future<void> Function(Duration) _sleep;
  final _jitter = Random();

  static const _headers = {
    'content-type': 'application/json',
    'accept': 'application/json',
  };

  Uri _url(String path, [Map<String, String>? query]) => baseUrl.replace(
    path: '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}$path',
    queryParameters: query,
  );

  @override
  Future<LicenceResponse> register({
    required String deviceHash,
    required String platform,
    required String appVersion,
  }) async => _licence(
    await _send(
      () => _client.post(
        _url('/v1/devices/register'),
        headers: _headers,
        body: jsonEncode({
          'deviceId': deviceHash,
          'platform': platform,
          'appVersion': appVersion,
        }),
      ),
      idempotent: true,
    ),
  );

  @override
  Future<LicenceResponse> entitlement(String deviceHash) async => _licence(
    await _send(
      () => _client.get(
        _url('/v1/entitlement', {'deviceId': deviceHash}),
        headers: _headers,
      ),
      idempotent: true,
    ),
  );

  @override
  Future<ServerPricing> config() async {
    final json = await _send(
      () => _client.get(_url('/v1/config'), headers: _headers),
      idempotent: true,
    );
    return ServerPricing.fromJson(json) ?? (throw _invalid);
  }

  @override
  Future<CheckoutResponse> checkout({
    required String deviceHash,
    required CheckoutProduct product,
    int? days,
  }) async {
    final json = await _send(
      () => _client.post(
        _url('/v1/checkout'),
        headers: _headers,
        body: jsonEncode({
          'deviceId': deviceHash,
          'product': product.name,
          'days': ?days,
        }),
      ),
      idempotent: false,
    );
    final session = json['sessionId'];
    final url = json['checkoutUrl'];
    final amount = json['amountCents'];
    final currency = json['currency'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (session is! String ||
        uri == null ||
        uri.scheme != 'https' ||
        amount is! int ||
        currency is! String) {
      throw _invalid;
    }
    return CheckoutResponse(
      sessionId: session,
      checkoutUrl: uri,
      amountCents: amount,
      currency: currency,
    );
  }

  @override
  Future<Uri> portal(String deviceHash) async {
    final json = await _send(
      () => _client.post(
        _url('/v1/portal'),
        headers: _headers,
        body: jsonEncode({'deviceId': deviceHash}),
      ),
      idempotent: false,
    );
    final raw = json['portalUrl'];
    final uri = raw is String ? Uri.tryParse(raw) : null;
    if (uri == null || uri.scheme != 'https') throw _invalid;
    return uri;
  }

  static const _invalid = LicenceClientException(
    LicenceFailureKind.invalidResponse,
  );

  LicenceResponse _licence(Map<String, Object?> json) {
    final token = json['token'];
    final time = json['serverTime'];
    if (token is! String || token.isEmpty || time is! int || time <= 0) {
      throw _invalid;
    }
    return LicenceResponse(
      token: token,
      serverTime: DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true),
      pricing: ServerPricing.fromJson(json['pricing']),
    );
  }

  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() request, {
    required bool idempotent,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return _decode(await request().timeout(timeout));
      } on LicenceClientException catch (e) {
        final retryable =
            idempotent &&
            (e.kind == LicenceFailureKind.offline ||
                e.kind == LicenceFailureKind.server);
        if (!retryable || attempt >= retries) rethrow;
      } on Object {
        // Socket, TLS, DNS errors and timeouts all mean "offline" here.
        if (!idempotent || attempt >= retries) {
          throw const LicenceClientException(LicenceFailureKind.offline);
        }
      }
      final wait = backoff * pow(2, attempt);
      await _sleep(wait + Duration(milliseconds: _jitter.nextInt(250)));
      attempt++;
    }
  }

  Map<String, Object?> _decode(http.Response r) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (json is Map<String, Object?>) return json;
      throw _invalid;
    }
    String? code;
    String? message;
    if (json is Map<String, Object?> && json['error'] is Map) {
      final error = json['error']! as Map;
      code = error['code'] is String ? error['code'] as String : null;
      message = error['message'] is String ? error['message'] as String : null;
    }
    final kind = switch (r.statusCode) {
      404 when code == 'device_not_registered' =>
        LicenceFailureKind.notRegistered,
      429 => LicenceFailureKind.rateLimited,
      >= 500 => LicenceFailureKind.server,
      >= 400 => LicenceFailureKind.rejected,
      _ => LicenceFailureKind.invalidResponse,
    };
    throw LicenceClientException(kind, code: code, message: message);
  }
}

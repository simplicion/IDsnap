import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:engine_license/engine_license.dart';
import 'package:license_server/src/rate_limiter.dart';
import 'package:license_server/src/service.dart';
import 'package:shelf/shelf.dart';

const _maxApiBody = 4 * 1024;
const _maxWebhookBody = 256 * 1024;

const _baseHeaders = {
  'cache-control': 'no-store',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
};

const _jsonHeaders = {
  ..._baseHeaders,
  'content-type': 'application/json; charset=utf-8',
};

Response _json(int status, Object? body, {Map<String, String>? headers}) =>
    Response(
      status,
      body: jsonEncode(body),
      headers: {..._jsonHeaders, ...?headers},
    );

Response _error(ApiException e) => _json(
  e.status,
  {
    'error': {'code': e.code, 'message': e.message},
  },
  headers: {
    if (e.retryAfter != null)
      'retry-after': '${e.retryAfter!.inSeconds.clamp(1, 86400)}',
  },
);

ApiException _limited(Duration wait) => ApiException(
  429,
  'rate_limited',
  'Too many requests. Try again shortly.',
  retryAfter: wait,
);

/// The HTTP surface:
///
/// - `POST /v1/devices/register`  {deviceId, platform, appVersion}
/// - `GET  /v1/entitlement?deviceId=…`
/// - `GET  /v1/config`
/// - `POST /v1/checkout`          {deviceId, product, days?}
/// - `POST /v1/portal`            {deviceId}
/// - `GET  /v1/checkout/return`   (static page the gateway redirects to)
/// - `POST /webhooks/180-pay`
/// - `GET  /healthz`
///
/// JSON in, JSON out, strict validation, per-IP and per-device limits.
/// [trustProxy]: take the client address from the last `X-Forwarded-For`
/// entry (exactly one trusted reverse proxy in front).
Handler buildHandler(
  LicenceService service, {
  RateLimits? limits,
  bool trustProxy = false,
}) {
  final rate = limits ?? RateLimits();

  String clientIp(Request request) {
    if (trustProxy) {
      final forwarded = request.headers['x-forwarded-for'];
      if (forwarded != null && forwarded.trim().isNotEmpty) {
        return forwarded.split(',').last.trim();
      }
    }
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
  }

  void limitDevice(Object? deviceId) {
    if (deviceId is! String || !isDeviceHash(deviceId)) return;
    final wait = rate.device.check(deviceId);
    if (wait != null) throw _limited(wait);
  }

  Future<Response> api(Request request) async {
    final ip = clientIp(request);
    final wait = rate.ip.check(ip);
    if (wait != null) throw _limited(wait);

    final path = request.url.path;
    final method = request.method;
    switch ((method, path)) {
      case ('GET', 'v1/config'):
        return _json(200, {
          ...service.pricing(),
          'serverTime': service.serverTime,
        });
      case ('GET', 'v1/entitlement'):
        final query = request.url.queryParameters;
        if (query.length != 1 || !query.containsKey('deviceId')) {
          throw const ApiException(
            400,
            'invalid_request',
            'Expected exactly one query parameter: deviceId.',
          );
        }
        limitDevice(query['deviceId']);
        return _json(200, await service.entitlement(query['deviceId']));
      case ('POST', 'v1/devices/register'):
        final body = await _readObject(request, const {
          'deviceId',
          'platform',
          'appVersion',
        });
        limitDevice(body['deviceId']);
        return _json(
          200,
          await service.register(
            deviceId: body['deviceId'],
            platform: body['platform'],
            appVersion: body['appVersion'],
            allowNewDevice: () => rate.newDevice.check(ip) == null,
          ),
        );
      case ('POST', 'v1/checkout'):
        final body = await _readObject(request, const {
          'deviceId',
          'product',
          'days',
        });
        limitDevice(body['deviceId']);
        final deviceId = body['deviceId'];
        if (deviceId is String && isDeviceHash(deviceId)) {
          final wait = rate.checkout.check(deviceId);
          if (wait != null) throw _limited(wait);
        }
        return _json(
          200,
          await service.checkout(
            deviceId: deviceId,
            product: body['product'],
            days: body['days'],
          ),
        );
      case ('POST', 'v1/portal'):
        final body = await _readObject(request, const {'deviceId'});
        limitDevice(body['deviceId']);
        final deviceId = body['deviceId'];
        if (deviceId is String && isDeviceHash(deviceId)) {
          final wait = rate.checkout.check(deviceId);
          if (wait != null) throw _limited(wait);
        }
        return _json(200, await service.portal(deviceId));
      case ('GET', 'v1/checkout/return'):
        return Response.ok(
          _returnPage,
          headers: {
            ..._baseHeaders,
            'content-type': 'text/html; charset=utf-8',
            'content-security-policy':
                "default-src 'none'; style-src 'unsafe-inline'",
          },
        );
    }
    throw const ApiException(404, 'not_found', 'No such endpoint.');
  }

  Future<Response> webhook(Request request) async {
    final wait = rate.webhook.check(clientIp(request));
    if (wait != null) throw _limited(wait);
    // The signature covers the bytes exactly as sent: read them raw and
    // never re-serialise.
    final raw = await _readBytes(request, _maxWebhookBody);
    final result = service.webhook(headers: request.headers, rawBody: raw);
    return _json(
      result.status,
      result.status == 200
          ? {'received': true, 'outcome': result.outcome}
          : {
              'error': {'code': result.outcome},
            },
    );
  }

  return (Request request) async {
    try {
      final path = request.url.path;
      if (path == 'healthz' && request.method == 'GET') {
        return _json(200, {'ok': true});
      }
      if (path == 'webhooks/180-pay') {
        if (request.method != 'POST') {
          throw const ApiException(405, 'method_not_allowed', 'Use POST.');
        }
        return await webhook(request);
      }
      if (path.startsWith('v1/')) return await api(request);
      throw const ApiException(404, 'not_found', 'No such endpoint.');
    } on ApiException catch (e) {
      return _error(e);
    } on Object {
      // Never leak internals.
      return _error(
        const ApiException(500, 'internal_error', 'Something went wrong.'),
      );
    }
  };
}

Future<Uint8List> _readBytes(Request request, int limit) async {
  final declared = request.contentLength;
  if (declared != null && declared > limit) {
    throw const ApiException(413, 'body_too_large', 'Request body too large.');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
    if (builder.length > limit) {
      throw const ApiException(
        413,
        'body_too_large',
        'Request body too large.',
      );
    }
  }
  return builder.takeBytes();
}

/// Reads a JSON object and rejects unknown keys.
Future<Map<String, Object?>> _readObject(
  Request request,
  Set<String> allowed,
) async {
  final type = request.headers['content-type'] ?? '';
  if (!type.toLowerCase().startsWith('application/json')) {
    throw const ApiException(
      415,
      'unsupported_media_type',
      'Send application/json.',
    );
  }
  final bytes = await _readBytes(request, _maxApiBody);
  Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    json = null;
  }
  if (json is! Map<String, Object?>) {
    throw const ApiException(400, 'invalid_json', 'Send a JSON object.');
  }
  final unknown = json.keys.where((k) => !allowed.contains(k));
  if (unknown.isNotEmpty) {
    throw const ApiException(
      400,
      'invalid_request',
      'Unknown field in request body.',
    );
  }
  return json;
}

const _returnPage = '''
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Return to IDSnap</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; margin: 15vh auto; max-width: 28rem; padding: 0 1.5rem; color: #1a1c1e; }
  h1 { font-size: 1.4rem; }
</style>
<h1>You can go back to IDSnap now</h1>
<p>Open the IDSnap app. If you paid, it unlocks within a minute while your phone is online. If it doesn't, tap <b>Refresh licence</b> in Settings &rsaquo; Subscription.</p>
<p>You can close this page.</p>
</html>
''';

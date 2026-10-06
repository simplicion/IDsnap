import 'package:engine_codes/src/content.dart';
import 'package:engine_codes/src/parsers/key_values.dart';
import 'package:engine_codes/src/text_utils.dart';

/// `WIFI:S:<ssid>;T:<WPA|WEP|SAE|nopass|WPA2-EAP>;P:<password>;H:<true>;;`
WifiContent? parseWifi(String raw) {
  final body = stripPrefixIgnoreCase(raw.trim(), 'WIFI:');
  if (body == null) return null;
  final fields = parseKeyValues(body);
  String? get(String key) =>
      fields.where((f) => f.key == key).firstOrNull?.value;

  final ssid = get('S');
  if (ssid == null) return null;
  final type = (get('T') ?? '').trim().toUpperCase();
  final password = get('P');
  final eap = cleanOrNull(get('E'));
  final security = switch (type) {
    'WEP' => WifiSecurity.wep,
    'NOPASS' || 'NONE' || 'OPEN' => WifiSecurity.open,
    '' =>
      (password == null || password.isEmpty)
          ? WifiSecurity.open
          : WifiSecurity.wpa,
    _ when type.contains('EAP') || eap != null => WifiSecurity.enterprise,
    _ => WifiSecurity.wpa,
  };
  final hidden = (get('H') ?? '').trim().toLowerCase();
  return WifiContent(
    raw,
    ssid: ssid,
    security: security,
    password: security == WifiSecurity.open
        ? null
        : cleanOrNull(password) == null
        ? null
        : password,
    hidden: hidden == 'true' || hidden == '1' || hidden == 'yes',
    eapMethod: eap,
    identity: cleanOrNull(get('I')),
    phase2: cleanOrNull(get('PH2')),
  );
}

final _emailAddress = RegExp(
  r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$",
);

bool isEmailAddress(String s) => _emailAddress.hasMatch(s.trim());

List<String> _addresses(String s) => s
    .split(RegExp('[,;]'))
    .map((a) => safeDecodeComponent(a).trim())
    .where((a) => a.isNotEmpty)
    .toList();

/// `mailto:` (RFC 6068), `MATMSG:TO:..;SUB:..;BODY:..;;` and
/// `SMTP:to:subject:body`, plus a bare address.
EmailContent? parseEmail(String raw) {
  final t = raw.trim();
  final mailto = stripPrefixIgnoreCase(t, 'mailto:');
  if (mailto != null) {
    final q = mailto.indexOf('?');
    final to = _addresses(q < 0 ? mailto : mailto.substring(0, q));
    final params = q < 0
        ? <String, String>{}
        : parseQuery(mailto.substring(q + 1));
    return EmailContent(
      raw,
      to: [...to, ...?params['to'].let(_addresses)],
      cc: params['cc'].let(_addresses) ?? const [],
      bcc: params['bcc'].let(_addresses) ?? const [],
      subject: cleanOrNull(params['subject']),
      body: cleanOrNull(params['body']),
    );
  }
  final matmsg = stripPrefixIgnoreCase(t, 'MATMSG:');
  if (matmsg != null) {
    final fields = parseKeyValues(matmsg);
    String? get(String k) =>
        cleanOrNull(fields.where((f) => f.key == k).firstOrNull?.value);
    return EmailContent(
      raw,
      to: get('TO').let(_addresses) ?? const [],
      subject: get('SUB'),
      body: get('BODY'),
    );
  }
  final smtp = stripPrefixIgnoreCase(t, 'SMTP:');
  if (smtp != null) {
    final parts = smtp.split(':');
    return EmailContent(
      raw,
      to: _addresses(parts.first),
      subject: parts.length > 1 ? cleanOrNull(parts[1]) : null,
      body: parts.length > 2 ? cleanOrNull(parts.sublist(2).join(':')) : null,
    );
  }
  if (isEmailAddress(t)) return EmailContent(raw, to: [t]);
  return null;
}

/// `tel:+1-555-0100`.
PhoneContent? parsePhone(String raw) {
  final body = stripPrefixIgnoreCase(raw.trim(), 'tel:');
  if (body == null) return null;
  final number = cleanOrNull(safeDecodeComponent(body.split(';').first));
  if (number == null || !RegExp(r'\d').hasMatch(number)) return null;
  return PhoneContent(raw, number: number);
}

/// `SMSTO:number:body`, `MMSTO:`, and `sms:number1,number2?body=..`
/// (RFC 5724).
SmsContent? parseSms(String raw) {
  final t = raw.trim();
  final smsto =
      stripPrefixIgnoreCase(t, 'smsto:') ?? stripPrefixIgnoreCase(t, 'mmsto:');
  if (smsto != null) {
    final colon = smsto.indexOf(':');
    final numbers = colon < 0 ? smsto : smsto.substring(0, colon);
    final body = colon < 0 ? null : smsto.substring(colon + 1);
    return SmsContent(raw, numbers: _numbers(numbers), body: cleanOrNull(body));
  }
  final sms =
      stripPrefixIgnoreCase(t, 'sms:') ?? stripPrefixIgnoreCase(t, 'mms:');
  if (sms != null) {
    final q = sms.indexOf('?');
    final head = q < 0 ? sms : sms.substring(0, q);
    final params = q < 0
        ? <String, String>{}
        : parseQuery(sms.substring(q + 1));
    return SmsContent(
      raw,
      numbers: _numbers(head.split(';').first),
      body: cleanOrNull(params['body']),
    );
  }
  return null;
}

List<String> _numbers(String s) => s
    .split(',')
    .map((n) => safeDecodeComponent(n).trim())
    .where((n) => n.isNotEmpty)
    .toList();

/// `geo:lat,lng[,alt][;crs=..;u=..][?q=..]` (RFC 5870, plus the common
/// `?q=` search extension).
GeoContent? parseGeo(String raw) {
  final body = stripPrefixIgnoreCase(raw.trim(), 'geo:');
  if (body == null) return null;
  final q = body.indexOf('?');
  final head = (q < 0 ? body : body.substring(0, q)).split(';').first;
  final params = q < 0
      ? <String, String>{}
      : parseQuery(body.substring(q + 1), plusAsSpace: true);
  final numbers = head
      .split(',')
      .map((s) => double.tryParse(s.trim()))
      .toList();
  double? lat;
  double? lng;
  double? alt;
  if (numbers.length >= 2 && numbers[0] != null && numbers[1] != null) {
    lat = numbers[0];
    lng = numbers[1];
    if (lat!.abs() > 90 || lng!.abs() > 180 || !lat.isFinite || !lng.isFinite) {
      return null;
    }
    if (numbers.length > 2) alt = numbers[2];
  } else if (head.trim().isNotEmpty) {
    return null;
  }
  var query = cleanOrNull(params['q']);
  // A `q` that only repeats the coordinates adds nothing.
  if (query != null && lat != null && RegExp(r'^[-\d.,\s]+$').hasMatch(query)) {
    query = null;
  }
  // `geo:0,0?q=Some place` means "search only".
  if (lat == 0 && lng == 0 && query != null) {
    lat = null;
    lng = null;
  }
  if (lat == null && query == null) return null;
  return GeoContent(
    raw,
    latitude: lat,
    longitude: lng,
    altitude: alt,
    query: query,
  );
}

/// `otpauth://totp/Issuer:account?secret=..&issuer=..`. The secret itself is
/// not kept; the Authenticator re-parses the raw URI.
OtpAuthContent? parseOtpAuth(String raw) {
  final t = raw.trim();
  final rest = stripPrefixIgnoreCase(t, 'otpauth://');
  if (rest == null) return null;
  final slash = rest.indexOf('/');
  if (slash < 0) return null;
  final type = rest.substring(0, slash).toLowerCase();
  if (type != 'totp' && type != 'hotp') return null;
  final afterType = rest.substring(slash + 1);
  final q = afterType.indexOf('?');
  final label = safeDecodeComponent(
    q < 0 ? afterType : afterType.substring(0, q),
  );
  final params = q < 0
      ? <String, String>{}
      : parseQuery(afterType.substring(q + 1));
  var issuer = cleanOrNull(params['issuer']);
  var account = cleanOrNull(label);
  final colon = label.indexOf(':');
  if (colon >= 0) {
    issuer ??= cleanOrNull(label.substring(0, colon));
    account = cleanOrNull(label.substring(colon + 1));
  }
  return OtpAuthContent(
    raw,
    counterBased: type == 'hotp',
    hasSecret: cleanOrNull(params['secret']) != null,
    issuer: issuer,
    account: account,
    digits: int.tryParse(params['digits'] ?? ''),
    period: int.tryParse(params['period'] ?? ''),
    algorithm: cleanOrNull(params['algorithm'])?.toUpperCase(),
  );
}

/// http(s) links, `www.` addresses, `URLTO:` and `MEBKM:TITLE:..;URL:..;;`.
UrlContent? parseUrl(String raw) {
  final t = raw.trim();
  final mebkm = stripPrefixIgnoreCase(t, 'MEBKM:');
  if (mebkm != null) {
    final fields = parseKeyValues(mebkm);
    String? get(String k) =>
        cleanOrNull(fields.where((f) => f.key == k).firstOrNull?.value);
    final url = get('URL');
    if (url == null) return null;
    return UrlContent(raw, url: _withScheme(url), linkText: get('TITLE'));
  }
  final urlto = stripPrefixIgnoreCase(t, 'URLTO:');
  if (urlto != null) {
    final c = urlto.indexOf(':');
    final title = c < 0 ? null : cleanOrNull(urlto.substring(0, c));
    final url = cleanOrNull(c < 0 ? urlto : urlto.substring(c + 1));
    if (url == null) return null;
    return UrlContent(raw, url: _withScheme(url), linkText: title);
  }
  if (t.contains(RegExp(r'\s'))) return null;
  final lower = t.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return UrlContent(raw, url: t);
  }
  if (lower.startsWith('www.') &&
      t.length > 4 &&
      t.substring(4).contains('.')) {
    return UrlContent(raw, url: 'https://$t');
  }
  return null;
}

String _withScheme(String url) {
  final lower = url.toLowerCase();
  if (RegExp('^[a-z][a-z0-9+.-]*:').hasMatch(lower)) return url;
  return 'https://$url';
}

extension _Let<T extends Object> on T? {
  R? let<R>(R Function(T) f) {
    final self = this;
    return self == null ? null : f(self);
  }
}

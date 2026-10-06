import 'package:engine_codes/src/content.dart';
import 'package:engine_codes/src/parsers/content_lines.dart';
import 'package:engine_codes/src/parsers/key_values.dart';
import 'package:engine_codes/src/text_utils.dart';

/// vCard 2.1 / 3.0 / 4.0. Returns null when nothing usable is found.
ContactContent? parseVCard(String raw) {
  final lines = parseContentLines(raw);
  String? version;
  String? fn;
  List<String>? n;
  String? nickname;
  String? org;
  String? title;
  String? note;
  String? bday;
  final phones = <LabeledValue>[];
  final emails = <LabeledValue>[];
  final urls = <LabeledValue>[];
  final addresses = <LabeledValue>[];

  var inCard = false;
  for (final line in lines) {
    if (line.name == 'BEGIN' && line.rawValue.trim().toUpperCase() == 'VCARD') {
      inCard = true;
      continue;
    }
    if (line.name == 'END' && line.rawValue.trim().toUpperCase() == 'VCARD') {
      // Only the first card of a multi-card code is shown.
      break;
    }
    if (!inCard || line.isBinary) continue;
    final value = cleanOrNull(line.value);
    switch (line.name) {
      case 'VERSION':
        version = value;
      case 'FN':
        fn ??= value;
      case 'N':
        n ??= line.components;
      case 'NICKNAME':
        nickname ??= value;
      case 'ORG':
        final parts = line.components.where((c) => c.isNotEmpty).toList();
        if (parts.isNotEmpty) org ??= parts.join(', ');
      case 'TITLE':
        title ??= value;
      case 'NOTE':
        note ??= value;
      case 'BDAY':
        bday ??= value;
      case 'TEL':
        final number = _stripUriScheme(value, 'tel:');
        if (number != null) {
          phones.add(LabeledValue(number, type: _phoneType(line.types)));
        }
      case 'EMAIL':
        final email = _stripUriScheme(value, 'mailto:');
        if (email != null) {
          emails.add(LabeledValue(email, type: _placeType(line.types)));
        }
      case 'URL':
        if (value != null) urls.add(LabeledValue(value));
      case 'ADR':
        final address = _formatAddress(line.components);
        if (address != null) {
          addresses.add(LabeledValue(address, type: _placeType(line.types)));
        }
    }
  }

  String? part(int i) => n != null && n.length > i ? cleanOrNull(n[i]) : null;
  final card = ContactCard(
    formattedName: fn,
    familyName: part(0),
    givenName: part(1),
    additionalNames: part(2),
    prefix: part(3),
    suffix: part(4),
    nickname: nickname,
    organization: org,
    jobTitle: title,
    phones: phones,
    emails: emails,
    urls: urls,
    addresses: addresses,
    note: note,
    birthday: bday,
  );
  if (card.isEmpty) return null;
  return ContactContent(
    raw,
    card: card,
    format: ContactFormat.vcard,
    version: version,
  );
}

/// `MECARD:N:Doe,John;TEL:+1555;EMAIL:j@x.com;;` (fields in any order).
ContactContent? parseMecard(String raw) {
  final body = stripPrefixIgnoreCase(raw.trim(), 'MECARD:');
  if (body == null) return null;
  final fields = parseKeyValues(body);
  String? first(String key) =>
      cleanOrNull(fields.where((f) => f.key == key).firstOrNull?.value);
  List<String> all(String key) => [
    for (final f in fields)
      if (f.key == key && f.value.trim().isNotEmpty) f.value.trim(),
  ];

  String? family;
  String? given;
  final name = first('N');
  if (name != null) {
    // "Family,Given" (the comma may be escaped or not).
    final parts = name.split(',');
    family = cleanOrNull(parts.first);
    if (parts.length > 1) given = cleanOrNull(parts.sublist(1).join(','));
  }
  final card = ContactCard(
    formattedName: family != null && given != null
        ? '$given $family'
        : (family ?? given),
    familyName: family,
    givenName: given,
    nickname: first('NICKNAME'),
    organization: first('ORG'),
    jobTitle: first('TITLE'),
    phones: [
      for (final t in all('TEL')) LabeledValue(t),
      for (final t in all('TEL-AV')) LabeledValue(t, type: 'Video'),
    ],
    emails: [for (final e in all('EMAIL')) LabeledValue(e)],
    urls: [for (final u in all('URL')) LabeledValue(u)],
    addresses: [
      for (final a in all('ADR'))
        LabeledValue(
          a
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .join(', '),
        ),
    ],
    note: first('NOTE') ?? first('MEMO'),
    birthday: _formatCompactDate(first('BDAY')),
  );
  if (card.isEmpty) return null;
  return ContactContent(raw, card: card, format: ContactFormat.mecard);
}

String? _stripUriScheme(String? value, String scheme) {
  if (value == null) return null;
  return cleanOrNull(stripPrefixIgnoreCase(value, scheme) ?? value);
}

String? _phoneType(Set<String> types) {
  if (types.contains('CELL') || types.contains('MOBILE')) return 'Mobile';
  if (types.contains('FAX')) return 'Fax';
  if (types.contains('PAGER')) return 'Pager';
  return _placeType(types);
}

String? _placeType(Set<String> types) {
  if (types.contains('WORK')) return 'Work';
  if (types.contains('HOME')) return 'Home';
  return null;
}

/// ADR: PO box; extended; street; locality; region; postal code; country.
String? _formatAddress(List<String> c) {
  String at(int i) => c.length > i ? c[i].trim() : '';
  final street = [at(0), at(1), at(2)].where((s) => s.isNotEmpty).join(', ');
  final city = [at(3), at(4), at(5)].where((s) => s.isNotEmpty).join(' ');
  final lines = [street, city, at(6)].where((s) => s.isNotEmpty).toList();
  // Extra components (malformed ADR) are appended rather than dropped.
  if (c.length > 7) {
    lines.addAll(c.skip(7).map((s) => s.trim()).where((s) => s.isNotEmpty));
  }
  return lines.isEmpty ? null : lines.join('\n');
}

/// MECARD BDAY is `YYYYMMDD`; shown as `YYYY-MM-DD` when it parses.
String? _formatCompactDate(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
  if (m == null) return value;
  return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
}

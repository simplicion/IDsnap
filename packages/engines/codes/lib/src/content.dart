import 'package:engine_codes/src/symbology.dart';
import 'package:engine_codes/src/text_utils.dart';
import 'package:engine_codes/src/url_safety.dart';
import 'package:meta/meta.dart';

/// One labelled value shown on the result screen and copied/shared.
@immutable
class CodeField {
  const CodeField(this.label, this.value, {this.secret = false});

  final String label;
  final String value;

  /// Hidden until revealed (passwords).
  final bool secret;

  @override
  bool operator ==(Object other) =>
      other is CodeField &&
      other.label == label &&
      other.value == value &&
      other.secret == secret;

  @override
  int get hashCode => Object.hash(label, value, secret);

  @override
  String toString() => secret ? '$label: ••••' : '$label: $value';
}

/// What a code contains. Labels are generic terms.
enum CodeKind {
  text('Text'),
  url('Link'),
  wifi('Wi-Fi network'),
  contact('Contact'),
  email('Email'),
  phone('Phone number'),
  sms('Text message'),
  geo('Location'),
  event('Calendar event'),
  otpAuth('Two-step verification key'),
  payment('Payment request'),
  product('Product barcode'),
  idCard('ID card barcode');

  const CodeKind(this.label);
  final String label;

  static CodeKind byName(String? name) => CodeKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => CodeKind.text,
  );
}

/// A parsed code. Never executes anything: actions are offered by the UI.
@immutable
sealed class CodeContent {
  const CodeContent(this.raw);

  /// The payload exactly as scanned.
  final String raw;

  CodeKind get kind;

  /// Heading on the result screen.
  String get title => kind.label;

  /// One line for lists (history).
  String get summary;

  List<CodeField> get fields;

  /// Passwords, payment details, identity data, sign-in keys. Not stored in
  /// scan history unless the user opts in.
  bool get isSensitive => false;

  /// Never stored in history, even when sensitive items are allowed.
  bool get neverStore => false;

  /// Title and fields as text, for copy / share / save as a note.
  String toPlainText() {
    final b = StringBuffer(title);
    for (final f in fields) {
      b.write('\n${f.label}: ${f.value}');
    }
    return b.toString();
  }
}

final class TextContent extends CodeContent {
  const TextContent(super.raw);

  @override
  CodeKind get kind => CodeKind.text;

  @override
  String get summary => _oneLine(raw);

  @override
  List<CodeField> get fields => [CodeField('Text', raw)];

  @override
  String toPlainText() => raw;
}

final class UrlContent extends CodeContent {
  UrlContent(super.raw, {required this.url, this.linkText})
    : safety = UrlSafety.assess(url, linkText: linkText);

  /// Full link, with `https://` added when the code omitted the scheme.
  final String url;

  /// A label that came with the link (bookmark title).
  final String? linkText;
  final UrlSafetyReport safety;

  /// Only http(s) links may be opened.
  bool get canOpen =>
      !safety.warnings.contains(UrlWarning.dangerousScheme) &&
      !safety.warnings.contains(UrlWarning.malformed);

  @override
  CodeKind get kind => CodeKind.url;

  @override
  String get summary => url;

  @override
  List<CodeField> get fields => [
    if (linkText != null) CodeField('Title', linkText!),
    CodeField('Link', url),
    if (safety.host != null) CodeField('Site', safety.host!),
  ];
}

enum WifiSecurity {
  wpa('WPA/WPA2/WPA3'),
  wep('WEP'),
  enterprise('WPA2/WPA3 Enterprise'),
  open('None (open network)');

  const WifiSecurity(this.label);
  final String label;

  /// The `T:` value used in generated codes.
  String get code => switch (this) {
    WifiSecurity.wpa => 'WPA',
    WifiSecurity.wep => 'WEP',
    WifiSecurity.enterprise => 'WPA2-EAP',
    WifiSecurity.open => 'nopass',
  };
}

final class WifiContent extends CodeContent {
  const WifiContent(
    super.raw, {
    required this.ssid,
    required this.security,
    this.password,
    this.hidden = false,
    this.eapMethod,
    this.identity,
    this.phase2,
  });

  final String ssid;
  final WifiSecurity security;
  final String? password;
  final bool hidden;
  final String? eapMethod;
  final String? identity;
  final String? phase2;

  @override
  CodeKind get kind => CodeKind.wifi;

  @override
  String get summary => ssid.isEmpty ? 'Wi-Fi network' : ssid;

  @override
  bool get isSensitive => password != null && password!.isNotEmpty;

  @override
  List<CodeField> get fields => [
    CodeField('Network name', ssid),
    CodeField('Security', security.label),
    if (password != null && password!.isNotEmpty)
      CodeField('Password', password!, secret: true),
    if (hidden) const CodeField('Hidden network', 'Yes'),
    if (eapMethod != null) CodeField('EAP method', eapMethod!),
    if (identity != null) CodeField('Identity', identity!),
    if (phase2 != null) CodeField('Phase 2 method', phase2!),
  ];
}

/// A phone number, email, address or link with its type ("Work").
@immutable
class LabeledValue {
  const LabeledValue(this.value, {this.type});

  final String value;

  /// Human label, e.g. "Mobile", "Work"; null when untyped.
  final String? type;

  @override
  bool operator ==(Object other) =>
      other is LabeledValue && other.value == value && other.type == type;

  @override
  int get hashCode => Object.hash(value, type);

  @override
  String toString() => type == null ? value : '$value ($type)';
}

/// Contact details from a vCard or MECARD code.
@immutable
class ContactCard {
  const ContactCard({
    this.formattedName,
    this.familyName,
    this.givenName,
    this.additionalNames,
    this.prefix,
    this.suffix,
    this.nickname,
    this.organization,
    this.jobTitle,
    this.phones = const [],
    this.emails = const [],
    this.urls = const [],
    this.addresses = const [],
    this.note,
    this.birthday,
  });

  final String? formattedName;
  final String? familyName;
  final String? givenName;
  final String? additionalNames;
  final String? prefix;
  final String? suffix;
  final String? nickname;
  final String? organization;
  final String? jobTitle;
  final List<LabeledValue> phones;
  final List<LabeledValue> emails;
  final List<LabeledValue> urls;
  final List<LabeledValue> addresses;
  final String? note;
  final String? birthday;

  /// Best available name.
  String get displayName {
    if (formattedName != null) return formattedName!;
    final composed = [
      prefix,
      givenName,
      additionalNames,
      familyName,
      suffix,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    if (composed.isNotEmpty) return composed;
    return nickname ??
        organization ??
        phones.firstOrNull?.value ??
        emails.firstOrNull?.value ??
        'Contact';
  }

  bool get isEmpty =>
      formattedName == null &&
      familyName == null &&
      givenName == null &&
      nickname == null &&
      organization == null &&
      phones.isEmpty &&
      emails.isEmpty &&
      urls.isEmpty &&
      addresses.isEmpty &&
      note == null;

  /// vCard 3.0 text (CRLF line ends), for "Add to contacts" and generation.
  String toVCard() {
    String esc(String v) => escapeBackslashes(
      v,
      ';,',
    ).replaceAll('\r\n', r'\n').replaceAll('\n', r'\n');
    String typeParam(String? type) {
      if (type == null) return '';
      final t = type.toLowerCase();
      final code = switch (t) {
        'mobile' => 'CELL',
        'work' => 'WORK',
        'home' => 'HOME',
        'fax' => 'FAX',
        _ => null,
      };
      return code == null ? '' : ';TYPE=$code';
    }

    final lines = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'N:${[familyName, givenName, additionalNames, prefix, suffix].map((v) => esc(v ?? '')).join(';')}',
      'FN:${esc(displayName)}',
      if (nickname != null) 'NICKNAME:${esc(nickname!)}',
      if (organization != null) 'ORG:${esc(organization!)}',
      if (jobTitle != null) 'TITLE:${esc(jobTitle!)}',
      for (final p in phones) 'TEL${typeParam(p.type)}:${esc(p.value)}',
      for (final e in emails) 'EMAIL${typeParam(e.type)}:${esc(e.value)}',
      for (final u in urls) 'URL:${esc(u.value)}',
      for (final a in addresses)
        'ADR${typeParam(a.type)}:;;${esc(a.value)};;;;',
      if (birthday != null) 'BDAY:${esc(birthday!)}',
      if (note != null) 'NOTE:${esc(note!)}',
      'END:VCARD',
    ];
    return '${lines.join('\r\n')}\r\n';
  }
}

enum ContactFormat {
  vcard('vCard'),
  mecard('MECARD');

  const ContactFormat(this.label);
  final String label;
}

final class ContactContent extends CodeContent {
  const ContactContent(
    super.raw, {
    required this.card,
    required this.format,
    this.version,
  });

  final ContactCard card;
  final ContactFormat format;

  /// vCard version ("2.1", "3.0", "4.0"), when stated.
  final String? version;

  @override
  CodeKind get kind => CodeKind.contact;

  @override
  String get summary => card.displayName;

  @override
  List<CodeField> get fields {
    String label(String base, LabeledValue v) =>
        v.type == null ? base : '$base (${v.type})';
    return [
      CodeField('Name', card.displayName),
      if (card.nickname != null && card.nickname != card.displayName)
        CodeField('Nickname', card.nickname!),
      if (card.organization != null && card.organization != card.displayName)
        CodeField('Organization', card.organization!),
      if (card.jobTitle != null) CodeField('Job title', card.jobTitle!),
      for (final p in card.phones) CodeField(label('Phone', p), p.value),
      for (final e in card.emails) CodeField(label('Email', e), e.value),
      for (final a in card.addresses) CodeField(label('Address', a), a.value),
      for (final u in card.urls) CodeField('Website', u.value),
      if (card.birthday != null) CodeField('Birthday', card.birthday!),
      if (card.note != null) CodeField('Note', card.note!),
    ];
  }
}

final class EmailContent extends CodeContent {
  const EmailContent(
    super.raw, {
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    this.subject,
    this.body,
  });

  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String? subject;
  final String? body;

  /// `mailto:` link that pre-fills the email app.
  String get mailtoUri {
    final params = <String>[
      if (cc.isNotEmpty) 'cc=${cc.map(Uri.encodeComponent).join(',')}',
      if (bcc.isNotEmpty) 'bcc=${bcc.map(Uri.encodeComponent).join(',')}',
      if (subject != null) 'subject=${Uri.encodeComponent(subject!)}',
      if (body != null) 'body=${Uri.encodeComponent(body!)}',
    ];
    final address = to.map(_encodeAddress).join(',');
    return 'mailto:$address${params.isEmpty ? '' : '?${params.join('&')}'}';
  }

  @override
  CodeKind get kind => CodeKind.email;

  @override
  String get summary => to.isEmpty ? (subject ?? 'Email') : to.join(', ');

  @override
  List<CodeField> get fields => [
    if (to.isNotEmpty) CodeField('To', to.join(', ')),
    if (cc.isNotEmpty) CodeField('Cc', cc.join(', ')),
    if (bcc.isNotEmpty) CodeField('Bcc', bcc.join(', ')),
    if (subject != null) CodeField('Subject', subject!),
    if (body != null) CodeField('Message', body!),
  ];
}

String _encodeAddress(String address) =>
    Uri.encodeComponent(address).replaceAll('%40', '@');

final class PhoneContent extends CodeContent {
  const PhoneContent(super.raw, {required this.number});

  final String number;

  String get telUri => 'tel:${_dialable(number)}';

  @override
  CodeKind get kind => CodeKind.phone;

  @override
  String get summary => number;

  @override
  List<CodeField> get fields => [CodeField('Phone number', number)];
}

String _dialable(String number) =>
    number.replaceAll(RegExp('[^0-9+*#,;pPwW]'), '');

final class SmsContent extends CodeContent {
  const SmsContent(super.raw, {required this.numbers, this.body});

  final List<String> numbers;
  final String? body;

  /// `sms:` link (RFC 5724) that pre-fills the messaging app.
  String get smsUri {
    final to = numbers.map(_dialable).join(',');
    return body == null || body!.isEmpty
        ? 'sms:$to'
        : 'sms:$to?body=${Uri.encodeComponent(body!)}';
  }

  @override
  CodeKind get kind => CodeKind.sms;

  @override
  String get summary => numbers.isEmpty ? 'Text message' : numbers.join(', ');

  @override
  List<CodeField> get fields => [
    if (numbers.isNotEmpty) CodeField('To', numbers.join(', ')),
    if (body != null && body!.isNotEmpty) CodeField('Message', body!),
  ];
}

final class GeoContent extends CodeContent {
  const GeoContent(
    super.raw, {
    this.latitude,
    this.longitude,
    this.altitude,
    this.query,
  });

  final double? latitude;
  final double? longitude;
  final double? altitude;

  /// A place name or address to search for.
  final String? query;

  bool get hasPoint => latitude != null && longitude != null;

  String get coordinates =>
      hasPoint ? '${_fmt(latitude!)}, ${_fmt(longitude!)}' : '';

  static String _fmt(double v) {
    final s = v.toStringAsFixed(6);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  /// `geo:` link for the maps app (Android and most platforms).
  String get geoUri {
    final q = query == null ? null : Uri.encodeComponent(query!);
    if (hasPoint) {
      final point = '${_fmt(latitude!)},${_fmt(longitude!)}';
      return q == null ? 'geo:$point?q=$point' : 'geo:$point?q=$q';
    }
    return 'geo:0,0?q=${q ?? ''}';
  }

  /// Apple Maps link (opens the Maps app on iOS).
  String get appleMapsUri {
    final params = <String>[
      if (hasPoint) 'll=${_fmt(latitude!)},${_fmt(longitude!)}',
      if (query != null) 'q=${Uri.encodeComponent(query!)}',
    ];
    return 'https://maps.apple.com/?${params.join('&')}';
  }

  @override
  CodeKind get kind => CodeKind.geo;

  @override
  String get summary => query ?? coordinates;

  @override
  List<CodeField> get fields => [
    if (hasPoint) CodeField('Coordinates', coordinates),
    if (altitude != null) CodeField('Altitude', '${_fmt(altitude!)} m'),
    if (query != null) CodeField('Place', query!),
  ];
}

/// A calendar date/time from an iCalendar value.
@immutable
class EventTime {
  const EventTime(
    this.value, {
    this.allDay = false,
    this.utc = false,
    this.tzid,
  });

  /// Wall-clock fields as written (UTC when [utc]).
  final DateTime value;
  final bool allDay;
  final bool utc;

  /// Time zone name from `TZID=`, shown next to the time.
  final String? tzid;

  String format() {
    final d =
        '${value.year.toString().padLeft(4, '0')}-${twoDigits(value.month)}'
        '-${twoDigits(value.day)}';
    if (allDay) return d;
    final t = '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
    final zone = utc ? ' UTC' : (tzid == null ? '' : ' ($tzid)');
    return '$d $t$zone';
  }

  @override
  bool operator ==(Object other) =>
      other is EventTime &&
      other.value == value &&
      other.allDay == allDay &&
      other.utc == utc &&
      other.tzid == tzid;

  @override
  int get hashCode => Object.hash(value, allDay, utc, tzid);
}

final class EventContent extends CodeContent {
  const EventContent(
    super.raw, {
    required this.eventBlock,
    this.summaryText,
    this.start,
    this.end,
    this.location,
    this.description,
    this.organizer,
    this.url,
  });

  /// The `BEGIN:VEVENT` … `END:VEVENT` lines, unfolded, for export.
  final List<String> eventBlock;
  final String? summaryText;
  final EventTime? start;
  final EventTime? end;
  final String? location;
  final String? description;
  final String? organizer;
  final String? url;

  /// A complete `.ics` calendar file (CRLF line ends) with this event.
  String toIcs() {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//IDSnap//Offline QR//EN',
      ...eventBlock,
      'END:VCALENDAR',
    ];
    return '${lines.join('\r\n')}\r\n';
  }

  @override
  CodeKind get kind => CodeKind.event;

  @override
  String get summary => summaryText ?? start?.format() ?? 'Calendar event';

  @override
  List<CodeField> get fields => [
    if (summaryText != null) CodeField('Event', summaryText!),
    if (start != null) CodeField('Starts', start!.format()),
    if (end != null) CodeField('Ends', end!.format()),
    if (location != null) CodeField('Location', location!),
    if (organizer != null) CodeField('Organizer', organizer!),
    if (url != null) CodeField('Link', url!),
    if (description != null) CodeField('Description', description!),
  ];
}

final class OtpAuthContent extends CodeContent {
  const OtpAuthContent(
    super.raw, {
    required this.counterBased,
    required this.hasSecret,
    this.issuer,
    this.account,
    this.digits,
    this.period,
    this.algorithm,
  });

  final bool counterBased;
  final bool hasSecret;
  final String? issuer;
  final String? account;
  final int? digits;
  final int? period;
  final String? algorithm;

  @override
  CodeKind get kind => CodeKind.otpAuth;

  @override
  String get summary =>
      [issuer, account].whereType<String>().join(' · ').ifEmpty(title);

  @override
  bool get isSensitive => true;

  @override
  bool get neverStore => true;

  /// The secret key is never shown or copied as text.
  @override
  List<CodeField> get fields => [
    if (issuer != null) CodeField('Service', issuer!),
    if (account != null) CodeField('Account', account!),
    CodeField('Type', counterBased ? 'Counter-based' : 'Time-based'),
    if (digits != null) CodeField('Digits', '$digits'),
    if (period != null && !counterBased) CodeField('Period', '$period s'),
    if (algorithm != null) CodeField('Algorithm', algorithm!),
  ];

  @override
  String toPlainText() =>
      fields.map((f) => '${f.label}: ${f.value}').join('\n');
}

enum PaymentMethod {
  /// Bank transfer with IBAN/BIC (payment QR standards, `payto://`).
  bankTransfer('Bank transfer'),

  /// A payment-app link addressed to a payee ID.
  paymentLink('Payment app link');

  const PaymentMethod(this.label);
  final String label;
}

/// A payment request. Shown read-only; nothing is ever paid or opened.
final class PaymentContent extends CodeContent {
  const PaymentContent(
    super.raw, {
    required this.method,
    this.payeeName,
    this.account,
    this.accountLabel = 'Payee account',
    this.accountValid,
    this.bic,
    this.amount,
    this.currency,
    this.reference,
    this.message,
    this.extra = const [],
  });

  final PaymentMethod method;
  final String? payeeName;
  final String? account;
  final String accountLabel;

  /// IBAN checksum result, when [account] is an IBAN.
  final bool? accountValid;
  final String? bic;
  final String? amount;
  final String? currency;
  final String? reference;
  final String? message;
  final List<CodeField> extra;

  @override
  CodeKind get kind => CodeKind.payment;

  @override
  String get summary => [
    payeeName ?? account,
    if (amount != null) [amount, currency].whereType<String>().join(' '),
  ].whereType<String>().join(' · ').ifEmpty(title);

  @override
  bool get isSensitive => true;

  @override
  List<CodeField> get fields => [
    CodeField('Method', method.label),
    if (payeeName != null) CodeField('Payee', payeeName!),
    if (account != null) CodeField(accountLabel, account!),
    if (accountValid != null)
      CodeField(
        'Account check',
        accountValid! ? 'Valid checksum' : 'Checksum does not match',
      ),
    if (bic != null) CodeField('BIC', bic!),
    if (amount != null)
      CodeField('Amount', [amount, currency].whereType<String>().join(' ')),
    if (amount == null && currency != null) CodeField('Currency', currency!),
    if (reference != null) CodeField('Reference', reference!),
    if (message != null) CodeField('Message', message!),
    ...extra,
  ];
}

final class ProductContent extends CodeContent {
  const ProductContent(
    super.raw, {
    required this.number,
    required this.symbology,
    this.checkDigitValid,
    this.expanded,
    this.isbn,
  });

  final String number;
  final CodeSymbology symbology;

  /// null when the format has no check digit to verify.
  final bool? checkDigitValid;

  /// UPC-E expanded to its 12-digit UPC-A form.
  final String? expanded;

  /// Book number for 978/979 EAN-13 codes.
  final String? isbn;

  @override
  CodeKind get kind => CodeKind.product;

  @override
  String get summary => '$number · ${symbology.label}';

  @override
  List<CodeField> get fields => [
    CodeField('Number', number),
    CodeField('Barcode type', symbology.label),
    if (checkDigitValid != null)
      CodeField(
        'Check digit',
        checkDigitValid! ? 'Valid' : 'Invalid — the number may be misread',
      ),
    if (expanded != null) CodeField('Full number (UPC-A)', expanded!),
    if (isbn != null) CodeField('ISBN', isbn!),
  ];
}

/// Identity data from a PDF417 ID card barcode, as generic labelled fields.
final class IdCardContent extends CodeContent {
  const IdCardContent(
    super.raw, {
    required this.documentFields,
    this.documentType,
    this.issuerId,
    this.standardVersion,
  });

  final List<CodeField> documentFields;

  /// "Driving licence" or "Identification card", from the subfile type.
  final String? documentType;

  /// Issuer identification number (6 digits).
  final String? issuerId;
  final String? standardVersion;

  @override
  CodeKind get kind => CodeKind.idCard;

  @override
  String get summary {
    String? pick(String label) =>
        documentFields.where((f) => f.label == label).firstOrNull?.value;
    return pick('Full name') ??
        [
          pick('Given name') ?? pick('Given names'),
          pick('Family name'),
        ].whereType<String>().join(' ').ifEmpty(title);
  }

  @override
  bool get isSensitive => true;

  @override
  List<CodeField> get fields => [
    if (documentType != null) CodeField('Document', documentType!),
    ...documentFields,
    if (issuerId != null) CodeField('Issuer ID number', issuerId!),
    if (standardVersion != null) CodeField('Format version', standardVersion!),
  ];
}

String _oneLine(String s) {
  final line = s.trim().split(RegExp(r'[\r\n]+')).first;
  return line.length > 120 ? '${line.substring(0, 117)}…' : line;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

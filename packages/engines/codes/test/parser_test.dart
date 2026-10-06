import 'package:engine_codes/engine_codes.dart';
import 'package:test/test.dart';

T parseAs<T extends CodeContent>(
  String raw, {
  CodeSymbology symbology = CodeSymbology.qr,
}) {
  final c = CodeParser.parse(raw, symbology: symbology);
  expect(c, isA<T>(), reason: 'parsed as ${c.runtimeType}');
  return c as T;
}

String? field(CodeContent c, String label) =>
    c.fields.where((f) => f.label == label).firstOrNull?.value;

void main() {
  group('Wi-Fi', () {
    test('WPA network with password', () {
      final w = parseAs<WifiContent>('WIFI:S:HomeNet;T:WPA;P:s3cret!;;');
      expect(w.ssid, 'HomeNet');
      expect(w.security, WifiSecurity.wpa);
      expect(w.password, 's3cret!');
      expect(w.hidden, isFalse);
      expect(w.isSensitive, isTrue);
      expect(w.fields.firstWhere((f) => f.label == 'Password').secret, isTrue);
    });

    test('fields in any order, lower-case prefix, hidden flag', () {
      final w = parseAs<WifiContent>('wifi:T:WEP;P:abc;S:Cafe;H:true;;');
      expect(w.ssid, 'Cafe');
      expect(w.security, WifiSecurity.wep);
      expect(w.hidden, isTrue);
    });

    test('escaped special characters', () {
      final w = parseAs<WifiContent>(
        r'WIFI:S:My\;Net\:work\\x;T:WPA;P:pa\;ss\,wo\"rd\:;;',
      );
      expect(w.ssid, r'My;Net:work\x');
      expect(w.password, 'pa;ss,wo"rd:');
    });

    test('quoted values are unwrapped', () {
      final w = parseAs<WifiContent>(
        'WIFI:S:"Quoted Net";T:WPA;P:"12345678";;',
      );
      expect(w.ssid, 'Quoted Net');
      expect(w.password, '12345678');
    });

    test('open network has no password and is not sensitive', () {
      final w = parseAs<WifiContent>('WIFI:S:Guest;T:nopass;P:;;');
      expect(w.security, WifiSecurity.open);
      expect(w.password, isNull);
      expect(w.isSensitive, isFalse);
    });

    test('missing type with password means WPA; without means open', () {
      expect(parseAs<WifiContent>('WIFI:S:A;P:x;;').security, WifiSecurity.wpa);
      expect(parseAs<WifiContent>('WIFI:S:A;;').security, WifiSecurity.open);
    });

    test('WPA3 / SAE and enterprise', () {
      expect(
        parseAs<WifiContent>('WIFI:S:A;T:SAE;P:x;;').security,
        WifiSecurity.wpa,
      );
      final e = parseAs<WifiContent>(
        'WIFI:S:Corp;T:WPA2-EAP;E:PEAP;I:alice;PH2:MSCHAPV2;P:pw;;',
      );
      expect(e.security, WifiSecurity.enterprise);
      expect(e.eapMethod, 'PEAP');
      expect(e.identity, 'alice');
      expect(e.phase2, 'MSCHAPV2');
    });

    test('malformed Wi-Fi falls back to text', () {
      expect(CodeParser.parse('WIFI:'), isA<TextContent>());
      expect(CodeParser.parse('WIFI:T:WPA;P:x;;'), isA<TextContent>());
      expect(CodeParser.parse(r'WIFI:S:\'), isA<WifiContent>());
    });
  });

  group('vCard', () {
    test('3.0 with structured name, types, escapes and folding', () {
      const raw =
          'BEGIN:VCARD\r\n'
          'VERSION:3.0\r\n'
          'N:Doe;Jane;Q.;Dr.;PhD\r\n'
          'FN:Dr. Jane Q. Doe\\, PhD\r\n'
          'ORG:Example Inc.;Research\r\n'
          'TITLE:Lead\r\n'
          'TEL;TYPE=CELL,VOICE:+1 555 0100\r\n'
          'TEL;TYPE=WORK:+1 555 0199\r\n'
          'EMAIL;TYPE=INTERNET,WORK:jane@example.com\r\n'
          'ADR;TYPE=HOME:;;1 Main St;Springfield;ST;12345;Land\r\n'
          'URL:https://example.com\r\n'
          'NOTE:Line one\\nLine two with a very long text that is fol\r\n'
          ' ded here\r\n'
          'BDAY:1990-01-31\r\n'
          'END:VCARD\r\n';
      final c = parseAs<ContactContent>(raw);
      expect(c.version, '3.0');
      expect(c.format, ContactFormat.vcard);
      final card = c.card;
      expect(card.displayName, 'Dr. Jane Q. Doe, PhD');
      expect(card.familyName, 'Doe');
      expect(card.givenName, 'Jane');
      expect(card.organization, 'Example Inc., Research');
      expect(card.jobTitle, 'Lead');
      expect(card.phones, [
        const LabeledValue('+1 555 0100', type: 'Mobile'),
        const LabeledValue('+1 555 0199', type: 'Work'),
      ]);
      expect(
        card.emails.single,
        const LabeledValue('jane@example.com', type: 'Work'),
      );
      expect(
        card.addresses.single.value,
        '1 Main St\nSpringfield ST 12345\nLand',
      );
      expect(card.addresses.single.type, 'Home');
      expect(card.urls.single.value, 'https://example.com');
      expect(
        card.note,
        'Line one\nLine two with a very long text that is folded here',
      );
      expect(card.birthday, '1990-01-31');
      expect(field(c, 'Phone (Mobile)'), '+1 555 0100');
      expect(c.isSensitive, isFalse);
    });

    test('2.1 bare parameters, quoted-printable with soft breaks, charset', () {
      const raw =
          'BEGIN:VCARD\n'
          'VERSION:2.1\n'
          'N;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:M=C3=BCller;J=C3=B6rg\n'
          'TEL;WORK;VOICE:0301234\n'
          'TEL;CELL:0170123\n'
          'NOTE;ENCODING=QUOTED-PRINTABLE:first=\n'
          'second\n'
          'PHOTO;ENCODING=BASE64;TYPE=JPEG:AAAA\n'
          'END:VCARD';
      final c = parseAs<ContactContent>(raw);
      expect(c.version, '2.1');
      expect(c.card.familyName, 'Müller');
      expect(c.card.givenName, 'Jörg');
      expect(c.card.displayName, 'Jörg Müller');
      expect(c.card.phones.map((p) => p.type), ['Work', 'Mobile']);
      expect(c.card.note, 'firstsecond');
    });

    test('2.1 latin-1 quoted-printable', () {
      const raw =
          'BEGIN:VCARD\nVERSION:2.1\n'
          'FN;CHARSET=ISO-8859-1;ENCODING=QUOTED-PRINTABLE:Ren=E9\nEND:VCARD';
      expect(parseAs<ContactContent>(raw).card.displayName, 'René');
    });

    test('4.0 with tel: URIs, groups and quoted params', () {
      const raw =
          'BEGIN:VCARD\n'
          'VERSION:4.0\n'
          'FN:Ana\n'
          'item1.TEL;VALUE=uri;TYPE="voice,cell":tel:+44-20-7946-0000\n'
          'EMAIL;PREF=1:mailto:ana@example.org\n'
          'END:VCARD';
      final c = parseAs<ContactContent>(raw);
      expect(c.version, '4.0');
      expect(
        c.card.phones.single,
        const LabeledValue('+44-20-7946-0000', type: 'Mobile'),
      );
      expect(c.card.emails.single.value, 'ana@example.org');
    });

    test('only the first of several cards is read', () {
      const raw =
          'BEGIN:VCARD\nFN:One\nEND:VCARD\nBEGIN:VCARD\nFN:Two\nEND:VCARD';
      expect(parseAs<ContactContent>(raw).card.displayName, 'One');
    });

    test('empty or broken vCard falls back to text', () {
      expect(CodeParser.parse('BEGIN:VCARD\nEND:VCARD'), isA<TextContent>());
      expect(CodeParser.parse('BEGIN:VCARD'), isA<TextContent>());
      expect(
        CodeParser.parse('BEGIN:VCARD\n:::\n;;;\nEND'),
        isA<TextContent>(),
      );
    });

    test('toVCard round trip keeps the details', () {
      const card = ContactCard(
        familyName: 'Doe',
        givenName: 'John',
        organization: 'A; B, C',
        jobTitle: 'CTO',
        phones: [LabeledValue('+1 555', type: 'Mobile')],
        emails: [LabeledValue('j@x.io', type: 'Work')],
        urls: [LabeledValue('https://x.io')],
        addresses: [LabeledValue('1 Road', type: 'Home')],
        note: 'Hello\nWorld',
        birthday: '2000-02-29',
      );
      final back = parseAs<ContactContent>(card.toVCard()).card;
      expect(back.displayName, 'John Doe');
      expect(back.familyName, 'Doe');
      expect(back.givenName, 'John');
      expect(back.organization, 'A; B, C');
      expect(back.jobTitle, 'CTO');
      expect(back.phones.single, const LabeledValue('+1 555', type: 'Mobile'));
      expect(back.emails.single, const LabeledValue('j@x.io', type: 'Work'));
      expect(back.urls.single.value, 'https://x.io');
      expect(back.addresses.single, const LabeledValue('1 Road', type: 'Home'));
      expect(back.note, 'Hello\nWorld');
      expect(back.birthday, '2000-02-29');
    });
  });

  group('MECARD', () {
    test('fields, escapes and order', () {
      final c = parseAs<ContactContent>(
        'MECARD:TEL:+15550100;N:Smith,Alex;EMAIL:alex@example.com;'
        r'ADR:1 Main St\, Apt 2,Town;URL:http://alex.example;NOTE:Hi\; there;BDAY:19851231;ORG:Acme;;',
      );
      expect(c.format, ContactFormat.mecard);
      expect(c.card.familyName, 'Smith');
      expect(c.card.givenName, 'Alex');
      expect(c.card.displayName, 'Alex Smith');
      expect(c.card.phones.single.value, '+15550100');
      expect(c.card.emails.single.value, 'alex@example.com');
      expect(c.card.urls.single.value, 'http://alex.example');
      expect(c.card.note, 'Hi; there');
      expect(c.card.birthday, '1985-12-31');
      expect(c.card.organization, 'Acme');
      expect(c.card.addresses.single.value, '1 Main St, Apt 2, Town');
    });

    test('single name and multiple phones', () {
      final c = parseAs<ContactContent>('mecard:N:Kim;TEL:1;TEL:2;;');
      expect(c.card.displayName, 'Kim');
      expect(c.card.phones.length, 2);
    });

    test('empty MECARD is text', () {
      expect(CodeParser.parse('MECARD:;;'), isA<TextContent>());
    });
  });

  group('links', () {
    test('https link', () {
      final u = parseAs<UrlContent>('https://example.com/path?q=1');
      expect(u.url, 'https://example.com/path?q=1');
      expect(u.safety.warnings, isEmpty);
      expect(u.canOpen, isTrue);
      expect(field(u, 'Site'), 'example.com');
    });

    test('www without scheme gets https', () {
      expect(
        parseAs<UrlContent>('www.example.org').url,
        'https://www.example.org',
      );
    });

    test('bookmark with title, mismatched title is flagged', () {
      final ok = parseAs<UrlContent>(
        'MEBKM:TITLE:Example;URL:https://example.com;;',
      );
      expect(ok.linkText, 'Example');
      expect(ok.safety.warnings, isEmpty);
      final bad = parseAs<UrlContent>(
        r'MEBKM:TITLE:mybank.com login;URL:https\://evil.example.net/login;;',
      );
      expect(bad.url, 'https://evil.example.net/login');
      expect(bad.safety.warnings, contains(UrlWarning.mismatchedText));
    });

    test('URLTO', () {
      final u = parseAs<UrlContent>('URLTO:Shop:shop.example.com');
      expect(u.url, 'https://shop.example.com');
      expect(u.linkText, 'Shop');
    });

    test('text with spaces is not a link', () {
      expect(CodeParser.parse('https://a.com and more'), isA<TextContent>());
    });

    test('javascript bookmark cannot be opened', () {
      final u = parseAs<UrlContent>(
        r'MEBKM:TITLE:x;URL:javascript\:alert(1);;',
      );
      expect(u.canOpen, isFalse);
      expect(u.safety.warnings, [UrlWarning.dangerousScheme]);
    });
  });

  group('email', () {
    test('mailto with several recipients and RFC 6068 params', () {
      final e = parseAs<EmailContent>(
        'mailto:a@x.com,b@y.org?subject=Hello%20there&body=1+1%3D2&cc=c@z.net',
      );
      expect(e.to, ['a@x.com', 'b@y.org']);
      expect(e.cc, ['c@z.net']);
      expect(e.subject, 'Hello there');
      expect(e.body, '1+1=2');
      expect(e.summary, 'a@x.com, b@y.org');
    });

    test('MATMSG', () {
      final e = parseAs<EmailContent>(
        r'MATMSG:TO:x@example.com;SUB:Hi\; you;BODY:Text: here;;',
      );
      expect(e.to, ['x@example.com']);
      expect(e.subject, 'Hi; you');
      expect(e.body, 'Text: here');
    });

    test('SMTP form and bare address', () {
      final s = parseAs<EmailContent>('SMTP:a@b.co:Sub:Body:with colon');
      expect(s.subject, 'Sub');
      expect(s.body, 'Body:with colon');
      expect(parseAs<EmailContent>('someone@example.com').to, [
        'someone@example.com',
      ]);
    });

    test('mailto link is rebuilt with encoding', () {
      final e = parseAs<EmailContent>('mailto:a@x.com?subject=A%26B');
      expect(e.mailtoUri, 'mailto:a@x.com?subject=A%26B');
    });

    test('malformed percent escapes do not throw', () {
      final e = parseAs<EmailContent>('mailto:a@x.com?subject=%E0%A4%A&body=%');
      expect(e.subject, '%E0%A4%A');
    });
  });

  group('phone and SMS', () {
    test('tel', () {
      final p = parseAs<PhoneContent>('tel:+1-555-0100');
      expect(p.number, '+1-555-0100');
      expect(p.telUri, 'tel:+15550100');
      expect(CodeParser.parse('tel:'), isA<TextContent>());
      expect(CodeParser.parse('tel:abc'), isA<TextContent>());
    });

    test('SMSTO with and without body', () {
      final s = parseAs<SmsContent>('SMSTO:+15550100:Hello: world');
      expect(s.numbers, ['+15550100']);
      expect(s.body, 'Hello: world');
      expect(s.smsUri, 'sms:+15550100?body=Hello%3A%20world');
      expect(parseAs<SmsContent>('smsto:123').body, isNull);
    });

    test('sms: URI with several numbers and body', () {
      final s = parseAs<SmsContent>('sms:+1555,+1666?body=Hi%20there');
      expect(s.numbers, ['+1555', '+1666']);
      expect(s.body, 'Hi there');
    });
  });

  group('geo', () {
    test('coordinates with altitude and parameters', () {
      final g = parseAs<GeoContent>('geo:37.786971,-122.399677,12;u=35');
      expect(g.latitude, closeTo(37.786971, 1e-9));
      expect(g.longitude, closeTo(-122.399677, 1e-9));
      expect(g.altitude, 12);
      expect(g.coordinates, '37.786971, -122.399677');
      expect(g.geoUri, 'geo:37.786971,-122.399677?q=37.786971,-122.399677');
    });

    test('search-only location', () {
      final g = parseAs<GeoContent>('geo:0,0?q=1+Main+Street');
      expect(g.hasPoint, isFalse);
      expect(g.query, '1 Main Street');
      expect(g.geoUri, 'geo:0,0?q=1%20Main%20Street');
      expect(g.appleMapsUri, 'https://maps.apple.com/?q=1%20Main%20Street');
    });

    test('out-of-range or junk coordinates are text', () {
      expect(CodeParser.parse('geo:91,0'), isA<TextContent>());
      expect(CodeParser.parse('geo:1,200'), isA<TextContent>());
      expect(CodeParser.parse('geo:abc,def'), isA<TextContent>());
      expect(CodeParser.parse('geo:'), isA<TextContent>());
    });
  });

  group('calendar event', () {
    test('VEVENT in VCALENDAR with UTC times', () {
      const raw =
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n'
          'SUMMARY:Team meeting\\, weekly\r\n'
          'DTSTART:20260315T090000Z\r\nDTEND:20260315T100000Z\r\n'
          'LOCATION:Room 1\r\nDESCRIPTION:Agenda\\nItem\r\n'
          'ORGANIZER;CN=Sam:mailto:sam@example.com\r\n'
          'BEGIN:VALARM\r\nDESCRIPTION:Reminder\r\nEND:VALARM\r\n'
          'END:VEVENT\r\nEND:VCALENDAR';
      final e = parseAs<EventContent>(raw);
      expect(e.summaryText, 'Team meeting, weekly');
      expect(e.start!.format(), '2026-03-15 09:00 UTC');
      expect(e.end!.format(), '2026-03-15 10:00 UTC');
      expect(e.location, 'Room 1');
      expect(e.description, 'Agenda\nItem');
      expect(e.organizer, 'Sam <sam@example.com>');
      final ics = e.toIcs();
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('BEGIN:VEVENT\r\n'));
      expect(ics, contains('BEGIN:VALARM'));
      expect(ics.trimRight(), endsWith('END:VCALENDAR'));
      // The exported file parses back to the same event.
      expect(parseAs<EventContent>(ics).summaryText, 'Team meeting, weekly');
    });

    test('bare VEVENT, all-day, TZID, DURATION, LF line ends', () {
      final e = parseAs<EventContent>(
        'BEGIN:VEVENT\nSUMMARY:Trip\nDTSTART;VALUE=DATE:20261224\n'
        'DURATION:P2D\nEND:VEVENT',
      );
      expect(e.start!.allDay, isTrue);
      expect(e.start!.format(), '2026-12-24');
      expect(e.end!.format(), '2026-12-26');
      final z = parseAs<EventContent>(
        'BEGIN:VEVENT\nSUMMARY:Call\nDTSTART;TZID=Europe/Paris:20260101T083000\n'
        'DURATION:PT1H30M\nEND:VEVENT',
      );
      expect(z.start!.format(), '2026-01-01 08:30 (Europe/Paris)');
      expect(z.end!.format(), '2026-01-01 10:00 (Europe/Paris)');
    });

    test('missing END and bad dates are tolerated', () {
      final e = parseAs<EventContent>(
        'BEGIN:VEVENT\nSUMMARY:X\nDTSTART:2026XX01',
      );
      expect(e.start, isNull);
      expect(e.toIcs(), contains('END:VEVENT'));
      expect(CodeParser.parse('BEGIN:VEVENT\nEND:VEVENT'), isA<TextContent>());
    });
  });

  group('otpauth', () {
    test('keeps issuer and account, never exposes the secret', () {
      final o = parseAs<OtpAuthContent>(
        'otpauth://totp/GitHub:me%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30',
      );
      expect(o.issuer, 'GitHub');
      expect(o.account, 'me@example.com');
      expect(o.hasSecret, isTrue);
      expect(o.counterBased, isFalse);
      expect(o.isSensitive, isTrue);
      expect(o.neverStore, isTrue);
      expect(o.toPlainText(), isNot(contains('JBSWY3DPEHPK3PXP')));
      expect(o.fields.map((f) => f.value), isNot(contains('JBSWY3DPEHPK3PXP')));
    });

    test('hotp, label without issuer', () {
      final o = parseAs<OtpAuthContent>(
        'otpauth://hotp/alice?secret=AAAA&counter=1',
      );
      expect(o.counterBased, isTrue);
      expect(o.account, 'alice');
      expect(o.issuer, isNull);
    });

    test('unknown type is text', () {
      expect(CodeParser.parse('otpauth://xyz/a?secret=A'), isA<TextContent>());
      expect(CodeParser.parse('otpauth://'), isA<TextContent>());
    });
  });

  group('payment requests', () {
    test('BCD bank-transfer code', () {
      const raw =
          'BCD\n002\n1\nSCT\nBFSWDE33BER\nWikimedia Foerdergesellschaft\n'
          'DE33100205000001194700\nEUR123.4\nCHAR\n\nDonation\nThanks';
      final p = parseAs<PaymentContent>(raw);
      expect(p.method, PaymentMethod.bankTransfer);
      expect(p.payeeName, 'Wikimedia Foerdergesellschaft');
      expect(p.account, 'DE33 1002 0500 0001 1947 00');
      expect(p.accountValid, isTrue);
      expect(p.bic, 'BFSWDE33BER');
      expect(p.amount, '123.40');
      expect(p.currency, 'EUR');
      expect(p.message, 'Donation');
      expect(p.title, 'Payment request');
      expect(p.isSensitive, isTrue);
      expect(field(p, 'Amount'), '123.40 EUR');
      expect(field(p, 'Purpose code'), 'CHAR');
      expect(field(p, 'Note to payer'), 'Thanks');
    });

    test('BCD with a wrong IBAN checksum and CRLF', () {
      final p = parseAs<PaymentContent>(
        'BCD\r\n001\r\n1\r\nSCT\r\nBIC\r\nName\r\nDE00100205000001194700\r\n',
      );
      expect(p.accountValid, isFalse);
      expect(field(p, 'Account check'), 'Checksum does not match');
    });

    test('BCD with wrong service tag or missing IBAN is text', () {
      expect(
        CodeParser.parse('BCD\n002\n1\nXXX\n\nName\nDE33100205000001194700'),
        isA<TextContent>(),
      );
      expect(
        CodeParser.parse('BCD\n002\n1\nSCT\n\nName\n\n'),
        isA<TextContent>(),
      );
    });

    test('payment-app link', () {
      final p = parseAs<PaymentContent>(
        'upi://pay?pa=shop@bank&pn=Corner+Shop&am=250&cu=INR&tn=Order%2042&tr=R1',
      );
      expect(p.method, PaymentMethod.paymentLink);
      expect(p.account, 'shop@bank');
      expect(p.accountLabel, 'Payee address');
      expect(p.payeeName, 'Corner Shop');
      expect(p.amount, '250.00');
      expect(p.currency, 'INR');
      expect(p.message, 'Order 42');
      expect(p.reference, 'R1');
      // Labels stay generic.
      for (final f in p.fields) {
        expect(f.label.toLowerCase(), isNot(contains('upi')));
      }
      expect(field(p, 'Method'), 'Payment app link');
    });

    test('payment link without payee is text', () {
      expect(CodeParser.parse('upi://pay?am=1'), isA<TextContent>());
    });

    test('payto IBAN link', () {
      final p = parseAs<PaymentContent>(
        'payto://iban/DE75512108001245126199?amount=EUR:200.0&message=Hi&receiver-name=Ann',
      );
      expect(p.account, 'DE75 5121 0800 1245 1261 99');
      expect(p.accountValid, isTrue);
      expect(p.amount, '200.00');
      expect(p.currency, 'EUR');
      expect(p.payeeName, 'Ann');
    });

    test('IBAN helpers', () {
      expect(isValidIban('GB82 WEST 1234 5698 7654 32'), isTrue);
      expect(isValidIban('GB82WEST12345698765433'), isFalse);
      expect(isValidIban('nonsense'), isFalse);
      expect(
        formatIban('GB82WEST12345698765432'),
        'GB82 WEST 1234 5698 7654 32',
      );
    });
  });

  group('product barcodes', () {
    test('EAN-13 valid and book numbers', () {
      final p = parseAs<ProductContent>(
        '9780306406157',
        symbology: CodeSymbology.ean13,
      );
      expect(p.checkDigitValid, isTrue);
      expect(p.isbn, '9780306406157 (ISBN-10: 0306406152)');
      expect(field(p, 'Barcode type'), 'EAN-13');
      expect(field(p, 'Check digit'), 'Valid');
    });

    test('EAN-13 invalid check digit', () {
      final p = parseAs<ProductContent>(
        '4006381333932',
        symbology: CodeSymbology.ean13,
      );
      expect(p.checkDigitValid, isFalse);
      expect(
        parseAs<ProductContent>(
          '4006381333931',
          symbology: CodeSymbology.ean13,
        ).checkDigitValid,
        isTrue,
      );
    });

    test('EAN-8, UPC-A, ITF-14', () {
      expect(
        parseAs<ProductContent>(
          '96385074',
          symbology: CodeSymbology.ean8,
        ).checkDigitValid,
        isTrue,
      );
      expect(
        parseAs<ProductContent>(
          '036000291452',
          symbology: CodeSymbology.upcA,
        ).checkDigitValid,
        isTrue,
      );
      expect(
        parseAs<ProductContent>(
          '10012345000017',
          symbology: CodeSymbology.itf,
        ).checkDigitValid,
        isTrue,
      );
    });

    test('UPC-E expands to UPC-A for validation', () {
      final p = parseAs<ProductContent>(
        '04252614',
        symbology: CodeSymbology.upcE,
      );
      expect(p.expanded, '042100005264');
      expect(p.checkDigitValid, isTrue);
      expect(expandUpcE('01234565'), '012345000065');
      expect(expandUpcE('01234531'), '012300000451');
      expect(expandUpcE('01234543'), '012340000053');
      expect(expandUpcE('21234565'), isNull);
    });

    test('wrong length or letters fall back to text', () {
      expect(
        CodeParser.parse('12345', symbology: CodeSymbology.ean13),
        isA<TextContent>(),
      );
      expect(
        CodeParser.parse('ABC', symbology: CodeSymbology.ean8),
        isA<TextContent>(),
      );
    });

    test('Code 128 carrying a link is a link', () {
      expect(
        CodeParser.parse(
          'https://example.com',
          symbology: CodeSymbology.code128,
        ),
        isA<UrlContent>(),
      );
    });

    test('GTIN helpers', () {
      expect(gtinCheckDigit('400638133393'), 1);
      expect(isValidGtin('x'), isFalse);
    });
  });

  group('ID card barcode', () {
    const card =
        '@\n\x1e\rANSI 636014090102DL00410279ZC03200024DLDAQD1234562\n'
        'DCSPUBLIC\nDDEN\nDACJOHN\nDDFN\nDADQUINCY\nDDGN\nDCAC\nDCBNONE\n'
        'DCDNONE\nDBD08312013\nDBB08311977\nDBA08312022\nDBC1\nDAU069 IN\n'
        'DAYBRO\nDAG789 E OAK ST\nDAIANYTOWN\nDAJCA\nDAK902230000  \n'
        'DCF83D9BN217QO983B1\nDCGUSA\nDAW180\nDAZBRO\nDDK1\r'
        'ZCZCAY\nZCBCORR LENS\r';

    test('header, subfile and elements map to generic labels', () {
      final c = parseAs<IdCardContent>(card, symbology: CodeSymbology.pdf417);
      expect(c.title, 'ID card barcode');
      expect(c.documentType, 'Driving licence');
      expect(c.issuerId, '636014');
      expect(c.standardVersion, '09');
      expect(field(c, 'ID number'), 'D1234562');
      expect(field(c, 'Family name'), 'PUBLIC');
      expect(field(c, 'Given name'), 'JOHN');
      expect(field(c, 'Middle names'), 'QUINCY');
      expect(field(c, 'Date of birth'), '1977-08-31');
      expect(field(c, 'Issue date'), '2013-08-31');
      expect(field(c, 'Expiry date'), '2022-08-31');
      expect(field(c, 'Sex'), 'Male');
      expect(field(c, 'Height'), '69 in');
      expect(field(c, 'Eye colour'), 'Brown');
      expect(field(c, 'Address'), '789 E OAK ST');
      expect(field(c, 'Region'), 'CA');
      expect(field(c, 'Postal code'), '90223');
      expect(field(c, 'Weight'), '180 lb');
      expect(field(c, 'Organ donor'), 'Yes');
      expect(c.summary, 'JOHN PUBLIC');
      expect(c.isSensitive, isTrue);
    });

    test('labels never name a country or programme', () {
      final c = parseAs<IdCardContent>(card, symbology: CodeSymbology.pdf417);
      final labels = c.fields.map((f) => f.label.toLowerCase()).join(' ');
      for (final word in [
        'state',
        'aamva',
        'dmv',
        'us ',
        'american',
        'canad',
      ]) {
        expect(labels, isNot(contains(word)));
      }
    });

    test('ID subfile, CCYYMMDD dates and full-name element', () {
      const raw =
          '@\n\x1e\rANSI 636012030001ID00310123IDDAAJONES,ANN,MARIE\n'
          'DBB19900115\nDBC2\nDAQ123456789\nDBA20300115\r';
      final c = parseAs<IdCardContent>(raw);
      expect(c.documentType, 'Identification card');
      expect(field(c, 'Full name'), 'JONES ANN MARIE');
      expect(field(c, 'Date of birth'), '1990-01-15');
      expect(field(c, 'Sex'), 'Female');
    });

    test('PDF417 without header needs clear identity elements', () {
      expect(
        CodeParser.parse(
          'DAQ123\nDCSDOE\nDACJO',
          symbology: CodeSymbology.pdf417,
        ),
        isA<IdCardContent>(),
      );
      expect(
        CodeParser.parse(
          'Some shipping label',
          symbology: CodeSymbology.pdf417,
        ),
        isA<TextContent>(),
      );
      expect(CodeParser.parse('DAQ123\nDCSDOE'), isA<TextContent>());
    });

    test('truncated header does not throw', () {
      expect(CodeParser.parse('@\nANSI 63'), isA<TextContent>());
      expect(formatCardDate('13452020'), '13452020');
    });
  });

  group('robustness', () {
    test('plain text and empty input', () {
      expect(parseAs<TextContent>('Hello, world').summary, 'Hello, world');
      expect(CodeParser.parse(''), isA<TextContent>());
      expect(CodeParser.parse('   '), isA<TextContent>());
    });

    test('very long input stays text', () {
      final long = 'WIFI:S:${'a' * 20000};;';
      expect(CodeParser.parse(long), isA<TextContent>());
    });

    test('fuzzed prefixes never throw', () {
      const prefixes = [
        'WIFI:',
        'MECARD:',
        'BEGIN:VCARD',
        'BEGIN:VEVENT',
        'MATMSG:',
        'mailto:',
        'SMTP:',
        'tel:',
        'SMSTO:',
        'sms:',
        'geo:',
        'otpauth://',
        'BCD\n',
        'payto://',
        'upi://pay?',
        'MEBKM:',
        'URLTO:',
        'http://',
        'www.',
        '@\nANSI ',
      ];
      const junk = [
        '',
        ';',
        ':',
        r'\',
        '%',
        '%%%',
        ';;;;',
        ':::',
        '\n\n',
        '?',
        '&&=',
        '\u0000',
        'é',
        '"',
        r'\;',
        '=',
        'xn--',
        '[::1]',
        '////',
      ];
      for (final p in prefixes) {
        for (final j in junk) {
          for (final s in CodeSymbology.values) {
            final c = CodeParser.parse('$p$j', symbology: s);
            expect(c.raw, '$p$j');
            // Rendering fields must not throw either.
            c
              ..fields
              ..summary
              ..toPlainText();
          }
        }
      }
    });

    test('scanned code helper', () {
      final c = ScannedCode.from(rawValue: null, symbology: CodeSymbology.qr);
      expect(c.raw, '');
      expect(CodeParser.parseCode(c), isA<TextContent>());
      expect(CodeSymbology.byName('nope'), CodeSymbology.unknown);
      expect(CodeKind.byName('wifi'), CodeKind.wifi);
    });
  });
}

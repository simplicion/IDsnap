import 'package:engine_codes/engine_codes.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import 'support/qr_decoder.dart';

String roundTrip(String data, {QrErrorLevel level = QrErrorLevel.medium}) {
  final m = QrMatrix.tryEncode(data, level: level)!;
  final decoded = decodeQr(m.size, m.isDark);
  expect(decoded.version, m.version);
  return decoded.text;
}

void main() {
  group('payload builders parse back', () {
    test('Wi-Fi with special characters', () {
      final payload = QrPayload.wifi(
        ssid: r'Cafe;Net:"1"\',
        password: 'p;a,s:s"',
        hidden: true,
      );
      final w = CodeParser.parse(payload) as WifiContent;
      expect(w.ssid, r'Cafe;Net:"1"\');
      expect(w.password, 'p;a,s:s"');
      expect(w.security, WifiSecurity.wpa);
      expect(w.hidden, isTrue);
    });

    test('Wi-Fi open and WEP', () {
      final open =
          CodeParser.parse(
                QrPayload.wifi(
                  ssid: 'Guest',
                  password: 'ignored',
                  security: WifiSecurity.open,
                ),
              )
              as WifiContent;
      expect(open.security, WifiSecurity.open);
      expect(open.password, isNull);
      final wep =
          CodeParser.parse(
                QrPayload.wifi(
                  ssid: 'Old',
                  password: 'abc',
                  security: WifiSecurity.wep,
                ),
              )
              as WifiContent;
      expect(wep.security, WifiSecurity.wep);
    });

    test('email, phone, SMS, URL', () {
      final e =
          CodeParser.parse(
                QrPayload.email(
                  to: 'a@b.co',
                  subject: 'Hi & bye',
                  body: 'Line 1\nLine 2+',
                ),
              )
              as EmailContent;
      expect(e.to, ['a@b.co']);
      expect(e.subject, 'Hi & bye');
      expect(e.body, 'Line 1\nLine 2+');

      final p =
          CodeParser.parse(QrPayload.phone('+1 555 0100')) as PhoneContent;
      expect(p.number, '+15550100');

      final s =
          CodeParser.parse(
                QrPayload.sms(number: '+1 (555) 0100', message: 'Hello: there'),
              )
              as SmsContent;
      expect(s.numbers, ['+15550100']);
      expect(s.body, 'Hello: there');

      expect(QrPayload.url('example.com'), 'https://example.com');
      expect(QrPayload.url('http://x.io'), 'http://x.io');
      expect(CodeParser.parse(QrPayload.url('example.com')), isA<UrlContent>());
    });

    test('contact', () {
      final c =
          CodeParser.parse(
                QrPayload.contact(
                  const ContactCard(
                    givenName: 'Ana',
                    familyName: 'Lee',
                    phones: [LabeledValue('+1555', type: 'Mobile')],
                    emails: [LabeledValue('ana@x.io')],
                  ),
                ),
              )
              as ContactContent;
      expect(c.card.displayName, 'Ana Lee');
      expect(c.card.phones.single.value, '+1555');
      expect(c.card.emails.single.value, 'ana@x.io');
    });
  });

  group('QR encoding', () {
    test('round trips through an independent decoder', () {
      for (final data in [
        'Hello',
        'https://example.com/a?b=c',
        QrPayload.wifi(ssid: 'Home', password: 'secret'),
        'Ünïcödé ✓ 日本語',
        List.filled(300, 'x').join(),
      ]) {
        expect(roundTrip(data), data);
      }
    });

    test('every error-correction level', () {
      for (final level in QrErrorLevel.values) {
        final m = QrMatrix.tryEncode('level test', level: level)!;
        final d = decodeQr(m.size, m.isDark);
        expect(d.text, 'level test');
        expect(d.levelBits, level.qrValue);
        expect(m.level, level);
      }
    });

    test('higher correction needs a bigger symbol for the same data', () {
      final data = List.filled(100, 'y').join();
      final low = QrMatrix.tryEncode(data, level: QrErrorLevel.low)!;
      final high = QrMatrix.tryEncode(data, level: QrErrorLevel.high)!;
      expect(high.size, greaterThan(low.size));
    });

    test('large payloads use version 7+ and still decode', () {
      final data = List.filled(1200, 'z').join();
      final m = QrMatrix.tryEncode(data, level: QrErrorLevel.low)!;
      expect(m.version, greaterThanOrEqualTo(7));
      expect(decodeQr(m.size, m.isDark).text, data);
    });

    test('too long for any QR returns null', () {
      final data = List.filled(5000, 'a').join();
      expect(QrMatrix.tryEncode(data, level: QrErrorLevel.high), isNull);
    });

    test('PNG export decodes back to the same payload', () {
      const data = 'https://example.com/png';
      final m = QrMatrix.tryEncode(data)!;
      final png = m.toPng(pixels: 400);
      final image = img.decodePng(png)!;
      final total = m.size + QrMatrix.quietZone * 2;
      expect(image.width, image.height);
      expect(image.width % total, 0);
      final module = image.width ~/ total;
      // The quiet zone is white.
      expect(image.getPixel(1, 1).r, 255);
      bool dark(int r, int c) =>
          image
              .getPixel(
                (c + QrMatrix.quietZone) * module + module ~/ 2,
                (r + QrMatrix.quietZone) * module + module ~/ 2,
              )
              .r <
          128;
      expect(decodeQr(m.size, dark).text, data);
    });

    test('tiny PNG requests still get one pixel per module', () {
      final m = QrMatrix.tryEncode('a')!;
      final image = img.decodePng(m.toPng(pixels: 1))!;
      expect(image.width, m.size + QrMatrix.quietZone * 2);
    });
  });
}
